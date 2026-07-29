import 'package:flutter_mcp_server/analysis/localization_scanner.dart';
import 'package:test/test.dart';

/// Treats any path starting with `lib/` as a lib file.
bool _isLib(String path) => path.startsWith('lib/');

Set<String> _names(LocalizationScanResult r) =>
    {for (final s in r.unlocalized) s.name};

void main() {
  test('screen (by name) with hardcoded text and no l10n is flagged', () {
    final result = analyzeLocalization({
      'lib/home_screen.dart': '''
import 'package:flutter/material.dart';
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: const Text('Home')));
}
''',
    }, _isLib);

    expect(result.screenCount, 1);
    expect(_names(result), {'HomeScreen'});
    expect(result.unlocalized.single.hardcodedCount, 1);
    expect(result.unlocalized.single.samples, ['Home']);
  });

  test('screen using AppLocalizations.of is not flagged', () {
    final result = analyzeLocalization({
      'lib/home_screen.dart': '''
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Text(AppLocalizations.of(context)!.title));
}
''',
    }, _isLib);

    expect(result.screenCount, 1);
    expect(result.unlocalized, isEmpty);
  });

  test('screen using easy_localization .tr() is not flagged', () {
    final result = analyzeLocalization({
      'lib/settings_page.dart': '''
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Text('settings.title'.tr()));
}
''',
    }, _isLib);

    expect(result.unlocalized, isEmpty);
  });

  test('screen using context.l10n is not flagged', () {
    final result = analyzeLocalization({
      'lib/profile_page.dart': '''
import 'package:flutter/material.dart';
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});
  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Text(context.l10n.profileTitle));
}
''',
    }, _isLib);

    expect(result.unlocalized, isEmpty);
  });

  test('screen using S.of is not flagged', () {
    final result = analyzeLocalization({
      'lib/about_view.dart': '''
import 'package:flutter/material.dart';
import 'generated/l10n.dart';
class AboutView extends StatelessWidget {
  const AboutView({super.key});
  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Text(S.of(context).about));
}
''',
    }, _isLib);

    expect(result.unlocalized, isEmpty);
  });

  test('non-screen widget with hardcoded text is ignored', () {
    final result = analyzeLocalization({
      'lib/fancy_button.dart': '''
import 'package:flutter/material.dart';
class FancyButton extends StatelessWidget {
  const FancyButton({super.key});
  @override
  Widget build(BuildContext context) => const Text('Tap me');
}
''',
    }, _isLib);

    // Not a screen (no suffix, no Scaffold), so it is not a candidate.
    expect(result.screenCount, 0);
    expect(result.unlocalized, isEmpty);
  });

  test('Scaffold-building widget without screen suffix is detected', () {
    final result = analyzeLocalization({
      'lib/dashboard.dart': '''
import 'package:flutter/material.dart';
class Dashboard extends StatelessWidget {
  const Dashboard({super.key});
  @override
  Widget build(BuildContext context) =>
      Scaffold(body: const Text('Welcome back'));
}
''',
    }, _isLib);

    expect(result.screenCount, 1);
    expect(_names(result), {'Dashboard'});
  });

  test('screen with no user-visible strings is not flagged', () {
    final result = analyzeLocalization({
      'lib/splash_screen.dart': '''
import 'package:flutter/material.dart';
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
''',
    }, _isLib);

    expect(result.screenCount, 1);
    expect(result.unlocalized, isEmpty);
  });

  test('StatefulWidget screen text lives in its State and is detected', () {
    final result = analyzeLocalization({
      'lib/counter_page.dart': '''
import 'package:flutter/material.dart';
class CounterPage extends StatefulWidget {
  const CounterPage({super.key});
  @override
  State<CounterPage> createState() => _CounterPageState();
}
class _CounterPageState extends State<CounterPage> {
  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: const Text('Counter')));
}
''',
    }, _isLib);

    expect(result.screenCount, 1);
    expect(_names(result), {'CounterPage'});
    expect(result.unlocalized.single.samples, ['Counter']);
  });

  test('non-text string literals (asset paths, keys) are not counted', () {
    final result = analyzeLocalization({
      'lib/logo_page.dart': '''
import 'package:flutter/material.dart';
class LogoPage extends StatelessWidget {
  const LogoPage({super.key});
  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Image.asset('assets/logo.png'));
}
''',
    }, _isLib);

    // The only string is an asset path; screen has no user-visible text.
    expect(result.screenCount, 1);
    expect(result.unlocalized, isEmpty);
  });
}
