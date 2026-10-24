import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'protocol.dart';

abstract class UpdateStore {
  Future<Map<String, dynamic>> read();
  Future<void> write(Map<String, dynamic> data);
}

class FileUpdateStore implements UpdateStore {
  Future<File> _file() async => File(
    '${(await getApplicationSupportDirectory()).path}/clustter-update-v1.json',
  );
  @override
  Future<Map<String, dynamic>> read() async {
    final file = await _file();
    if (!await file.exists() || await file.length() > 16384) return {};
    return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  }

  @override
  Future<void> write(Map<String, dynamic> data) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(data));
  }
}

class UpdateController extends ChangeNotifier {
  UpdateController({
    required this.appId,
    required this.platform,
    UpdateStore? store,
    Future<String> Function()? currentVersion,
    Future<String> Function()? fetch,
    DateTime Function()? clock,
  }) : store = store ?? FileUpdateStore(),
       _version =
           currentVersion ??
           (() async => (await PackageInfo.fromPlatform()).version),
       _fetch = fetch ?? UpdateClient().fetch,
       _clock = clock ?? DateTime.now;
  final String appId, platform;
  final UpdateStore store;
  final Future<String> Function() _version, _fetch;
  final DateTime Function() _clock;
  static const interval = Duration(minutes: 30);
  final Map<String, dynamic> _cache = {};
  String? currentVersion, dismissed;
  UpdateRelease? available;
  DateTime? _lastCheck;
  bool ready = false, _closed = false, _checking = false;
  Future<void> _writes = Future.value();
  bool get showBanner => available != null && dismissed != available!.version;
  void _notify() {
    if (!_closed) notifyListeners();
  }

  Future<void> initialize() async {
    if (!['windows', 'android'].contains(platform)) return;
    try {
      currentVersion = await _version();
      AppVersion.parse(currentVersion!);
      if (_closed) return;
      try {
        _cache.addAll(await store.read());
      } catch (_) {
        /* Disposable metadata cache. */
      }
      if (_closed) return;
      try {
        dismissed = _cache['dismissed'] as String?;
        _lastCheck = DateTime.tryParse(_cache['checkedAt'] as String? ?? '');
        if (_cache['release'] != null) {
          _consider(UpdateRelease.fromJson(_cache['release'], appId));
        }
      } catch (_) {
        _cache.clear();
        dismissed = null;
        _lastCheck = null;
        available = null;
      }
      ready = true;
      _notify();
      await check();
    } catch (_) {
      /* Version/plugin/network errors never block the app. */
    }
  }

  void _consider(UpdateRelease? release) {
    available =
        release != null &&
            AppVersion.parse(
                  release.version,
                ).compareTo(AppVersion.parse(currentVersion!)) >
                0
        ? release
        : null;
  }

  Future<void> check({bool force = false}) async {
    if (!ready || _closed || _checking) return;
    final now = _clock();
    if (!force &&
        _lastCheck != null &&
        now.difference(_lastCheck!).inSeconds >= 0 &&
        now.difference(_lastCheck!) < interval) {
      return;
    }
    _checking = true;
    _lastCheck = now; // Throttle offline attempts in this process as well.
    try {
      final next = readUpdate(await _fetch(), appId, platform);
      if (_closed) return;
      _consider(next);
      _cache['checkedAt'] = now.toUtc().toIso8601String();
      _cache['release'] = next?.toJson();
      _notify();
      await _persist();
    } catch (_) {
      /* Keep local work and a previously validated cached notice. */
    } finally {
      _checking = false;
    }
  }

  Future<void> dismiss() async {
    dismissed = available?.version;
    _cache['dismissed'] = dismissed;
    _notify();
    await _persist();
  }

  Future<void> _persist() async {
    final snapshot = {..._cache};
    final write = _writes.then((_) => store.write(snapshot));
    _writes = write.then<void>((_) {}, onError: (Object e, StackTrace s) {});
    try {
      await write;
    } catch (_) {
      /* Cache is optional. */
    }
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}
