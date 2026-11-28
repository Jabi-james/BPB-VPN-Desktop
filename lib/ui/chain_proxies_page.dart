// ignore_for_file: use_build_context_synchronously

import 'dart:io';

import 'package:flutter/material.dart';
import 'app_toast.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:window_manager/window_manager.dart';

import '../models/settings.dart';
import '../services/chain_proxy.dart';
import '../services/desktop_qr_scanner.dart';
import '../services/vpn_channel.dart';
import '../state/app_state.dart';
import 'chip_menu.dart';
import 'prefs.dart';
import 'flag_text.dart';

/// Settings → Chain proxies: the saved configs a connection can exit through (picked per
/// connection type on the home page). Added from the clipboard, a QR code or a WireGuard file.
class ChainProxiesPage extends StatelessWidget {
  const ChainProxiesPage({super.key});

  /// Adds the chain proxies in [text], or says why there are none.
  static void _import(BuildContext context, String? text, {String? fileName}) {
    if (text == null || text.trim().isEmpty) return;
    try {
      final chains = parseChainProxies(text, fileName: fileName);
      AppScope.read(context).addChains(chains);
      AppToast.showSnackBar(context, 
        SnackBar(content: Text(chains.length == 1 ? 'Added ${chains.single.name}' : 'Added ${chains.length} configs')),
      );
    } on FormatException catch (e) {
      AppToast.showSnackBar(context, SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _add(BuildContext context) async {
    final source = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Symbols.content_paste_rounded),
              title: const Text('Import from clipboard'),
              subtitle: const Text('v2ray links or WireGuard configs'),
              onTap: () => Navigator.of(context).pop('clipboard'),
            ),
            ListTile(
              leading: const Icon(Symbols.qr_code_rounded),
              title: const Text('Scan QR code'),
              onTap: () => Navigator.of(context).pop('qr'),
            ),
            ListTile(
              leading: const Icon(Symbols.folder_rounded),
              title: const Text('Import WireGuard config file'),
              onTap: () => Navigator.of(context).pop('file'),
            ),
          ],
        ),
      ),
    );
    if (source == null || !context.mounted) return;
    final String? text;
    String? fileName;
    try {
      switch (source) {
        case 'clipboard':
          text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
        case 'qr':
          text = await _scanDesktopQr();
        default:
          final file = await VpnChannel.pickFile();
          text = file?.content;
          fileName = file?.name;
      }
    } on PlatformException catch (e) {
      AppToast.showSnackBar(context, SnackBar(content: Text("Couldn't read the file: ${e.message}")));
      return;
    } catch (e) {
      AppToast.showSnackBar(context, SnackBar(content: Text('Desktop QR scan failed: $e')));
      return;
    }
    if (source == 'qr' && (text == null || text.trim().isEmpty)) {
      AppToast.showSnackBar(context, const SnackBar(content: Text('No QR code found on the desktop screen')));
      return;
    }
    if (source == 'clipboard' && (text == null || text.trim().isEmpty)) {
      AppToast.showSnackBar(context, const SnackBar(content: Text('The clipboard is empty')));
      return;
    }
    if (context.mounted) _import(context, text, fileName: fileName);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final chains = state.profile.chains;
    return Scaffold(
      appBar: AppBar(title: const Text('Chain proxies')),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 96),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Chain proxy',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => _add(context),
                      icon: const Icon(Symbols.add_rounded, size: 18),
                      label: const Text('Add config'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Traffic exits through the chain proxy when Chain proxy is selected as the exit node.\\n'
                  'WireGuard and Hysteria protocols work over WARP and MASQUE only.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          // A card per config.
          for (final c in chains)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SettingsCard(children: [_ChainTile(chain: c)]),
            ),
        ],
      ),
    );
  }
}

/// Hides BPB temporarily, captures the primary desktop work area, decodes a QR code and restores BPB.
Future<String?> _scanDesktopQr() async {
  var hidden = false;
  try {
    await windowManager.hide();
    hidden = true;
    // Match v2rayN's screen-scan delay before taking the desktop screenshot.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final captureDirectory = await Directory.systemTemp.createTemp('bpb-qr-scan-');
    try {
      final capturePath = '${captureDirectory.path}${Platform.pathSeparator}desktop.png';
      const script = r'''
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class BpbDpiAwareness {
  [DllImport("user32.dll", SetLastError = true)]
  public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
  [DllImport("user32.dll", SetLastError = true)]
  public static extern bool SetProcessDPIAware();
}
"@
# Use physical desktop coordinates, including high-DPI displays.
if (-not [BpbDpiAwareness]::SetProcessDpiAwarenessContext([IntPtr](-4))) {
  [void][BpbDpiAwareness]::SetProcessDPIAware()
}
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
# v2rayN captures the primary monitor's work area rather than the entire virtual desktop.
$bounds = [System.Windows.Forms.SystemInformation]::WorkingArea
if ($bounds.Width -le 0 -or $bounds.Height -le 0) { throw 'No screen work area is available for capture.' }
$bitmap = [System.Drawing.Bitmap]::new($bounds.Width, $bounds.Height)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
try {
  $graphics.CopyFromScreen($bounds.Left, $bounds.Top, 0, 0, $bitmap.Size)
  $bitmap.Save($env:BPB_QR_CAPTURE_PATH, [System.Drawing.Imaging.ImageFormat]::Png)
} finally {
  $graphics.Dispose()
  $bitmap.Dispose()
}
''';
      final result = await Process.run(
        'powershell.exe',
        ['-NoProfile', '-NonInteractive', '-STA', '-Command', script],
        environment: {'BPB_QR_CAPTURE_PATH': capturePath},
      );
      if (result.exitCode != 0) {
        throw StateError('Windows screen capture failed: ${result.stderr}');
      }
      final screenshot = File(capturePath);
      if (!await screenshot.exists()) return null;
      final bytes = await screenshot.readAsBytes();
      if (bytes.isEmpty) return null;
      return decodeDesktopQr(bytes);
    } finally {
      if (await captureDirectory.exists()) {
        await captureDirectory.delete(recursive: true);
      }
    }
  } finally {
    if (hidden) {
      await windowManager.show();
      await windowManager.focus();
    }
  }
}

/// A chain proxy: its name, address and tags, and copy / QR / delete.
class _ChainTile extends StatelessWidget {
  final ChainProxy chain;
  const _ChainTile({required this.chain});

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: chain.link));
    AppToast.showSnackBar(context, const SnackBar(content: Text('Link copied')));
  }

  void _showQr(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: FlagText(chain.name),
      content: SizedBox(
        width: 260,
        height: 260,
        // Dark modules on white whatever the theme, so every scanner reads it.
        child: QrImageView(data: chain.link, backgroundColor: Colors.white, padding: const EdgeInsets.all(12)),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
    ),
  );

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete config?'),
        content: FlagText('${chain.name} will be removed from the chain proxies.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true && context.mounted) AppScope.read(context).deleteChain(chain);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = ChainInfo.of(chain.link);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FlagText(chain.name, style: theme.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  info?.address ?? 'Invalid link',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: info == null ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (info != null) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [for (final tag in info.tags) ChipMenu.badge(context, tag)],
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy link',
            icon: const Icon(Symbols.content_copy_rounded),
            onPressed: () => _copy(context),
          ),
          IconButton(
            tooltip: 'QR code',
            icon: const Icon(Symbols.qr_code_rounded),
            onPressed: () => _showQr(context),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Symbols.delete_rounded),
            onPressed: () => _delete(context),
          ),
        ],
      ),
    );
  }
}
