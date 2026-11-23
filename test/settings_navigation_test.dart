import 'package:bpb/state/app_state.dart';
import 'package:bpb/ui/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _NavigationState extends AppState {
  @override
  List<String> readList(String path) => [];
}

Future<void> _tapText(WidgetTester tester, String value, {int index = 0}) async {
  final target = find.text(value).at(index);
  final inkWellFinder = find.ancestor(
    of: target,
    matching: find.byType(InkWell),
  ).first;
  final inkWell = tester.widget<InkWell>(inkWellFinder);
  expect(inkWell.onTap, isNotNull, reason: '$value is not an interactive card or tab');
  inkWell.onTap!();
  await tester.pumpAndSettle();
}

Future<void> _tapBack(WidgetTester tester) async {
  final buttonFinder = find.byWidgetPredicate(
    (widget) => widget is IconButton && widget.tooltip == 'Back',
  );
  final button = tester.widget<IconButton>(buttonFinder);
  expect(button.onPressed, isNotNull);
  button.onPressed!();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('moved settings follow the new navigation map', (tester) async {
    final state = _NavigationState();
    addTearDown(state.dispose);

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );

    // Existing Global options remain above the separate card of relocated settings.
    for (final title in [
      'Chain proxies',
      'Local DNS',
      'Anti Sanction DNS',
      'Fake DNS',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
    for (final title in [
      'IPv6 connection',
      'Prefer IPv6',
      'Share over LAN',
      'VPN MTU',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
    final existingGlobalCard = find.ancestor(
      of: find.text('Fake DNS'),
      matching: find.byType(SettingsCard),
    ).first;
    final relocatedGlobalCard = find.ancestor(
      of: find.text('VPN MTU'),
      matching: find.byType(SettingsCard),
    ).first;
    expect(
      tester.getTopLeft(existingGlobalCard).dy,
      lessThan(tester.getTopLeft(relocatedGlobalCard).dy),
      reason: 'Relocated network settings must be in a separate card below existing Global options',
    );

    // Connection is a root tab. Its landing page contains the five moved cards.
    await _tapText(tester, 'Connection');
    for (final title in ['BPB Core', 'Aether Core', 'SSH', 'Tor', 'Serverless']) {
      expect(find.text(title), findsOneWidget);
    }
    for (final title in [
      'IPv6 connection',
      'Prefer IPv6',
      'Share over LAN',
      'VPN MTU',
    ]) {
      expect(find.text(title), findsNothing);
    }

    // Direct Connection cards open their own settings page and return to home.
    for (final title in ['SSH', 'Tor', 'Serverless']) {
      await _tapText(tester, title);
      expect(find.byTooltip('Back'), findsOneWidget, reason: '$title did not open');
      await _tapBack(tester);
      expect(find.text(title), findsOneWidget, reason: '$title did not return home');
    }

    // BPB Core has its own VLESS, MASQUE and WARP cards.
    await _tapText(tester, 'BPB Core');
    for (final title in ['VLESS', 'MASQUE', 'WARP']) {
      expect(find.text(title), findsOneWidget);
    }
    await _tapText(tester, 'VLESS');
    expect(find.byTooltip('Back'), findsOneWidget);

    // Selecting the root Connection tab from a nested page resets to its home.
    await _tapText(tester, 'Connection');
    expect(find.text('BPB Core'), findsOneWidget);
    expect(find.text('Aether Core'), findsOneWidget);

    // Aether Core is a separate group with independent MASQUE and WARP cards.
    await _tapText(tester, 'Aether Core');
    for (final title in ['MASQUE', 'WARP']) {
      expect(find.text(title), findsOneWidget);
    }
    await _tapText(tester, 'MASQUE');
    expect(find.byTooltip('Back'), findsOneWidget);
    await _tapBack(tester);
    expect(find.text('Connection'), findsNWidgets(2));

    // Browser Security is a root tab, separate from Connection.
    await _tapText(tester, 'Browser Security');
    expect(find.text('WebRTC Leak Protection'), findsOneWidget);
    expect(find.text('Browser Privacy'), findsOneWidget);
    expect(find.text('BPB Core'), findsNothing);
    expect(find.text('SSH'), findsNothing);
  });
}
