import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const clustterSite = 'https://vacilao38.github.io/clustter-cores-downloads/';
final clustterFeed = Uri.parse('${clustterSite}updates.json');

class AppVersion implements Comparable<AppVersion> {
  AppVersion._(this.parts, this.pre);
  final List<int> parts;
  final List<String> pre;
  factory AppVersion.parse(String text) {
    if (text.length > 100) throw const FormatException('Versão inválida.');
    final match = RegExp(
      r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$',
    ).firstMatch(text);
    if (match == null) throw const FormatException('Versão inválida.');
    final pre = match[4]?.split('.') ?? <String>[];
    if (pre.any(
      (p) =>
          p.isEmpty ||
          (RegExp(r'^[0-9]+$').hasMatch(p) &&
              p.length > 1 &&
              p.startsWith('0')),
    )) {
      throw const FormatException('Versão inválida.');
    }
    return AppVersion._([
      for (var i = 1; i <= 3; i++) int.parse(match[i]!),
    ], pre);
  }
  @override
  int compareTo(AppVersion other) {
    for (var i = 0; i < 3; i++) {
      final n = parts[i].compareTo(other.parts[i]);
      if (n != 0) return n;
    }
    if (pre.isEmpty || other.pre.isEmpty) {
      return pre.isEmpty == other.pre.isEmpty
          ? 0
          : pre.isEmpty
          ? 1
          : -1;
    }
    for (var i = 0; i < pre.length && i < other.pre.length; i++) {
      final a = int.tryParse(pre[i]), b = int.tryParse(other.pre[i]);
      final n = a != null && b != null
          ? a.compareTo(b)
          : a != null
          ? -1
          : b != null
          ? 1
          : pre[i].compareTo(other.pre[i]);
      if (n != 0) return n;
    }
    return pre.length.compareTo(other.pre.length);
  }
}

class UpdateRelease {
  UpdateRelease._(this.version, this.page, this.notes);
  final String version, notes;
  final Uri page;
  factory UpdateRelease.fromJson(Object? value, String appId) {
    if (value is! Map ||
        value['version'] is! String ||
        value['page'] is! String) {
      throw const FormatException('Update inválido.');
    }
    final version = value['version'] as String;
    AppVersion.parse(version);
    final page = Uri.parse(value['page'] as String);
    final site = Uri.parse(clustterSite);
    if (page.scheme != 'https' ||
        page.host != site.host ||
        page.path != site.path ||
        page.hasPort ||
        page.userInfo.isNotEmpty ||
        page.hasQuery ||
        page.fragment != appId) {
      throw const FormatException('Destino de atualização inválido.');
    }
    final notes = value['notes'];
    if (notes != null && (notes is! String || notes.length > 1000)) {
      throw const FormatException('Nota inválida.');
    }
    return UpdateRelease._(version, page, notes as String? ?? '');
  }
  Map<String, Object> toJson() => {
    'version': version,
    'page': page.toString(),
    'notes': notes,
  };
}

UpdateRelease? readUpdate(String text, String appId, String platform) {
  if (!RegExp(r'^[a-z][a-z0-9-]{0,39}$').hasMatch(appId) ||
      !['windows', 'android'].contains(platform) ||
      utf8.encode(text).length > 262144) {
    throw const FormatException('Update inválido.');
  }
  final data = jsonDecode(text);
  if (data is! Map ||
      data['protocol'] != 'clustter.update' ||
      data['schema'] != 1 ||
      data['apps'] is! Map) {
    throw const FormatException('Protocolo Update desconhecido.');
  }
  final app = data['apps'][appId];
  if (app == null) return null;
  if (app is! Map) throw const FormatException('Aplicativo inválido.');
  final release = app[platform];
  return release == null ? null : UpdateRelease.fromJson(release, appId);
}

class UpdateClient {
  /// Only this public metadata endpoint is contacted; redirects aren't followed.
  Future<String> fetch() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..userAgent = 'Clustter-Update/1';
    try {
      return await (() async {
        final request = await client.getUrl(clustterFeed);
        request.followRedirects = false;
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        final response = await request.close();
        if (response.statusCode != 200 || response.contentLength > 262144) {
          throw const HttpException('Update indisponível.');
        }
        final bytes = BytesBuilder(copy: false);
        await for (final part in response) {
          if (bytes.length + part.length > 262144) {
            throw const FormatException('Update muito grande.');
          }
          bytes.add(part);
        }
        return utf8.decode(bytes.takeBytes());
      })().timeout(const Duration(seconds: 8));
    } finally {
      client.close(force: true);
    }
  }
}
