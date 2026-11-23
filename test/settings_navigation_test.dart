import 'package:bpb/state/app_state.dart';
import 'package:bpb/ui/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _NavigationState extends AppState {
  @override
  List<String> readList(String path) => [];
}

void main() {
  testWidgets('Connection cards open and return to their expected level', (
    tester,
  ) async {
    final state = _NavigationState();
    addTearDown(state.dispose);

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );

    // Connection is a root tab and exposes all moved sections as cards.
    await tester.tap(find.text('Connection'));
    await tester.pumpAndSettle();

    for (final title in ['BPB Core', 'Aether Core', 'SSH', 'Tor', 'Serverless']) {
      expect(find.text(title), findsOneWidget);
    }

    // Direct sections must open a second-level page with a Back control.
    for (final title in ['SSH', 'Tor', 'Serverless']) {
      await tester.ensureVisible(find.text(title));
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Back'), findsOneWidget, reason: '$title did not open');
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget, reason: '$title did not return to Connection');
    }

    // BPB Core exposes the three existing protocol settings pages.
    await tester.tap(find.text('BPB Core'));
    await tester.pumpAndSettle();
    for (final title in ['VLESS', 'MASQUE', 'WARP']) {
      expect(find.text(title), findsOneWidget);
    }
    await tester.tap(find.text('VLESS'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back'), findsOneWidget);
    // Clicking the root Connection tab from a nested page must reset to home.
    await tester.tap(find.text('Connection').first);
    await tester.pumpAndSettle();
    expect(find.text('BPB Core'), findsOneWidget);
    expect(find.text('Aether Core'), findsOneWidget);

    // Aether Core has its own independent MASQUE and WARP settings pages.
    await tester.tap(find.text('Aether Core'));
    await tester.pumpAndSettle();
    for (final title in ['MASQUE', 'WARP']) {
      expect(find.text(title), findsOneWidget);
    }
    await tester.tap(find.text('MASQUE'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Connection'), findsOneWidget);
    await tester.tap(find.text('WARP'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back'), findsOneWidget);
  });

  testWidgets('Browser Security remains an independent root tab', (
    tester,
  ) async {
    final state = _NavigationState();
    addTearDown(state.dispose);

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );

    await tester.tap(find.text('Browser Security'));
    await tester.pumpAndSettle();

    expect(find.text('Browser Security'), findsOneWidget);
    expect(find.textContaining('WebRTC'), findsWidgets);
  });
}
