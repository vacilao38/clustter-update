import 'dart:async';
import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;
import 'package:clustter_update/clustter_update.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String feed(String version, {String platform = 'windows', String? page}) =>
    jsonEncode({
      'protocol': 'clustter.update',
      'schema': 1,
      'apps': {
        'chain': {
          platform: {'version': version, 'page': page ?? '$clustterSite#chain'},
        },
      },
    });

class MemoryStore implements UpdateStore {
  Map<String, dynamic> data = {};
  @override
  Future<Map<String, dynamic>> read() async => {...data};
  @override
  Future<void> write(Map<String, dynamic> value) async {
    data = {...value};
  }
}

void main() {
  testWidgets(
    'builder banner supports hover and dismissal without replacing the current route',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = UpdateController(
        appId: 'chain',
        platform: 'windows',
        store: MemoryStore(),
        currentVersion: () async => '1.0.0',
        fetch: () async => feed('1.1.0'),
      );
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          builder: (context, child) => ClustterUpdate(
            appId: 'chain',
            appName: 'Chain',
            controller: controller,
            child: child!,
          ),
          home: const Scaffold(body: Text('Biblioteca')),
        ),
      );
      await tester.pumpAndSettle();
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              const Scaffold(body: TextField(key: ValueKey('draft'))),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('draft')),
        'Rascunho preservado',
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(
        tester.getCenter(find.byTooltip('Lembrar apenas na próxima versão')),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
      expect(find.text('Lembrar apenas na próxima versão'), findsOneWidget);
      expect(find.text('Rascunho preservado'), findsOneWidget);
      await tester.tap(find.byTooltip('Lembrar apenas na próxima versão'));
      await mouse.removePointer();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('1.1.0 está disponível'), findsNothing);
      expect(find.text('Rascunho preservado'), findsOneWidget);
      expect(nav.currentState!.canPop(), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
  test('numeric versions, prereleases and Android ABI build numbers', () {
    final ordered = [
      '1.0.0-alpha',
      '1.0.0-alpha.2',
      '1.0.0-alpha.10',
      '1.0.0-beta',
      '1.0.0',
      '1.2.0',
      '1.10.0',
      '2.0.0',
    ];
    for (var i = 1; i < ordered.length; i++) {
      expect(
        AppVersion.parse(
          ordered[i],
        ).compareTo(AppVersion.parse(ordered[i - 1])),
        greaterThan(0),
      );
    }
    expect(
      AppVersion.parse('1.1.0+2002').compareTo(AppVersion.parse('1.1.0+2')),
      0,
    );
    for (final invalid in [
      '1.2',
      '01.2.3',
      '1.0.0-alpha.01',
      '1.0.0-..',
      'latest',
    ]) {
      expect(() => AppVersion.parse(invalid), throwsFormatException);
    }
  });
  test(
    'schema and platform isolate releases; only the official product page opens',
    () {
      expect(readUpdate(feed('1.1.0'), 'chain', 'android'), isNull);
      expect(readUpdate(feed('1.1.0'), 'folk', 'windows'), isNull);
      expect(readUpdate(feed('1.1.0'), 'chain', 'windows')!.version, '1.1.0');
      for (final page in [
        'http://vacilao38.github.io/clustter-cores-downloads/#chain',
        'https://evil.example/#chain',
        '$clustterSite#folk',
        '$clustterSite?token=secret#chain',
        'https://vacilao38.github.io/other/#chain',
      ]) {
        expect(
          () => readUpdate(feed('1.1.0', page: page), 'chain', 'windows'),
          throwsFormatException,
        );
      }
      expect(
        () => readUpdate(
          '{"protocol":"clustter.update","schema":2,"apps":{}}',
          'chain',
          'windows',
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'cache corruption recovers; dismiss persists; a newer release returns',
    () async {
      final store = MemoryStore()
        ..data = {
          'release': {'bad': true},
          'dismissed': 7,
        };
      var now = DateTime.utc(2026, 10, 24), version = '1.1.0', calls = 0;
      UpdateController create() => UpdateController(
        appId: 'chain',
        platform: 'windows',
        store: store,
        currentVersion: () async => '1.0.0',
        fetch: () async {
          calls++;
          return feed(version);
        },
        clock: () => now,
      );
      final c = create();
      await c.initialize();
      expect(c.ready, isTrue);
      expect(c.showBanner, isTrue);
      expect(calls, 1);
      await c.check();
      expect(calls, 1);
      await c.dismiss();
      expect(c.showBanner, isFalse);
      c.dispose();
      final next = create();
      await next.initialize();
      expect(next.showBanner, isFalse);
      expect(calls, 1);
      now = now.add(const Duration(minutes: 31));
      version = '1.2.0';
      await next.check();
      expect(next.showBanner, isTrue);
      expect(calls, 2);
      next.dispose();
    },
  );
  test(
    'offline, equal and older versions never interrupt local app work',
    () async {
      for (final value in ['1.0.0', '0.9.0', 'offline']) {
        final c = UpdateController(
          appId: 'chain',
          platform: 'windows',
          store: MemoryStore(),
          currentVersion: () async => '1.0.0',
          fetch: () async {
            if (value == 'offline') throw const FormatException('offline');
            return feed(value);
          },
        );
        await c.initialize();
        expect(c.showBanner, isFalse);
        c.dispose();
      }
    },
  );
  test('dispose during a request drops its result safely', () async {
    final response = Completer<String>();
    final c = UpdateController(
      appId: 'chain',
      platform: 'windows',
      store: MemoryStore(),
      currentVersion: () async => '1.0.0',
      fetch: () => response.future,
    );
    final started = c.initialize();
    await Future<void>.delayed(Duration.zero);
    c.dispose();
    response.complete(feed('1.1.0'));
    await started;
    expect(c.available, isNull);
  });
  for (final size in [const Size(360, 740), const Size(1366, 900)]) {
    testWidgets('notice opens the site and preserves workspace at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = UpdateController(
        appId: 'chain',
        platform: 'windows',
        store: MemoryStore(),
        currentVersion: () async => '1.0.0',
        fetch: () async => feed('1.1.0'),
      );
      Uri? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: ClustterUpdate(
            appId: 'chain',
            appName: 'Chain',
            controller: c,
            openPage: (uri) async {
              opened = uri;
              return true;
            },
            child: const Scaffold(body: Text('Meu trabalho local')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('1.1.0 está disponível'), findsOneWidget);
      expect(find.text('Meu trabalho local'), findsOneWidget);
      await tester.tap(find.text('Baixar no site'));
      await tester.pumpAndSettle();
      expect(opened.toString(), '$clustterSite#chain');
      await tester.tap(find.byTooltip('Lembrar apenas na próxima versão'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1.1.0 está disponível'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    });
  }
}
