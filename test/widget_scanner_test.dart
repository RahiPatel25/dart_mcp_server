import 'package:flutter_mcp_server/analysis/widget_scanner.dart';
import 'package:test/test.dart';

/// Treats any path starting with `lib/` as a lib file.
bool _isLib(String path) => path.startsWith('lib/');

Set<String> _unusedNames(ScanResult r) => {for (final w in r.unused) w.name};

void main() {
  test('unused StatelessWidget is flagged', () {
    final result = analyzeSources({
      'lib/orphan.dart': '''
import 'package:flutter/widgets.dart';
class Orphan extends StatelessWidget {
  const Orphan({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''',
    }, _isLib);

    expect(result.widgetCount, 1);
    expect(_unusedNames(result), {'Orphan'});
  });

  test('widget instantiated elsewhere is not flagged', () {
    final result = analyzeSources({
      'lib/child.dart': '''
import 'package:flutter/widgets.dart';
class Child extends StatelessWidget {
  const Child({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''',
      'lib/parent.dart': '''
import 'package:flutter/widgets.dart';
import 'child.dart';
class Parent extends StatelessWidget {
  const Parent({super.key});
  @override
  Widget build(BuildContext context) => const Child();
}
''',
    }, _isLib);

    // Parent is unused, Child is used by Parent.
    expect(_unusedNames(result), {'Parent'});
  });

  test('StatefulWidget referenced only by its own State<W> is flagged', () {
    final result = analyzeSources({
      'lib/counter.dart': '''
import 'package:flutter/widgets.dart';
class Counter extends StatefulWidget {
  const Counter({super.key});
  @override
  State<Counter> createState() => _CounterState();
}
class _CounterState extends State<Counter> {
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''',
    }, _isLib);

    expect(_unusedNames(result), {'Counter'});
  });

  test('StatefulWidget used elsewhere is not flagged', () {
    final result = analyzeSources({
      'lib/counter.dart': '''
import 'package:flutter/widgets.dart';
class Counter extends StatefulWidget {
  const Counter({super.key});
  @override
  State<Counter> createState() => _CounterState();
}
class _CounterState extends State<Counter> {
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''',
      'lib/home.dart': '''
import 'package:flutter/widgets.dart';
import 'counter.dart';
class Home extends StatelessWidget {
  const Home({super.key});
  @override
  Widget build(BuildContext context) => const Counter();
}
''',
    }, _isLib);

    // Only Home is unused; Counter is used by Home.
    expect(_unusedNames(result), {'Home'});
  });

  test('widget used only from a test file is not flagged', () {
    final result = analyzeSources({
      'lib/button.dart': '''
import 'package:flutter/widgets.dart';
class FancyButton extends StatelessWidget {
  const FancyButton({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''',
      'test/button_test.dart': '''
import 'package:flutter_test/flutter_test.dart';
import 'package:app/button.dart';
void main() {
  testWidgets('renders', (tester) async {
    await tester.pumpWidget(const FancyButton());
  });
}
''',
    }, _isLib);

    expect(result.unused, isEmpty);
  });

  test('ConsumerWidget (third-party base) is detected', () {
    final result = analyzeSources({
      'lib/screen.dart': '''
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
class Screen extends ConsumerWidget {
  const Screen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => const SizedBox();
}
''',
    }, _isLib);

    expect(result.widgetCount, 1);
    expect(_unusedNames(result), {'Screen'});
  });

  test('root widget passed to runApp is not flagged', () {
    final result = analyzeSources({
      'lib/app.dart': '''
import 'package:flutter/widgets.dart';
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''',
      'lib/main.dart': '''
import 'package:flutter/widgets.dart';
import 'app.dart';
void main() => runApp(const MyApp());
''',
    }, _isLib);

    expect(result.unused, isEmpty);
  });
}
