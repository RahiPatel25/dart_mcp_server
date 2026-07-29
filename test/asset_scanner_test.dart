import 'package:flutter_mcp_server/analysis/asset_scanner.dart';
import 'package:test/test.dart';

Set<String> _paths(AssetScanResult r) => {for (final a in r.unused) a.path};

void main() {
  test('asset referenced by full path is not reported', () {
    final result = analyzeAssets(
      assetPaths: {'assets/images/logo.png'},
      dartSources: {
        'lib/app.dart': '''
import 'package:flutter/material.dart';
final w = Image.asset('assets/images/logo.png');
''',
      },
    );

    expect(result.unused, isEmpty);
    expect(result.assetCount, 1);
    expect(result.fileCount, 1);
  });

  test('asset referenced nowhere is reported as unused', () {
    final result = analyzeAssets(
      assetPaths: {'assets/images/logo.png', 'assets/images/orphan.png'},
      dartSources: {
        'lib/app.dart': "const path = 'assets/images/logo.png';",
      },
    );

    expect(_paths(result), {'assets/images/orphan.png'});
  });

  test('asset referenced only by file name (interpolated dir) is kept', () {
    final result = analyzeAssets(
      assetPaths: {'assets/icons/home.png'},
      dartSources: {
        'lib/app.dart': r"final s = '$base/home.png';",
      },
    );

    expect(result.unused, isEmpty);
  });

  test('match only inside string literals, not identifiers', () {
    // A bare identifier that happens to contain the name must NOT count as use.
    final result = analyzeAssets(
      assetPaths: {'assets/logo.png'},
      dartSources: {
        'lib/app.dart': 'var logo = 1; // assets/logo.png in a comment only',
      },
    );

    // The comment text is not a string literal, so the asset is unused.
    expect(_paths(result), {'assets/logo.png'});
  });

  test('adjacent-string reference is detected', () {
    final result = analyzeAssets(
      assetPaths: {'assets/images/logo.png'},
      dartSources: {
        'lib/app.dart': "const p = 'assets/images/' 'logo.png';",
      },
    );

    // Split across adjacent strings, neither piece contains the full path but
    // the second contains the file name 'logo.png'.
    expect(result.unused, isEmpty);
  });

  test('results are sorted by path', () {
    final result = analyzeAssets(
      assetPaths: {'assets/z.png', 'assets/a.png', 'assets/m.png'},
      dartSources: {'lib/app.dart': "const x = 'nothing';"},
    );

    expect(
      result.unused.map((a) => a.path).toList(),
      ['assets/a.png', 'assets/m.png', 'assets/z.png'],
    );
  });
}
