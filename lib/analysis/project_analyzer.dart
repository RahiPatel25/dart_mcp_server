import 'package:yaml/yaml.dart';

/// State-management libraries, mapped from a friendly label to the package
/// names that indicate it. Order matters: the first label with a matching
/// dependency becomes the reported primary.
const _stateManagement = <String, List<String>>{
  'Riverpod': [
    'flutter_riverpod',
    'hooks_riverpod',
    'riverpod',
    'riverpod_annotation',
  ],
  'BLoC': ['flutter_bloc', 'bloc'],
  'GetX': ['get'],
  'Provider': ['provider'],
  'MobX': ['flutter_mobx', 'mobx'],
  'Redux': ['flutter_redux', 'redux'],
  'Stacked': ['stacked'],
  'GetIt': ['get_it'],
};

/// Routing libraries (friendly label -> package names).
const _routers = <String, List<String>>{
  'go_router': ['go_router'],
  'auto_route': ['auto_route'],
  'beamer': ['beamer'],
  'fluro': ['fluro'],
  'routemaster': ['routemaster'],
};

/// Networking libraries (friendly label -> package names).
const _networking = <String, List<String>>{
  'dio': ['dio'],
  'retrofit': ['retrofit'],
  'chopper': ['chopper'],
  'http': ['http'],
  'graphql': ['graphql_flutter', 'graphql'],
};

/// Localization libraries (friendly label -> package names).
const _localization = <String, List<String>>{
  'easy_localization': ['easy_localization'],
  'intl_utils': ['intl_utils'],
  'slang': ['slang', 'slang_flutter'],
  'flutter gen-l10n': ['flutter_localizations'],
  'intl': ['intl'],
};

/// The result of an [analyzeProject] scan — a high-level profile of a Flutter
/// project.
class ProjectAnalysis {
  ProjectAnalysis({
    required this.name,
    required this.flutter,
    required this.dart,
    required this.stateManagement,
    required this.stateManagementAll,
    required this.router,
    required this.networking,
    required this.localization,
    required this.packages,
    required this.directDependencies,
    required this.devDependencies,
    required this.usesFvm,
  });

  /// The project name from `pubspec.yaml` (`name:`), or null if unknown.
  final String? name;

  /// The Flutter SDK version (major.minor), or null if it could not be found.
  final String? flutter;

  /// The Dart SDK version (major.minor), or null if it could not be found.
  final String? dart;

  /// The primary state-management library (friendly label), or `'None'`.
  final String stateManagement;

  /// Every recognized state-management library found (may be empty).
  final List<String> stateManagementAll;

  /// The routing library, or null if none recognized.
  final String? router;

  /// The networking library, or null if none recognized.
  final String? networking;

  /// The localization library, or null if none recognized.
  final String? localization;

  /// Total number of resolved packages (from `pubspec.lock`), falling back to
  /// the count of direct dependencies when no lockfile is available.
  final int packages;

  /// Number of direct dependencies declared in `pubspec.yaml`.
  final int directDependencies;

  /// Number of dev dependencies declared in `pubspec.yaml`.
  final int devDependencies;

  /// Whether the project pins a Flutter version via FVM.
  final bool usesFvm;

  /// A JSON-serializable view of the analysis. Null-valued keys are omitted.
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      if (name != null) 'name': name,
      if (flutter != null) 'flutter': flutter,
      if (dart != null) 'dart': dart,
      'stateManagement': stateManagement,
      if (stateManagementAll.length > 1)
        'stateManagementAll': stateManagementAll,
      if (router != null) 'router': router,
      if (networking != null) 'networking': networking,
      if (localization != null) 'localization': localization,
      'packages': packages,
      'directDependencies': directDependencies,
      'devDependencies': devDependencies,
      'usesFvm': usesFvm,
    };
    return map;
  }
}

/// Builds a [ProjectAnalysis] from the raw contents of a project's config
/// files. Every argument except [pubspecContent] is optional so the function
/// stays pure and unit-testable against in-memory strings.
///
/// - [pubspecContent]: the `pubspec.yaml` contents (required).
/// - [pubspecLockContent]: the `pubspec.lock` contents, if present.
/// - [fvmrcContent]: the `.fvmrc` contents (newer FVM), if present.
/// - [fvmConfigContent]: the `.fvm/fvm_config.json` contents (older FVM).
ProjectAnalysis analyzeProject({
  required String pubspecContent,
  String? pubspecLockContent,
  String? fvmrcContent,
  String? fvmConfigContent,
}) {
  final pubspec = _tryLoadMap(pubspecContent);
  final lock = pubspecLockContent == null
      ? null
      : _tryLoadMap(pubspecLockContent);

  final deps = _stringKeys(pubspec['dependencies']);
  final devDeps = _stringKeys(pubspec['dev_dependencies']);

  // The full set of dependency names used to detect libraries. Direct deps are
  // the meaningful signal, but include dev deps too (e.g. intl_utils).
  final allDeps = {...deps, ...devDeps};

  // --- Package counts ------------------------------------------------------
  final lockPackages = lock == null ? null : lock['packages'];
  final resolvedCount = lockPackages is Map ? lockPackages.length : null;

  // --- SDK versions --------------------------------------------------------
  // pubspec.lock records the resolved SDK constraints under `sdks:`; prefer it.
  final lockSdks = lock == null ? null : lock['sdks'];
  final dartConstraint = _asString(_lookup(lockSdks, 'dart')) ??
      _asString(_lookup(pubspec['environment'], 'sdk'));
  final flutterFromLock = _asString(_lookup(lockSdks, 'flutter')) ??
      _asString(_lookup(pubspec['environment'], 'flutter'));

  // FVM pins take precedence for the Flutter version — it is the version the
  // project actually builds with.
  final fvmVersion = _fvmVersion(fvmrcContent, fvmConfigContent);

  final flutter = _majorMinor(fvmVersion ?? flutterFromLock);
  final dart = _majorMinor(dartConstraint);

  // --- Library detection ---------------------------------------------------
  final stateAll = _detectAll(_stateManagement, allDeps);

  return ProjectAnalysis(
    name: _asString(pubspec['name']),
    flutter: flutter,
    dart: dart,
    stateManagement: stateAll.isEmpty ? 'None' : stateAll.first,
    stateManagementAll: stateAll,
    router: _detectFirst(_routers, allDeps),
    networking: _detectFirst(_networking, allDeps),
    localization: _detectFirst(_localization, allDeps),
    packages: resolvedCount ?? deps.length,
    directDependencies: deps.length,
    devDependencies: devDeps.length,
    usesFvm: fvmrcContent != null || fvmConfigContent != null,
  );
}

/// Returns the first label whose package list intersects [deps].
String? _detectFirst(Map<String, List<String>> catalog, Set<String> deps) {
  for (final entry in catalog.entries) {
    if (entry.value.any(deps.contains)) return entry.key;
  }
  return null;
}

/// Returns every label whose package list intersects [deps], in catalog order.
List<String> _detectAll(Map<String, List<String>> catalog, Set<String> deps) {
  return [
    for (final entry in catalog.entries)
      if (entry.value.any(deps.contains)) entry.key,
  ];
}

/// Extracts a pinned Flutter version from FVM config, preferring `.fvmrc`.
String? _fvmVersion(String? fvmrcContent, String? fvmConfigContent) {
  if (fvmrcContent != null) {
    final rc = _tryLoadMap(fvmrcContent);
    final v = _asString(rc['flutter']) ?? _asString(rc['flutterSdkVersion']);
    if (v != null) return v;
  }
  if (fvmConfigContent != null) {
    final cfg = _tryLoadMap(fvmConfigContent);
    final v = _asString(cfg['flutterSdkVersion']) ?? _asString(cfg['flutter']);
    if (v != null) return v;
  }
  return null;
}

/// Reduces a version string or constraint to `major.minor` (e.g. `^3.9.2` and
/// `>=3.35.0 <4.0.0` and `3.35.1@beta` all become `3.9`/`3.35`). Non-numeric
/// pins (e.g. FVM channels like `stable`) are returned unchanged. Null in →
/// null out.
String? _majorMinor(String? raw) {
  if (raw == null) return null;
  final match = RegExp(r'(\d+)\.(\d+)').firstMatch(raw);
  if (match == null) {
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  return '${match.group(1)}.${match.group(2)}';
}

/// Parses [content] as YAML (JSON is valid YAML too) into a `Map`, returning an
/// empty map on any failure so callers never have to handle exceptions.
Map<dynamic, dynamic> _tryLoadMap(String content) {
  try {
    final doc = loadYaml(content);
    return doc is Map ? doc : const {};
  } catch (_) {
    return const {};
  }
}

/// The string keys of [node] if it is a map, else an empty set.
Set<String> _stringKeys(dynamic node) {
  if (node is Map) {
    return {for (final k in node.keys) k.toString()};
  }
  return {};
}

/// Reads [key] from [node] if it is a map.
dynamic _lookup(dynamic node, String key) => node is Map ? node[key] : null;

/// Returns [value] as a trimmed non-empty string, or null.
String? _asString(dynamic value) {
  if (value == null) return null;
  final s = value.toString().trim();
  return s.isEmpty ? null : s;
}
