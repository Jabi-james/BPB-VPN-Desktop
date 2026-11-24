/// All connection modes use the same five-minute health-check interval.
Duration connectionHealthInterval({required bool workerMode}) =>
    const Duration(minutes: 5);
