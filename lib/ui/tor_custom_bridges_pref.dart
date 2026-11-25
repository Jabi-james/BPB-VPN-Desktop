import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/settings.dart';
import '../services/vpn_channel.dart';
import '../state/app_state.dart';
import 'prefs.dart';

/// Per-bridge management; the underlying tor.bridges setting remains the source of truth.
class TorCustomBridgesPref extends StatefulWidget {
  const TorCustomBridgesPref({super.key});

  @override
  State<TorCustomBridgesPref> createState() => _TorCustomBridgesPrefState();
}

class _TorCustomBridgesPrefState extends State<TorCustomBridgesPref> {
  final Set<String> _testing = {};
  final Map<String, bool> _results = {};

  Future<void> _add() async {
    final state = AppScope.read(context);
    final value = await showTextInputDialog(
      context,
      title: 'Add custom bridge',
      hint: 'webtunnel / obfs4 / snowflake bridge line',
      multiline: false,
      validator: (v) {
        final line = TorSettings.normalize(v);
        if (!TorSettings.isBridge(line)) return 'Unsupported or invalid bridge type';
        return validateBridge(line);
      },
    );
    if (value == null || !mounted) return;
    final line = TorSettings.normalize(value);
    final current = state.profile.tor.bridges;
    if (!current.contains(line)) state.write('tor.bridges', [...current, line]);
  }

  Future<void> _test(String bridge) async {
    if (_testing.contains(bridge)) return;
    setState(() { _testing.add(bridge); _results.remove(bridge); });
    try {
      await VpnChannel.testTorBridge(bridge);
      if (mounted) setState(() => _results[bridge] = true);
    } catch (e) {
      if (mounted) {
        setState(() => _results[bridge] = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bridge test failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _testing.remove(bridge));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final bridges = state.profile.tor.bridges;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: const Icon(Symbols.list_alt_rounded),
          title: const Text('Custom bridges'),
          subtitle: Text(bridges.isEmpty ? 'No bridges added' : '${bridges.length} saved bridge(s)'),
          trailing: IconButton(
            tooltip: 'Add bridge',
            onPressed: _add,
            icon: const Icon(Symbols.add_circle_outline_rounded),
          ),
        ),
        if (bridges.isNotEmpty)
          for (final bridge in bridges)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SelectableText(bridge, style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (_testing.contains(bridge))
                          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        else if (_results[bridge] == true)
                          const Icon(Icons.check_circle, color: Colors.green, size: 19)
                        else if (_results[bridge] == false)
                          Icon(Icons.cancel, color: theme.colorScheme.error, size: 19),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _testing.contains(bridge) ? null : () => _test(bridge),
                          icon: const Icon(Symbols.network_check_rounded),
                          label: const Text('Test'),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            state.removeTorBridge(bridge);
                            setState(() => _results.remove(bridge));
                          },
                          icon: const Icon(Symbols.delete_outline_rounded),
                          label: const Text('Delete'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
