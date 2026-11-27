import 'package:flutter/material.dart';
import 'app_toast.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/settings.dart';
import '../services/vpn_channel.dart';
import '../state/app_state.dart';
import 'prefs.dart';

/// Opens the dedicated page for managing the existing tor.bridges setting.
class TorCustomBridgesPref extends StatefulWidget {
  const TorCustomBridgesPref({super.key});

  @override
  State<TorCustomBridgesPref> createState() => _TorCustomBridgesPageState();
}

class _TorBridgeRow extends StatefulWidget {
  const _TorBridgeRow({super.key, required this.bridge});

  final String bridge;

  @override
  State<_TorBridgeRow> createState() => _TorBridgeRowState();
}

class _TorBridgeRowState extends State<_TorBridgeRow> {
  bool _testing = false;
  bool? _passed;

  Future<void> _test() async {
    if (_testing) return;
    setState(() {
      _testing = true;
      _passed = null;
    });
    try {
      await VpnChannel.testTorBridge(widget.bridge);
      if (mounted) setState(() => _passed = true);
    } catch (error) {
      if (mounted) {
        setState(() => _passed = false);
        AppToast.showSnackBar(context, 
          SnackBar(content: Text('Bridge test failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.bridge));
    if (!mounted) return;
    AppToast.showSnackBar(context, 
      const SnackBar(content: Text('Bridge address copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.bridge,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              if (_testing)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (_passed == true)
                const Icon(Icons.check_circle, color: Colors.green, size: 19)
              else if (_passed == false)
                Icon(Icons.cancel, color: theme.colorScheme.error, size: 19),
              const Spacer(),
              TextButton.icon(
                onPressed: _testing ? null : _test,
                icon: const Icon(Symbols.network_check_rounded),
                label: const Text('Test'),
              ),
              TextButton.icon(
                onPressed: _copy,
                icon: const Icon(Symbols.content_copy_rounded),
                label: const Text('Copy'),
              ),
              TextButton.icon(
                onPressed: () => AppScope.read(context).removeTorBridge(widget.bridge),
                icon: const Icon(Symbols.delete_outline_rounded),
                label: const Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TorCustomBridgesPageState extends State<TorCustomBridgesPref> {
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

  @override
  Widget build(BuildContext context) {
    final bridges = AppScope.of(context).profile.tor.bridges;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Custom Bridges'),
        actions: [
          IconButton(
            tooltip: 'Add bridge',
            onPressed: _add,
            icon: const Icon(Symbols.add_rounded),
          ),
        ],
      ),
      body: bridges.isEmpty
          ? const Center(child: Text('No custom bridges added'))
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: bridges.length,
              itemBuilder: (context, index) => _TorBridgeRow(
                key: ValueKey(bridges[index]),
                bridge: bridges[index],
              ),
            ),
    );
  }
}
