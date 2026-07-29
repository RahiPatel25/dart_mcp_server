import 'dart:async';
import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:path/path.dart' as p;

import 'package:flutter_mcp_server/analysis/large_widget_scanner.dart';

/// Directories (relative to the project root) scanned for widget declarations.
const _scanDirs = ['lib'];

/// Suffixes of generated files that should be ignored entirely.
const _generatedSuffixes = ['.g.dart', '.freezed.dart', '.mocks.dart', '.config.dart'];

/// Definition of the `find_large_widgets` tool.
final findLargeWidgetsTool = Tool(
  name: 'find_large_widgets',
  description:
      'Scans a Flutter project and lists widgets in lib/ whose build method is '
      'longer than a threshold (default $kDefaultBuildLineThreshold lines) — '
      'oversized build methods that are good refactor candidates. Detects '
      'StatelessWidget/ConsumerWidget/HookWidget builds and StatefulWidget '
      'builds (measured in the companion State but attributed to the widget). '
      'Results are sorted largest-first and also report the total class size. '
      'Note: syntactic parse only — a custom base class that itself extends a '
      'widget is not followed.',
  inputSchema: Schema.object(
    properties: {
      'threshold': Schema.int(
        description:
            'Minimum build-method length, in source lines, for a widget to be '
            'reported. Defaults to $kDefaultBuildLineThreshold.',
        minimum: 1,
      ),
    },
  ),
);

/// Handles calls to [findLargeWidgetsTool]. [projectPath] is the configured
/// project root injected by the server.
FutureOr<CallToolResult> handleFindLargeWidgets(
  CallToolRequest request,
  String projectPath,
) {
  final threshold =
      (request.arguments?['threshold'] as num?)?.toInt() ??
      kDefaultBuildLineThreshold;
  if (threshold < 1) {
    return _error('threshold must be a positive integer.');
  }

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

  final result = analyzeLargeWidgets(
    sources,
    libPaths.contains,
    threshold: threshold,
  );

  return CallToolResult(content: [TextContent(text: _format(result, projectPath))]);
}

bool _isGenerated(String path) => _generatedSuffixes.any((suffix) => path.endsWith(suffix));

String _format(LargeWidgetResult result, String projectPath) {
  if (result.widgets.isEmpty) {
    return '✅ No large widgets found '
        '(threshold ${result.threshold} lines; scanned ${result.fileCount} '
        'files, ${result.widgetCount} widgets).';
  }

  final buffer = StringBuffer()
    ..writeln(
      'Found ${result.widgets.length} large widget'
      '${result.widgets.length == 1 ? '' : 's'} '
      '(build > ${result.threshold} lines; scanned ${result.fileCount} files, '
      '${result.widgetCount} widgets):',
    );
  for (final w in result.widgets) {
    final rel = p.relative(w.path, from: projectPath);
    final kind = w.isStateful ? ', StatefulWidget' : '';
    buffer.writeln(
      '• ${w.name}  —  $rel:${w.line}  '
      '(build ${w.buildLines} lines, class ${w.classLines} lines$kind)',
    );
  }
  return buffer.toString().trimRight();
}

CallToolResult _error(String message) =>
    CallToolResult(isError: true, content: [TextContent(text: message)]);
