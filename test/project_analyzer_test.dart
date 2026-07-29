import 'package:flutter_mcp_server/analysis/project_analyzer.dart';
import 'package:test/test.dart';

void main() {
  test('reads name, dart from pubspec and counts direct/dev deps', () {
    final r = analyzeProject(
      pubspecContent: '''
name: my_app
environment:
  sdk: ^3.9.2
dependencies:
  flutter:
    sdk: flutter
  http: ^1.2.0
dev_dependencies:
  test: ^1.25.0
  lints: ^6.0.0
''',
    );

    expect(r.name, 'my_app');
    expect(r.dart, '3.9');
    expect(r.directDependencies, 2); // flutter + http
    expect(r.devDependencies, 2);
    // No lockfile: packages falls back to direct dependency count.
    expect(r.packages, 2);
  });

  test('detects Riverpod as primary state management', () {
    final r = analyzeProject(
      pubspecContent: '''
name: app
dependencies:
  flutter_riverpod: ^2.5.0
  go_router: ^14.0.0
  dio: ^5.4.0
''',
    );

    expect(r.stateManagement, 'Riverpod');
    expect(r.router, 'go_router');
    expect(r.networking, 'dio');
  });

  test('reports None when no state management is present', () {
    final r = analyzeProject(
      pubspecContent: '''
name: app
dependencies:
  http: ^1.2.0
''',
    );

    expect(r.stateManagement, 'None');
    expect(r.stateManagementAll, isEmpty);
    expect(r.router, isNull);
  });

  test('lists all detected state-management libraries', () {
    final r = analyzeProject(
      pubspecContent: '''
name: app
dependencies:
  flutter_bloc: ^8.0.0
  provider: ^6.0.0
''',
    );

    expect(r.stateManagement, 'BLoC'); // higher priority than Provider
    expect(r.stateManagementAll, ['BLoC', 'Provider']);
  });

  test('prefers pubspec.lock sdks and resolved package count', () {
    final r = analyzeProject(
      pubspecContent: '''
name: app
environment:
  sdk: ^3.0.0
dependencies:
  http: ^1.2.0
''',
      pubspecLockContent: '''
packages:
  http:
    dependency: "direct main"
    version: "1.2.0"
  async:
    dependency: transitive
    version: "2.11.0"
  meta:
    dependency: transitive
    version: "1.15.0"
sdks:
  dart: ">=3.9.0 <4.0.0"
  flutter: ">=3.35.0"
''',
    );

    // sdks block wins over the pubspec environment constraint.
    expect(r.dart, '3.9');
    expect(r.flutter, '3.35');
    // Resolved count comes from the lock's packages map.
    expect(r.packages, 3);
    expect(r.directDependencies, 1);
  });

  test('.fvmrc pins the Flutter version over the lockfile', () {
    final r = analyzeProject(
      pubspecContent: 'name: app\ndependencies:\n  http: ^1.2.0\n',
      pubspecLockContent: 'sdks:\n  flutter: ">=3.10.0"\n',
      fvmrcContent: '{"flutter": "3.35.1"}',
    );

    expect(r.flutter, '3.35');
    expect(r.usesFvm, isTrue);
  });

  test('reads legacy .fvm/fvm_config.json', () {
    final r = analyzeProject(
      pubspecContent: 'name: app\ndependencies:\n  http: ^1.2.0\n',
      fvmConfigContent: '{"flutterSdkVersion": "3.22.3"}',
    );

    expect(r.flutter, '3.22');
    expect(r.usesFvm, isTrue);
  });

  test('toJson omits null fields and keeps required keys', () {
    final r = analyzeProject(
      pubspecContent: 'name: app\ndependencies:\n  http: ^1.2.0\n',
    );
    final json = r.toJson();

    expect(json['name'], 'app');
    expect(json['stateManagement'], 'None');
    expect(json.containsKey('flutter'), isFalse); // unknown -> omitted
    expect(json.containsKey('router'), isFalse); // none -> omitted
    expect(json['packages'], 1);
    expect(json['usesFvm'], isFalse);
  });

  test('gracefully handles malformed pubspec', () {
    final r = analyzeProject(pubspecContent: ': : not valid : yaml : [');

    expect(r.name, isNull);
    expect(r.stateManagement, 'None');
    expect(r.directDependencies, 0);
  });
}
