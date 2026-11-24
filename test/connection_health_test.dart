import 'package:flutter_test/flutter_test.dart';
import 'package:bpb/state/connection_health.dart';

void main() {
  group('connection health schedule', () {
    test('Worker/VLESS probes once per minute', () {
      expect(
        connectionHealthInterval(workerMode: true),
        const Duration(minutes: 1),
      );
    });

    test('other connection modes probe every five seconds', () {
      expect(
        connectionHealthInterval(workerMode: false),
        const Duration(seconds: 5),
      );
    });

    test('Worker probe is skipped while traffic was seen in the interval', () {
      final now = DateTime(2026, 11, 24, 10);
      expect(
        shouldSkipConnectionProbe(
          workerMode: true,
          lastTrafficAt: now.subtract(const Duration(seconds: 30)),
          now: now,
        ),
        isTrue,
      );
      expect(
        shouldSkipConnectionProbe(
          workerMode: true,
          lastTrafficAt: now.subtract(const Duration(minutes: 1, seconds: 1)),
          now: now,
        ),
        isFalse,
      );
    });

    test('other modes never skip a probe because of traffic', () {
      final now = DateTime(2026, 11, 24, 10);
      expect(
        shouldSkipConnectionProbe(
          workerMode: false,
          lastTrafficAt: now,
          now: now,
        ),
        isFalse,
      );
    });
  });
}
