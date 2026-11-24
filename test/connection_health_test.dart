import 'package:flutter_test/flutter_test.dart';
import 'package:bpb/state/connection_health.dart';

void main() {
  group('connection health schedule', () {
    test('every connection mode probes every five minutes', () {
      expect(connectionHealthInterval(workerMode: true), const Duration(minutes: 5));
      expect(connectionHealthInterval(workerMode: false), const Duration(minutes: 5));
    });
  });
}
