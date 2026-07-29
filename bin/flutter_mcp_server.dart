import 'dart:io' as io;

import 'package:dart_mcp/stdio.dart';
import 'package:flutter_mcp_server/server/flutter_server.dart';
import 'package:path/path.dart' as p;

/// Environment variable that pins this server to a single Flutter project.
const _projectPathEnv = 'FLUTTER_PROJECT_PATH';

void main() {
  // The server is bound to exactly one project, configured via an environment
  // variable. Tools take no project path — they always analyze this project.
  final root = _resolveProjectRoot();

  // Create the server and connect it to stdio. The channel keeps the process
  // alive by listening on stdin.
  FlutterMcpServer(
    stdioChannel(input: io.stdin, output: io.stdout),
    projectRoot: root,
  );
}

/// Reads and validates [_projectPathEnv]. On any problem, prints a clear error
/// to stderr and exits with code 64 (EX_USAGE) so a misconfigured client fails
/// loudly instead of silently serving an empty project.
String _resolveProjectRoot() {
  final raw = io.Platform.environment[_projectPathEnv]?.trim();
  if (raw == null || raw.isEmpty) {
    _fail(
      '$_projectPathEnv is not set. Configure the Flutter project this server '
      'should analyze, e.g.\n'
      '  "env": { "$_projectPathEnv": "/path/to/flutter_project" }',
    );
  }

  final root = p.normalize(p.absolute(raw));
  if (!io.Directory(root).existsSync()) {
    _fail('$_projectPathEnv points to a directory that does not exist: $root');
  }
  if (!io.File(p.join(root, 'pubspec.yaml')).existsSync()) {
    _fail('No pubspec.yaml found at $_projectPathEnv: $root');
  }
  return root;
}

Never _fail(String message) {
  io.stderr.writeln('flutter_mcp_server: $message');
  io.exit(64);
}
