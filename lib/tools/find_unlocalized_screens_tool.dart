import 'dart:async';
import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:path/path.dart' as p;

import 'package:flutter_mcp_server/analysis/localization_scanner.dart';

/// Directories (relative to the project root) scanned for screens.
const _scanDirs = ['lib'];

/// Suffixes of generated files that should be ignored entirely.
const _generatedSuffixes = ['.g.dart', '.freezed.dart', '.mocks.dart', '.config.dart'];

/// Definition of the `find_unlocalized_screens` tool.
final findUnlocalizedScreensTool = Tool(
  name: 'find_unlocalized_screens',
  description:
      'Scans a Flutter project and lists screen widgets (classes named '
      '*Screen/*Page/*View, or that build a Scaffold) which contain hardcoded, '
      'user-visible strings but use no localization mechanism. Recognizes '
      'AppLocalizations.of(context), context.l10n, S.of(context)/S.current, '
      "easy_localization .tr(), and Intl.message. Note: only user-visible text "
      'in common Text widgets and text arguments (title, label, hintText, ...) '
      'is checked; dynamic/interpolated strings are ignored, so results are a '
      'starting point rather than an exhaustive audit.',
  inputSchema: Schema.object(properties: {}),
);

/// Handles calls to [findUnlocalizedScreensTool]. [projectPath] is the
/// configured project root injected by the server.
FutureOr<CallToolResult> handleFindUnlocalizedScreens(
  CallToolRequest request,
  String projectPath,
) {
  final projectDir = Directory(projectPath);
  if (!projectDir.existsSync()) {
    return _error('Project path does not exist: $projectPath');
  }
  final libDir = Directory(p.join(projectPath, 'lib'));
  if (!libDir.existsSync()) {
    return _error('No lib/ directory found under: $projectPath');
  }

  final sources = <String, String>{};
  final libPaths = <String>{};
  for (final dirName in _scanDirs) {
    final dir = Directory(p.join(projectPath, dirName));
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (_isGenerated(entity.path)) continue;
      final abs = entity.absolute.path;
      sources[abs] = entity.readAsStringSync();
      if (dirName == 'lib') libPaths.add(abs);
    }
  }

  final result = analyzeLocalization(sources, libPaths.contains);

  return CallToolResult(content: [TextContent(text: _format(result, projectPath))]);
}

bool _isGenerated(String path) => _generatedSuffixes.any((suffix) => path.endsWith(suffix));

String _format(LocalizationScanResult result, String projectPath) {
  if (result.unlocalized.isEmpty) {
    return '✅ No unlocalized screens found '
        '(scanned ${result.fileCount} files, ${result.screenCount} screens).';
  }

  final buffer = StringBuffer()
    ..writeln(
      'Found ${result.unlocalized.length} unlocalized screen'
      '${result.unlocalized.length == 1 ? '' : 's'} '
      '(scanned ${result.fileCount} files, ${result.screenCount} screens):',
    );
  for (final s in result.unlocalized) {
    final rel = p.relative(s.path, from: projectPath);
    final sample = s.samples.map((v) => '"$v"').join(', ');
    buffer.writeln(
      '• ${s.name}  —  $rel:${s.line}  '
      '(${s.hardcodedCount} hardcoded string'
      '${s.hardcodedCount == 1 ? '' : 's'}: $sample)',
    );
  }
  return buffer.toString().trimRight();
}

CallToolResult _error(String message) => CallToolResult(isError: true, content: [TextContent(text: message)]);
