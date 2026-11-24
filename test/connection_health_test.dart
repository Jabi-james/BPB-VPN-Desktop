import 'package:flutter_test/flutter_test.dart';
import 'package:bpb/state/connection_health.dart';

void main() {
  test('all connection modes probe every five seconds', () {
    expect(connectionHealthInterval(), const Duration(seconds: 5));
  });
}
