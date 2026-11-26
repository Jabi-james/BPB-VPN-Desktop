import 'dart:io';

import 'package:flutter/services.dart';

/// A font file placed by the user in the application's Fonts folder.
class UserFont {
  final String name;
  final String path;
  final String family;

  const UserFont({required this.name, required this.path, required this.family});
}

/// Discovers and loads user-provided fonts without relying on a fixed install path.
class UserFontService {
  UserFontService._();

  static final Set<String> _loadedFamilies = {};

  static Directory get directory => Directory(
    '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}Fonts',
  );

  static Future<Directory> ensureDirectory() async {
    final folder = directory;
    await folder.create(recursive: true);
    return folder;
  }

  static Future<List<UserFont>> discover() async {
    final folder = await ensureDirectory();
    final files = <File>[];
    await for (final entity in folder.list(followLinks: false)) {
      if (entity is! File) continue;
      final extension = entity.path.split('.').last.toLowerCase();
      if (extension == 'ttf' || extension == 'otf') files.add(entity);
    }
    files.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
    return [
      for (final file in files)
        UserFont(
          name: file.uri.pathSegments.last.replaceFirst(
            RegExp(r'\.(ttf|otf)$', caseSensitive: false),
            '',
          ),
          path: file.path,
          family: _familyFor(file),
        ),
    ];
  }

  static String _familyFor(File file) {
    final base = file.uri.pathSegments.last.replaceAll(RegExp(r'\.[^.]+$'), '');
    final safe = base.replaceAll(RegExp(r'[^A-Za-z0-9_]+'), '_');
    var hash = 0x811c9dc5;
    for (final unit in file.uri.pathSegments.last.toLowerCase().codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return 'BPBUser_${safe}_${hash.toRadixString(16)}';
  }

  static Future<void> load(UserFont font) async {
    if (_loadedFamilies.contains(font.family)) return;
    final bytes = await File(font.path).readAsBytes();
    final loader = FontLoader(font.family)
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
    _loadedFamilies.add(font.family);
  }

  static Future<void> openFolder() async {
    if (!Platform.isWindows) return;
    final folder = await ensureDirectory();
    await Process.start('explorer.exe', [folder.path]);
  }
}
