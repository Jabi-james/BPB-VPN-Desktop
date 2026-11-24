import 'package:flutter/foundation.dart';

/// Health probes are deliberately less frequent for Worker/VLESS deployments,
/// whose Cloudflare Worker request budget is limited.
Duration connectionHealthInterval({required bool workerMode}) =>
    workerMode ? const Duration(minutes: 1) : const Duration(seconds: 5);

/// Skip a Worker probe while any traffic has passed during the current interval.
bool shouldSkipConnectionProbe({
  required bool workerMode,
  required DateTime? lastTrafficAt,
  required DateTime now,
}) {
  if (!workerMode || lastTrafficAt == null) return false;
  return now.difference(lastTrafficAt) < const Duration(minutes: 1);
}
