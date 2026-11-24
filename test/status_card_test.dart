import 'package:bpb/state/app_state.dart';
import 'package:bpb/ui/status_card.dart';
import 'package:bpb/services/vpn_channel.dart';
import 'package:flutter/foundation.dart' show debugDefaultTargetPlatformOverride, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('network recheck displays Reconnecting', (tester) async {
    final state = AppState()
      ..status = VpnStatus.connecting
      ..connectedAt = DateTime.now()
      ..exitDetail = 'Checking internet connection…';
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: Scaffold(body: StatusCard())),
      ),
    );
    expect(find.text('RECONNECTING'), findsOneWidget);
    expect(find.text('Checking internet connection…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('connecting remains cancellable and describes retrying', (
    tester,
  ) async {
    final state = AppState()
      ..status = VpnStatus.connecting
      ..exitDetail = 'Failed · Retrying…';
    const channel = MethodChannel('bpb/core');
    final calls = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: Scaffold(body: StatusCard())),
      ),
    );

    expect(find.text('CONNECTING'), findsOneWidget);
    expect(find.text('Failed · Retrying…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == 'Disconnect',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byType(InkWell));
    await tester.pump();
    expect(calls, ['stop']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('connect button has equal top and right insets', (tester) async {
    await tester.pumpWidget(
      AppScope(
        state: AppState(),
        child: const MaterialApp(home: Scaffold(body: StatusCard())),
      ),
    );

    final card = tester.getRect(
      find
          .descendant(of: find.byType(Card), matching: find.byType(Stack))
          .first,
    );
    final ink = tester.getRect(find.byType(InkWell));
    expect(ink.top - card.top, 24);
    expect(card.right - ink.right, 24);
  });

  testWidgets('No Ping remains tappable while the tunnel is connected', (tester) async {
    // Exercise the MethodChannel path; Windows uses its native child-process bridge.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final state = AppState()
      ..status = VpnStatus.connected
      ..connectedAt = DateTime.now()
      ..pingMs = -1;
    const channel = MethodChannel('bpb/core');
    final calls = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'measureDelay') return 42;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: Scaffold(body: StatusCard())),
      ),
    );

    expect(find.text('No Ping'), findsOneWidget);
    await tester.tap(find.text('No Ping'));
    await tester.pump();
    expect(calls, contains('measureDelay'));
    expect(find.text('42 ms'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('shows image warning and red No Ping when disconnected', (tester) async {
    final state = AppState();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: Scaffold(body: StatusCard())),
      ),
    );

    expect(find.text('No Ping'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName == 'images/icon/Warning.png',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

}
