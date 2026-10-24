import 'dart:io';
import 'package:clustter_update/src/protocol.dart';

/// Read-only end-to-end check using the same HTTPS client shipped in apps.
Future<void> main() async {
  final text = await UpdateClient().fetch();
  for (final app in ['folk', 'lake', 'chain', 'noon', 'pile']) {
    for (final platform in ['windows', 'android']) {
      final release = readUpdate(text, app, platform);
      if (release == null) throw StateError('$app/$platform ausente');
      stdout.writeln('$app/$platform ${release.version} ${release.page}');
    }
  }
}
