import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'controller.dart';

/// Place in MaterialApp.builder. Only an available update occupies UI space.
class ClustterUpdate extends StatefulWidget {
  const ClustterUpdate({
    super.key,
    required this.appId,
    required this.appName,
    required this.child,
    this.controller,
    this.openPage,
  });
  final String appId, appName;
  final Widget child;
  final UpdateController? controller;
  final Future<bool> Function(Uri)? openPage;
  @override
  State<ClustterUpdate> createState() => _ClustterUpdateState();
}

class _ClustterUpdateState extends State<ClustterUpdate>
    with WidgetsBindingObserver {
  late final controller =
      widget.controller ??
      UpdateController(
        appId: widget.appId,
        platform: kIsWeb
            ? 'unsupported'
            : Platform.isWindows
            ? 'windows'
            : Platform.isAndroid
            ? 'android'
            : 'unsupported',
      );
  Timer? timer;
  bool opening = false, openFailed = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_start());
    });
  }

  Future<void> _start() async {
    await controller.initialize();
    if (!mounted || !controller.ready) return;
    timer = Timer.periodic(UpdateController.interval, (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(controller.check());
      }
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(controller.check());
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_changed);
    if (widget.controller == null) controller.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final page = controller.available?.page;
    if (page == null) return;
    setState(() {
      opening = true;
      openFailed = false;
    });
    try {
      final result =
          await (widget.openPage?.call(page) ??
              launchUrl(page, mode: LaunchMode.externalApplication));
      if (mounted) setState(() => openFailed = !result);
    } catch (_) {
      if (mounted) setState(() => openFailed = true);
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (controller.showBanner)
        Material(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: LayoutBuilder(
                builder: (context, box) {
                  final scheme = Theme.of(context).colorScheme;
                  final message = Text(
                    '${widget.appName} ${controller.available!.version} está disponível',
                    style: TextStyle(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                  final download = TextButton.icon(
                    onPressed: opening ? null : _open,
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: Text(opening ? 'Abrindo…' : 'Baixar no site'),
                  );
                  final close = IconButton(
                    tooltip: 'Lembrar apenas na próxima versão',
                    onPressed: controller.dismiss,
                    icon: Icon(Icons.close, color: scheme.onPrimaryContainer),
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (box.maxWidth < 560) ...[
                        Row(
                          children: [
                            Expanded(child: message),
                            close,
                          ],
                        ),
                        Align(alignment: Alignment.centerLeft, child: download),
                      ] else
                        Row(
                          children: [
                            const Icon(Icons.system_update_alt),
                            const SizedBox(width: 12),
                            Expanded(child: message),
                            download,
                            close,
                          ],
                        ),
                      if (openFailed)
                        SelectableText(
                          'Abra a página no navegador: ${controller.available!.page}',
                          style: TextStyle(
                            color: scheme.onPrimaryContainer,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      Expanded(child: widget.child),
    ],
  );
}
