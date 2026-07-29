import 'package:flutter_mcp_server/analysis/screen_scanner.dart';
import 'package:test/test.dart';

/// Treats any path starting with `lib/` as a lib file.
bool _isLib(String path) => path.startsWith('lib/');

Set<String> _names(ScreenListResult r) => {for (final s in r.screens) s.name};

void main() {
  test('widget matched by Screen/Page/View suffix is listed', () {
    final result = analyzeScreens({
      'lib/home_screen.dart': '''
import 'package:flutter/material.dart';
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''',
    }, _isLib);

    expect(_names(result), {'HomeScreen'});
    final s = result.screens.single;
    expect(s.matchedBySuffix, isTrue);
    expect(s.buildsScaffold, isFalse);
    expect(s.line, 2);
  });

  test('Scaffold-building widget without a screen suffix is listed', () {
    final result = analyzeScreens({
      'lib/dashboard.dart': '''
import 'package:flutter/material.dart';
class Dashboard extends StatelessWidget {
  const Dashboard({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(body: const Text('hi'));
}
''',
    }, _isLib);

    expect(_names(result), {'Dashboard'});
    expect(result.screens.single.matchedBySuffix, isFalse);
    expect(result.screens.single.buildsScaffold, isTrue);
  });

  test('plain widget (no suffix, no Scaffold) is not a screen', () {
    final result = analyzeScreens({
      'lib/fancy_button.dart': '''
import 'package:flutter/material.dart';
class FancyButton extends StatelessWidget {
  const FancyButton({super.key});
  @override
  Widget build(BuildContext context) => const Text('Tap');
}
''',
    }, _isLib);

    expect(result.screens, isEmpty);
  });

  test('StatefulWidget screen whose Scaffold lives in its State is listed', () {
    final result = analyzeScreens({
      'lib/counter_page.dart': '''
import 'package:flutter/material.dart';
class CounterPage extends StatefulWidget {
  const CounterPage({super.key});
  @override
  State<CounterPage> createState() => _CounterPageState();
}
class _CounterPageState extends State<CounterPage> {
  @override
  Widget build(BuildContext context) => Scaffold(body: const Text('n'));
}
''',
    }, _isLib);

    // The State subclass itself must not be reported as a screen.
    expect(_names(result), {'CounterPage'});
    expect(result.screens.single.buildsScaffold, isTrue);
  });

  test('const Scaffold (instance creation) is detected', () {
    final result = analyzeScreens({
      'lib/splash.dart': '''
import 'package:flutter/material.dart';
class Splash extends StatelessWidget {
  const Splash({super.key});
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
''',
    }, _isLib);

    expect(_names(result), {'Splash'});
    expect(result.screens.single.buildsScaffold, isTrue);
  });

  test('results are sorted by path then line and count files', () {
    final result = analyzeScreens({
      'lib/b_page.dart': '''
import 'package:flutter/material.dart';
class BPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''',
      'lib/a_view.dart': '''
import 'package:flutter/material.dart';
class AView extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''',
    }, _isLib);

    expect(result.screens.map((s) => s.name).toList(), ['AView', 'BPage']);
    expect(result.fileCount, 2);
  });
}
