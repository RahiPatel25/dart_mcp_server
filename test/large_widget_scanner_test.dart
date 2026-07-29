import 'package:flutter_mcp_server/analysis/large_widget_scanner.dart';
import 'package:test/test.dart';

bool _isLib(String path) => path.startsWith('lib/');

Set<String> _names(LargeWidgetResult r) => {for (final w in r.widgets) w.name};

/// Builds a StatelessWidget whose build body has [bodyLines] statement lines.
String _statelessWithBuildLines(String name, int bodyLines) {
  final body = List.filled(bodyLines, '    print("x");').join('\n');
  return '''
import 'package:flutter/material.dart';
class $name extends StatelessWidget {
  const $name({super.key});
  @override
  Widget build(BuildContext context) {
$body
    return const SizedBox();
  }
}
''';
}

void main() {
  test('widget with a build over the threshold is reported', () {
    final result = analyzeLargeWidgets(
      {'lib/big.dart': _statelessWithBuildLines('Big', 40)},
      _isLib,
      threshold: 10,
    );

    expect(_names(result), {'Big'});
    final w = result.widgets.single;
    expect(w.isStateful, isFalse);
    expect(w.buildLines, greaterThan(10));
    expect(w.classLines, greaterThanOrEqualTo(w.buildLines));
  });

  test('widget with a small build is not reported', () {
    final result = analyzeLargeWidgets(
      {'lib/small.dart': _statelessWithBuildLines('Small', 3)},
      _isLib,
      threshold: 100,
    );

    expect(result.widgets, isEmpty);
    expect(result.widgetCount, 1);
  });

  test('StatefulWidget build is measured in State but attributed to widget', () {
    final body = List.filled(30, '    print("y");').join('\n');
    final result = analyzeLargeWidgets(
      {
        'lib/counter.dart': '''
import 'package:flutter/material.dart';
class CounterPage extends StatefulWidget {
  const CounterPage({super.key});
  @override
  State<CounterPage> createState() => _CounterPageState();
}
class _CounterPageState extends State<CounterPage> {
  @override
  Widget build(BuildContext context) {
$body
    return const SizedBox();
  }
}
''',
      },
      _isLib,
      threshold: 10,
    );

    // Attributed to the widget, not the State subclass.
    expect(_names(result), {'CounterPage'});
    expect(result.widgets.single.isStateful, isTrue);
  });

  test('results are sorted largest build first', () {
    final result = analyzeLargeWidgets(
      {
        'lib/a.dart': _statelessWithBuildLines('Aaa', 20),
        'lib/b.dart': _statelessWithBuildLines('Bbb', 60),
      },
      _isLib,
      threshold: 10,
    );

    expect(result.widgets.map((w) => w.name).toList(), ['Bbb', 'Aaa']);
  });

  test('widget with no build method is not reported', () {
    final result = analyzeLargeWidgets(
      {
        'lib/nobuild.dart': '''
import 'package:flutter/material.dart';
class NoBuild extends StatelessWidget {
  const NoBuild({super.key});
}
''',
      },
      _isLib,
      threshold: 1,
    );

    expect(result.widgets, isEmpty);
    expect(result.widgetCount, 1);
  });

  test('default threshold is applied when none is given', () {
    // A ~40-line build is under the default of 100, so nothing is reported.
    final result = analyzeLargeWidgets(
      {'lib/mid.dart': _statelessWithBuildLines('Mid', 40)},
      _isLib,
    );

    expect(result.threshold, kDefaultBuildLineThreshold);
    expect(result.widgets, isEmpty);
  });
}
