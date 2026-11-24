/// Worker/VLESS probes are less frequent because a probe may open a new Worker request.
Duration connectionHealthInterval({required bool workerMode}) =>
    workerMode ? const Duration(minutes: 1) : const Duration(seconds: 5);

/// Skip a Worker probe while user traffic has passed during the last minute.
bool shouldSkipConnectionProbe({
  required bool workerMode,
  required DateTime? lastTrafficAt,
  required DateTime now,
}) {
  if (!workerMode || lastTrafficAt == null) return false;
  return now.difference(lastTrafficAt) < const Duration(minutes: 1);
}
