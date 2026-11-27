import 'package:bpb/state/app_state.dart';
import 'package:bpb/ui/status_card.dart';
import 'package:bpb/services/vpn_channel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('network recheck keeps the home status clean', (tester) async {
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
    expect(find.text('CONNECTING'), findsOneWidget);
    expect(find.text('Checking internet connection…'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('disconnecting has its own status label', (tester) async {
    final state = AppState()..status = VpnStatus.disconnecting;
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: Scaffold(body: StatusCard())),
      ),
    );

    expect(find.text('DISCONNECTING'), findsOneWidget);
    expect(find.text('CONNECTING'), findsNothing);
    expect(find.text('Stopping connection…'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('connecting remains cancellable without showing log details', (
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
    expect(find.text('Failed · Retrying…'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == 'Disconnect',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byType(InkWell).first);
    await tester.pump();
    expect(calls, ['stop']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('connect button is centered above the connection status', (tester) async {
    await tester.pumpWidget(
      AppScope(
        state: AppState(),
        child: const MaterialApp(home: Scaffold(body: StatusCard())),
      ),
    );

    final card = tester.getRect(find.byType(Card).first);
    final button = tester.getRect(find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == 'Connect',
    ));
    final status = tester.getRect(find.text('DISCONNECTED'));
    expect((button.center.dx - card.center.dx).abs(), lessThan(1));
    expect(status.top, greaterThanOrEqualTo(button.bottom));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('disconnected ping displays only a dash', (tester) async {
    final state = AppState();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: Scaffold(body: StatusCard())),
      ),
    );

    expect(find.text('Timeout'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName == 'images/icon/Warning.png',
      ),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('connected ping timeout displays a separate warning image', (tester) async {
    final state = AppState()
      ..status = VpnStatus.connected
      ..pingMs = -1;
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: Scaffold(body: StatusCard())),
      ),
    );

    expect(find.text('Timeout'), findsOneWidget);
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
