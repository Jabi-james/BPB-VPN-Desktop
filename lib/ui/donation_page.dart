import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'prefs.dart';

const String _bpbBep20Address = '0xbdf15d41C56f861f25b2b11C835bd45dfD5b792F';
const String _bpbTrc20Address = 'TSEi338sydN11xh8E7ZLPUL5qc8sQtt8G4';
const String _bpbTonAddress = 'UQCHVokmmzsShpLL3FEUuLcnb9Bb6IKXWwEhJcfpr50EqMUa';

const String _notDevTrc20Address = 'TNMUWffS9VPhBsNTaTcHNHV6eErbRjVL51';
const String _notDevBep20Address = '0x1Ef196A6949A53e6Cc73e2A3c406fF3e312084A0';
const String _notDevTonAddress = 'UQAu1EXaAjVFFi60K4O8lIudr01xAruRPydqx0DsuxvXu2Oe';

class DonationPage extends StatelessWidget {
  const DonationPage({
    super.key,
    this.title = 'Donation (BPB)',
    this.bep20Address = _bpbBep20Address,
    this.trc20Address = _bpbTrc20Address,
    this.tonAddress = _bpbTonAddress,
  });

  final String title;
  final String? bep20Address;
  final String? trc20Address;
  final String? tonAddress;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        SettingsCard(
          children: [
            _DonationTile(
              network: 'TRC20',
              address: trc20Address,
              icon: Icons.account_tree_rounded,
              color: const Color(0xFFEB0029),
            ),
            _DonationTile(
              network: 'BEP20',
              address: bep20Address,
              icon: Icons.hexagon_rounded,
              color: const Color(0xFFF0B90B),
            ),
            _DonationTile(
              network: 'TON',
              address: tonAddress,
              icon: Icons.send_rounded,
              color: const Color(0xFF0098EA),
            ),
          ],
        ),
      ],
    ),
  );
}

class _DonationTile extends StatelessWidget {
  const _DonationTile({
    required this.network,
    required this.address,
    required this.icon,
    required this.color,
  });

  final String network;
  final String? address;
  final IconData icon;
  final Color color;

  Future<void> _copy(BuildContext context, String address) async {
    await Clipboard.setData(ClipboardData(text: address));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Tether - $network address copied')));
  }

  void _showQr(BuildContext context, String address) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Tether - $network'),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 20,
          children: [
            SizedBox(
              width: MediaQuery.sizeOf(context).width,
              child: AspectRatio(
                aspectRatio: 1,
                // QrImageView uses LayoutBuilder, which cannot report intrinsic sizes.
                child: SizedBox.square(
                  dimension: MediaQuery.sizeOf(context).width,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: QrImageView(
                      data: address,
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                ),
              ),
            ),
            SelectableText(address),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = address?.trim();
    final configuredAddress = value == null || value.isEmpty ? null : value;
    return ListTile(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(width: 8),
          Text('Tether - $network'),
        ],
      ),
      subtitle: Text(
        configuredAddress ?? 'Address not configured',
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Copy $network address',
            icon: const Icon(Symbols.content_copy_rounded),
            onPressed: configuredAddress == null
                ? null
                : () => _copy(context, configuredAddress),
          ),
          IconButton(
            tooltip: '$network QR code',
            icon: const Icon(Symbols.qr_code_rounded),
            onPressed: configuredAddress == null
                ? null
                : () => _showQr(context, configuredAddress),
          ),
        ],
      ),
    );
  }
}
