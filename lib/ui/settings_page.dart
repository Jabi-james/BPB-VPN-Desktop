import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/settings.dart';
import '../models/theme_color.dart';
import '../services/scanner_channel.dart';
import '../services/updates.dart';
import '../services/cloudflare_api.dart';
import '../services/vpn_channel.dart';
import '../services/xray_config.dart';
import '../state/app_state.dart';
import 'cf_accounts_page.dart';
import 'chain_proxies_page.dart';
import 'cloudflare_scanner_page.dart';
import 'dns_page.dart';
import 'donation_page.dart';
import 'fragments_page.dart';
import 'license_page.dart';
import 'noises_page.dart';
import 'per_app_page.dart';
import 'prefs.dart';
import 'routing_page.dart';
import 'tor_bridges_page.dart';
import 'ssh_settings_page.dart';
import 'hover_animated_icon.dart';

class _WebRtcProtectionPref extends StatelessWidget {
  const _WebRtcProtectionPref();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final enabled = state.readBool('general.webRtcLeakProtection');
    return SwitchListTile(
      secondary: const Icon(Symbols.security_rounded),
      title: const Text('WebRTC Leak Protection'),
      subtitle: const Text('Chrome and Edge · Restart the browser to apply policy changes'),
      value: enabled,
      onChanged: (value) async {
        final messenger = ScaffoldMessenger.of(context);
        final verified = await state.setWebRtcLeakProtection(value);
        if (!context.mounted) return;
        messenger.showSnackBar(SnackBar(
          content: Text(!verified
              ? 'WebRTC Leak Protection could not be verified. Check Windows browser policies.'
              : value
                  ? 'WebRTC Leak Protection Enabled. You are Secure.'
                  : 'WebRTC Leak Protection Disabled. You are not Secure.'),
          duration: const Duration(seconds: 4),
        ));
      },
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _sshDirty = false;
  bool _sshSelected = false;
  VoidCallback? _saveSsh;

  void _onSshSaveStateChanged(VoidCallback save, bool dirty) {
    if (!mounted) return;
    setState(() {
      _saveSsh = save;
      _sshDirty = dirty;
    });
  }

  static const fingerprints = {
    'chrome': 'Chrome',
    'firefox': 'Firefox',
    'safari': 'Safari',
    'ios': 'iOS',
    'android': 'Android',
    'edge': 'Edge',
    '360': '360',
    'qq': 'QQ',
    'random': 'Random',
    'randomized': 'Randomized',
    'unsafe': 'Unsafe',
  };

  static const routingStrategy = {'AsIs': 'Speed', 'IPIfNonMatch': 'Accuracy'};

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final p = state.profile;
    final d = state.device;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          if (_sshSelected)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF238636), foregroundColor: Colors.white, visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: const Size(0, 34)),
              onPressed: _sshDirty ? _saveSsh : null,
              icon: const Icon(Symbols.save_rounded, size: 17),
              label: const Text('Save'),
            ),
          IconButton(
            tooltip: 'Reset settings',
            icon: const Icon(Symbols.settings_backup_restore_rounded),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Reset settings?'),
                  content: const Text(
                    'Proxy settings return to their defaults. VLESS Clean IPs, WARP and MASQUE '
                    'endpoints and Tor custom bridges are preserved.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Reset'),
                    ),
                  ],
                ),
              );
              if (ok == true) state.resetSettings();
            },
          ),
        ],
      ),
      body: _SettingsSections(
        onSectionChanged: (isSsh) => setState(() => _sshSelected = isSsh),
        children: [
          const SectionHeader('Global'),
          SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Symbols.link_rounded),
                title: const Text('Chain proxies'),
                subtitle: Text(switch (p.chains.length) {
                  0 => 'None added',
                  1 => '1 config',
                  final n => '$n configs',
                }),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) =>_CompactSettingsTheme(child:  const ChainProxiesPage())),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsCard(
            children: [
              const TextPref(
                'general.localDns',
                'Local DNS',
                icon: Symbols.home_rounded,
                hint: 'IP, tcp://IP or localhost',
                help:
                    'Resolves outbound domains and bypass routing rules. '
                    'It can be an UDP DNS, TCP DNS or "localhost" to use system DNS.',
                validator: validateLocalDns,
              ),
              const TextPref(
                'general.antiSanctionDns',
                'Anti Sanction DNS',
                icon: Symbols.account_circle_off_rounded,
                help:
                    'Resolves the sanctioned domains so they work over a direct connection. '
                    'This only applies to Serverless, WARP and MASQUE connections when Exit node is set to Default. '
                    'It can be UDP DNS, TCP DNS, DoQ or DoH.',
                validator: validateSanctionDns,
              ),
              const SwitchPref(
                'general.enableFakeDns',
                'Fake DNS',
                icon: Symbols.dns_rounded,
                subtitle: 'Faster but may not work with some apps',
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsCard(
            children: [
              const _WebRtcProtectionPref(),
            ],
          ),
          const SizedBox(height: 16),
          SettingsCard(
            children: [
              const SwitchPref(
                'general.enableIpv6',
                'IPv6 connection',
                icon: Symbols.counter_6_rounded,
                subtitle: 'Enable it based on your ISP',
              ),
              const SwitchPref(
                'general.preferIpv6',
                'Prefer IPv6',
                icon: Symbols.counter_6_rounded,
                subtitle: 'Enable it based on your ISP',
              ),
              const SwitchPref(
                'device.lanSharing.enabled',
                'Share over LAN',
                icon: Symbols.lan_rounded,
                subtitle: 'Share a Socks, HTTP proxy on port 10880',
              ),
              if (d.lanSharing) ...[
                const TextPref(
                  'device.lanSharing.username',
                  'Proxy username',
                  icon: Symbols.account_circle_rounded,
                  hint: 'Optional',
                  help:
                      'Recommended to set a username and password to only allow trusted devices. '
                      'Leave both empty for no login.',
                  allowEmpty: true,
                  validator: validateProxyUsername,
                ),
                const TextPref(
                  'device.lanSharing.password',
                  'Proxy password',
                  icon: Symbols.password_rounded,
                  hint: 'Optional',
                  help: 'Used only together with a username.',
                  allowEmpty: true,
                  secret: true,
                  validator: validateProxyPassword,
                ),
              ],
              FutureBuilder<bool>(
                future: VpnChannel.supportsAppendHttpProxy,
                builder: (context, snapshot) => snapshot.data == true
                    ? const SwitchPref(
                        'device.appendHttpProxy',
                        'Add HTTP proxy to VPN',
                        icon: Symbols.http_rounded,
                        subtitle:
                            'Use proxy directly for supported apps, browsers',
                      )
                    : const SizedBox.shrink(),
              ),
              const IntPref(
                'device.mtu',
                'VPN MTU',
                icon: Symbols.straighten_rounded,
                min: 1280,
                max: 9000,
              ),
              if (defaultTargetPlatform != TargetPlatform.windows)
                ListTile(
                  leading: const Icon(Symbols.apps_rounded),
                  title: const Text('Per-app proxy'),
                  subtitle: Text(switch (d.perAppMode) {
                    PerAppMode.include =>
                      'Proxy selected apps (${d.perAppApps.length})',
                    PerAppMode.exclude =>
                      'Exclude selected apps (${d.perAppApps.length})',
                    PerAppMode.off => 'Proxy all apps',
                  }),
                  trailing: const Icon(Symbols.chevron_right_rounded),
                  onTap: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) =>_CompactSettingsTheme(child:  const PerAppPage()))),
                ),
            ],
          ),

          const CoreGroupHeader('BPB Core'),
          const SectionHeader('VLESS'),
          SettingsCard(
            children: [
              const _DeploymentTile(),
              const TextPref(
                'vless.remoteDns.server',
                'Remote DNS',
                icon: Symbols.outbound_rounded,
                help: 'Resolves foreign domains for routing and can be a DoH or TCP DNS.',
                validator: validateRemoteDns,
              ),
              const MultiIntPref(
                'vless.ports',
                'Ports',
                XrayConfigBuilder.httpsPorts,
                icon: Symbols.numbers_rounded,
              ),
              const ChoicePref(
                'vless.tlsFingerprint',
                'TLS Fingerprint',
                fingerprints,
                icon: Symbols.fingerprint_rounded,
              ),
              if (state.worker != null) const _CustomDomainTile(),
              const SwitchPref(
                'vless.customCdn.enabled',
                'Custom CDN',
                icon: Symbols.cloud_rounded,
                subtitle: 'Enable for domain fronting',
              ),
              if (p.vless.customCdn.enabled) ...const [
                ListPref(
                  'vless.customCdn.addresses',
                  'Custom CDN addresses',
                  icon: Symbols.list_arrow_rounded,
                  hint: 'speedtest.net\n151.101.66.219\n2a04:4e42::731',
                  help: 'Used with the custom CDN host and SNI together.',
                  itemValidator: validateHost,
                ),
                TextPref(
                  'vless.customCdn.host',
                  'Custom CDN host',
                  icon: Symbols.host_rounded,
                  allowEmpty: true,
                  validator: validateHost,
                ),
                TextPref(
                  'vless.customCdn.sni',
                  'Custom CDN SNI',
                  icon: Symbols.host_rounded,
                  allowEmpty: true,
                  validator: validateHost,
                ),
              ],
              const SwitchPref(
                'vless.ech.enabled',
                'TLS ECH',
                icon: Symbols.encrypted_rounded,
                subtitle: 'Hide the real SNI',
              ),
              if (p.vless.ech.enabled)
                const TextPref(
                  'vless.ech.dns',
                  'ECH DNS server',
                  icon: Symbols.dns_rounded,
                  hint: '8.8.8.8 or https://8.8.8.8/dns-query',
                  help:
                      'DNS server the ECH config is fetched from, an IP or a DoH with an IP host. '
                      'DNS server should be reachable from your network and not blocked by your ISP.',
                  validator: validateEchDns,
                ),
              ListTile(
                leading: const Icon(Symbols.view_week_rounded),
                title: const Text('TCP Fragments'),
                subtitle: Text(_fragmentSummary(p.fragments)),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) =>_CompactSettingsTheme(child:  const FragmentsPage())),
                ),
              ),
              TextPref(
                'vless.upstreamProxy',
                'Upstream TCP Proxy',
                icon: Symbols.swap_vert_rounded,
                hint: 'host:port',
                help: 'Setup a upstream TCP proxy like SNI spoofing.',
                allowEmpty: true,
                validator: validateEndpoint,
              ),
              const ListPref(
                'vless.proxyIps',
                'Proxy IPs or domains',
                icon: Symbols.list_arrow_rounded,
                help:
                    'Used by the worker to connect to Cloudflare-hosted sites. Leave empty for its '
                    'built-in default. It is highly recommended to leave it empty, because Proxy IPs expire frequently '
                    'while the default IPs update regularly.',
                hint: 'proxyip.example.com\n94.1.2.3\n95.4.5.6:8443\n[2001:db8::1]\n[2001:db8::2]:8443',
                allowEmpty: true,
                itemValidator: validateHostPort,
              ),
              const SwitchPref(
                'vless.enableTcpFastOpen',
                'TCP Fast Open',
                icon: Symbols.bolt_rounded,
                subtitle: 'Enable with caution',
              ),
              const TextPref(
                'vless.fallbackUrl',
                'Fallback website',
                icon: Symbols.eyeglasses_rounded,
                hint: 'https://example.com',
                help: 'Non-VPN visitors to the worker see this website instead of a 404. ',
                allowEmpty: true,
                validator: validateHttpsUrl,
              ),
              const IntPref(
                'vless.speedTestInterval',
                'Speed test interval (s)',
                icon: Symbols.timer_rounded,
                help: 'Interval between ping attempts to automatically find the fastest server.',
                min: 10,
                max: 300,
                suffix: ' s',
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsCard(
            children: [
              const ListPref(
                'vless.cleanIps',
                'Clean IPs or domains',
                icon: Symbols.list_arrow_rounded,
                hint: 'www.speedtest.net\n104.16.1.1\n2606:4700::6810:84e5',
                help:
                    'Set clean Cloudflare IPs or domains to boost connection speed. '
                    'Include at least one IPv4 address.',
                itemValidator: validateHost,
                listValidator: validateCleanIps,
              ),
              ListTile(
                leading: const Icon(Symbols.manage_search_rounded),
                title: const Text('Scan clean IPs'),
                subtitle: const Text('Find fast IPs for VLESS'),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>_CompactSettingsTheme(child:  const CloudflareScannerPage(
                      protocol: ScanProtocol.vless,
                    )),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsCard(children: [const _CloudflareAccountsTile()]),

          const SectionHeader('MASQUE'),
          SettingsCard(
            children: [
              const TextPref(
                'masque.remoteDns',
                'Remote DNS',
                icon: Symbols.outbound_rounded,
                hint: '1.1.1.1',
                help: 'It can be an UDP DNS, TCP DNS or DoH.',
                validator: validateTunnelDns,
              ),
              const TextPref(
                'masque.sni',
                'SNI',
                icon: Symbols.host_rounded,
                hint: MasqueSettings.defaultSni,
                validator: validateHost,
              ),
              const ChoicePref('masque.transport', 'Transport', {
                'h2': 'H2 · TCP',
                'h3': 'H3 · QUIC',
              }, icon: Symbols.swap_horiz_rounded),
              if (p.masque.transport == 'h2')
                const ChoicePref(
                  'masque.tlsFingerprint',
                  'H2 Fingerprint',
                  fingerprints,
                  icon: Symbols.fingerprint_rounded,
                ),
              ListTile(
                leading: const Icon(Symbols.view_week_rounded),
                title: const Text('H2 TCP Fragments'),
                subtitle: Text(_fragmentSummary(p.masque.fragments)),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>_CompactSettingsTheme(child:  const FragmentsPage(section: 'masque.')),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Symbols.graphic_eq_rounded),
                title: const Text('H3 UDP Obfuscation'),
                subtitle: Text(
                  '${p.masque.udpNoises.length} noise${p.masque.udpNoises.length == 1 ? '' : 's'}',
                ),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>_CompactSettingsTheme(child:  const NoisesPage(section: 'masque.')),
                  ),
                ),
              ),
              const IntPref(
                'masque.speedTestInterval',
                'Speed test interval (s)',
                icon: Symbols.timer_rounded,
                help: 'Interval between ping attempts to automatically find the fastest server.',
                min: 10,
                max: 300,
                suffix: ' s',
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsCard(
            children: [
              const ListPref(
                'masque.endpoints',
                'Endpoints',
                icon: Symbols.list_arrow_rounded,
                hint: '162.159.198.1:443\n[2606:4700:103::1]:443',
                help: 'Each endpoint in a new line. Include at least two IPv4 endpoints.',
                itemValidator: validateEndpoint,
                listValidator: validateIpv4Endpoints,
              ),
              ListTile(
                leading: const Icon(Symbols.manage_search_rounded),
                title: const Text('Scan endpoints'),
                subtitle: const Text('Find fast IPs for MASQUE'),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>_CompactSettingsTheme(child:  CloudflareScannerPage(
                      protocol: p.masque.transport == 'h3'
                          ? ScanProtocol.masqueH3
                          : ScanProtocol.masqueH2,
                    )),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsCard(children: [const _MasqueAccountTile()]),

          const SectionHeader('WARP'),
          SettingsCard(
            children: [
              const TextPref(
                'warp.remoteDns',
                'Remote DNS',
                icon: Symbols.outbound_rounded,
                hint: '1.1.1.1',
                help: 'It can be a UDP DNS, TCP DNS or DoH.',
                validator: validateTunnelDns,
              ),
              const SwitchPref(
                'warp.enableReservedBytes',
                'Reserved bytes',
                icon: Symbols.memory_rounded,
                subtitle: 'May help on some ISPs',
              ),
              ListTile(
                leading: const Icon(Symbols.graphic_eq_rounded),
                title: const Text('UDP Obfuscation'),
                subtitle: Text(
                  '${p.udpNoises.length} noise${p.udpNoises.length == 1 ? '' : 's'}',
                ),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) =>_CompactSettingsTheme(child:  const NoisesPage()))),
              ),
              const IntPref(
                'warp.keepAlive',
                'Keep alive interval (s)',
                icon: Symbols.timer_rounded,
                help: 'Keep WARP connection alive. Set 0 to disable.',
                min: 0,
                max: 25,
                suffix: ' s',
              ),
              const IntPref(
                'warp.speedTestInterval',
                'Speed test interval (s)',
                icon: Symbols.timer_rounded,
                help: 'Interval between ping attempts to automatically find the fastest server.',
                min: 10,
                max: 300,
                suffix: ' s',
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsCard(
            children: [
              const ListPref(
                'warp.endpoints',
                'Endpoints',
                icon: Symbols.list_arrow_rounded,
                hint: 'engage.cloudflareclient.com:2408\n162.159.192.1:2408\n[2606:4700:d0::a29f:c001]:2408',
                help: 'Cloudflare Warp endpoints. Include at least two IPv4 endpoints.',
                itemValidator: validateEndpoint,
                listValidator: validateIpv4Endpoints,
              ),
              ListTile(
                leading: const Icon(Symbols.manage_search_rounded),
                title: const Text('Scan endpoints'),
                subtitle: const Text('Find fast IPs for WARP'),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>_CompactSettingsTheme(child:  const CloudflareScannerPage(
                      protocol: ScanProtocol.warp,
                    )),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsCard(children: [const _WarpAccountTile()]),

          const CoreGroupHeader('Aether Core'),
          const SectionHeader('MASQUE'),
          SettingsCard(
            children: [
              const TextPref(
                'device.aether.masqueDns',
                'Remote DNS',
                icon: Symbols.outbound_rounded,
                hint: '1.1.1.1,1.0.0.1',
                help: 'DNS resolvers used inside the Aether MASQUE tunnel. Separate multiple resolvers with commas.',
              ),
              const TextPref(
                'device.aether.masqueSni',
                'MASQUE SNI',
                icon: Symbols.host_rounded,
                hint: 'www.cloudflare.com',
                validator: validateHost,
              ),
              const ChoicePref('device.aether.masqueTransport', 'Transport', {
                'h2': 'H2 · TCP',
                'h3': 'H3 · QUIC',
              }, icon: Symbols.swap_horiz_rounded),
              const ListTile(
                leading: Icon(Symbols.fingerprint_rounded),
                title: Text('TLS Fingerprint'),
                subtitle: Text('Chrome · Aether uses its built-in BoringSSL fingerprint'),
              ),
              if (d.aetherMasqueFragment) ...const [
                TextPref(
                  'device.aether.masqueFragmentSize',
                  'Fragment size (bytes)',
                  icon: Symbols.straighten_rounded,
                  hint: '8-16',
                ),
                TextPref(
                  'device.aether.masqueFragmentDelay',
                  'Fragment delay (ms)',
                  icon: Symbols.timer_rounded,
                  hint: '2-10',
                ),
              ],
              const ChoicePref('device.aether.masqueNoize', 'Obfuscation profile', {
                'off': 'Off',
                'firewall': 'Firewall',
                'gfw': 'GFW',
              }, icon: Symbols.shield_rounded),
              if (d.aetherMasqueTransport == 'h3')
                const SwitchPref(
                  'device.aether.quicV2',
                  'QUIC v2 opener',
                  icon: Symbols.network_check_rounded,
                  subtitle: 'Keep enabled unless the network blocks it',
                ),
            ],
          ),
          const SizedBox(height: 12),
          SettingsCard(
            children: [
              const ListPref(
                'device.aether.masqueEndpoints',
                'Endpoints',
                icon: Symbols.list_arrow_rounded,
                hint: '162.159.198.2:443\\n162.159.199.2:443',
                help: 'Up to ten MASQUE endpoints verified by Aether. The fastest is used first.',
                itemValidator: validateEndpoint,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Symbols.manage_search_rounded),
                title: const Text('Scanner settings'),
                subtitle: const Text('Choose scan mode and scan MASQUE endpoints'),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) =>_CompactSettingsTheme(child:  const AetherScannerPage(protocol: 'masque'))),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SettingsCard(children: [const _AetherMasqueAccountTile()]),

          const SectionHeader('WARP'),
          SettingsCard(
            children: [
              const TextPref(
                'device.aether.wgDns',
                'Remote DNS',
                icon: Symbols.outbound_rounded,
                hint: '1.1.1.1,1.0.0.1',
                help: 'DNS resolvers used inside the Aether WireGuard tunnel. Separate multiple resolvers with commas.',
              ),
              const ChoicePref('device.aether.wgNoize', 'Obfuscation profile', {
                'off': 'Off',
                'light': 'Light',
                'balanced': 'Balanced',
                'aggressive': 'Aggressive',
              }, icon: Symbols.shield_rounded),
              const IntPref(
                'device.aether.wgKeepalive',
                'Keep alive interval (s)',
                icon: Symbols.timer_rounded,
                min: 1,
                max: 120,
                suffix: ' s',
              ),
              const ListTile(
                leading: Icon(Symbols.numbers_rounded),
                title: Text('Reserved bytes'),
                subtitle: Text('Not exposed by Aether’s WireGuard implementation'),
              ),
              const SwitchPref(
                'device.aether.wgNoProfileRetry',
                'Disable profile retry',
                icon: Symbols.repeat_rounded,
                subtitle: 'Do not retry other obfuscation profiles during scan',
              ),
            ],
          ),
          const SizedBox(height: 12),
          SettingsCard(
            children: [
              const ListPref(
                'device.aether.wgEndpoints',
                'Endpoints',
                icon: Symbols.list_arrow_rounded,
                hint: '162.159.192.1:2408\\n162.159.193.1:2408',
                help: 'Up to ten WireGuard endpoints verified by Aether. The fastest is used first.',
                itemValidator: validateEndpoint,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Symbols.manage_search_rounded),
                title: const Text('Scanner settings'),
                subtitle: const Text('Choose scan mode and scan WireGuard endpoints'),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) =>_CompactSettingsTheme(child:  const AetherScannerPage(protocol: 'wg'))),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SettingsCard(children: [const _AetherWgAccountTile()]),
          const CoreGroupEnd(),

          const SectionHeader('SSH'),
          SshSettingsPage(embedded: true, onSaveStateChanged: _onSshSaveStateChanged),

          const SectionHeader('Tor'),
          SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Symbols.download_rounded),
                title: const Text('Get bridges'),
                subtitle: const Text('Fresh bridges from Tor'),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) =>_CompactSettingsTheme(child:  const TorBridgesPage())),
                ),
              ),
              const ListPref(
                'tor.bridges',
                'Custom bridges',
                icon: Symbols.list_arrow_rounded,
                hint: 'webtunnel [2001:db8::1]:443 FINGERPRINT url=https://example.com/path ver=0.0.1',
                help:
                    'Used by the Tor Custom bridges mode. One bridge per line, as given by '
                    'bridges.torproject.org or @GetBridgesBot (webtunnel, obfs4, snowflake).',
                itemValidator: validateBridge,
                commaSeparated: false,
              ),
            ],
          ),

          const SectionHeader('Serverless'),
          SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Symbols.dns_rounded),
                title: const Text('DNS servers'),
                subtitle: Text('DNS mode'),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) =>_CompactSettingsTheme(child:  const DnsPage()))),
              ),
              const SwitchPref(
                'serverless.dnsSettings.fakeSniServers',
                'Fake SNI servers',
                icon: Symbols.encrypted_rounded,
                subtitle: 'DNS mode',
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Symbols.view_week_rounded),
                title: const Text('TCP Fragments'),
                subtitle: Text('Packet mode'),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>_CompactSettingsTheme(child:  const FragmentsPage(section: 'serverless.')),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Symbols.graphic_eq_rounded),
                title: const Text('UDP Obfuscation'),
                subtitle: Text('Packet mode'),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>_CompactSettingsTheme(child:  const NoisesPage(section: 'serverless.')),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsCard(
            children: [
              if (defaultTargetPlatform == TargetPlatform.windows)
                const _WindowsMitmCaTile()
              else
                const _MitmCaTile(),
            ],
          ),

          const SectionHeader('Routing'),
          SettingsCard(
            children: [
              ChoicePref(
                'routing.domainStrategy',
                'Strategy',
                routingStrategy,
                icon: Symbols.discover_tune_rounded,
              ),
              _RulesTile(
                title: 'Bypass rules',
                icon: Symbols.alt_route_rounded,
                group: 'bypass',
                labels: RoutingPage.bypassLabels,
                domainHint: 'example.ir',
                ipHint:
                    '10.0.0.1/24\n192.178.24.110\n2a00:1450:400e:808::200e/128',
              ),
              _RulesTile(
                title: 'Sanction rules',
                icon: Symbols.alt_route_rounded,
                group: 'sanctionBypass',
                labels: RoutingPage.sanctionBypassLabels,
                domainHint: 'gemini.google.com',
                help: RoutingPage.sanctionHelp,
              ),
              _RulesTile(
                title: 'Block rules',
                icon: Symbols.do_not_disturb_on_rounded,
                group: 'block',
                labels: RoutingPage.blockLabels,
                domainHint: 'ads.example.com',
                ipHint: '10.10.34.34/24\n2001:4188:2:600:10:10:34:34/112',
              ),
              const _GeoAssetsTile(),
            ],
          ),

          const SectionHeader('Import / Export'),
          const SettingsCard(
            children: [
              _ExportSettingsTile(download: false),
              _ImportSettingsTile(),
              _ExportSettingsTile(download: true),
            ],
          ),

          const SectionHeader('Appearance'),
          const SettingsCard(children: [_ThemeModeTile(), _ThemeColorTile(), _FontScaleTile()]),

          const SectionHeader('About'),
          SettingsCard(
            children: [
              const _VersionTile(),
            ],
          ),
          const SizedBox(height: 12),
          SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Symbols.code_rounded),
                title: const Text('BPB Source Code'),
                subtitle: const Text('github.com/bia-pain-bache/BPB-VPN'),
                trailing: const Icon(Symbols.open_in_new_rounded, size: 20),
                onTap: () => VpnChannel.openUrl('https://github.com/bia-pain-bache/BPB-VPN'),
              ),
              ListTile(
                leading: const Icon(Icons.desktop_windows_rounded, color: Color(0xFF1685D8)),
                title: const Text('Desktop App Repo'),
                subtitle: const Text('github.com/NottDevv/BPB-VPN-Desktop'),
                trailing: const Icon(Symbols.open_in_new_rounded, size: 20),
                onTap: () => VpnChannel.openUrl('https://github.com/NottDevv/BPB-VPN-Desktop'),
              ),
              ListTile(
                leading: const Icon(Symbols.code_rounded),
                title: const Text('Desktop App Source Code'),
                subtitle: const Text('github.com/NottDevv/BPB-VPN-Desktop-Dev'),
                trailing: const Icon(Symbols.open_in_new_rounded, size: 20),
                onTap: () => VpnChannel.openUrl('https://github.com/NottDevv/BPB-VPN-Desktop-Dev'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Symbols.copyright_rounded),
                title: const Text('Open Source License'),
                subtitle: const Text('GNU GPL v3.0'),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) =>_CompactSettingsTheme(child:  const LicensePageView())),
                ),
              ),
              ListTile(
                leading: const Icon(Symbols.favorite_rounded),
                title: const Text('Donation'),
                subtitle: const Text('Keep this project alive'),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) =>_CompactSettingsTheme(child:  const DonationPage())),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AetherScannerPage extends StatefulWidget {
  final String protocol;
  const AetherScannerPage({required this.protocol, super.key});

  @override
  State<AetherScannerPage> createState() => _AetherScannerPageState();
}

class _AetherScannerPageState extends State<AetherScannerPage> {
  bool _loading = false;
  bool _stopping = false;
  bool _hasScanned = false;
  String? _error;
  List<String> _endpoints = const [];

  Future<void> _scan() async {
    if (!mounted || _loading) return;
    setState(() {
      _loading = true;
      _hasScanned = true;
      _error = null;
      _endpoints = const [];
    });
    try {
      final endpoints = await AppScope.of(context).scanAetherEndpoints(widget.protocol);
      if (!mounted) return;
      setState(() {
        _endpoints = endpoints;
        _loading = false;
        _stopping = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
        _stopping = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final protocolName = widget.protocol == 'masque' ? 'MASQUE' : 'WireGuard';
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('Aether $protocolName Scanner')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Choose how Aether scans the network. These are Aether-native options, not BPB scanner settings.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          SettingsCard(
            children: [
              const ChoicePref('device.aether.scanMode', 'Scan mode', {
                'turbo': 'Turbo',
                'balanced': 'Balanced',
                'thorough': 'Thorough',
                'stealth': 'Stealth',
                'ironclad': 'Ironclad',
              }, icon: Symbols.speed_rounded),
              const ChoicePref('device.aether.ipVersion', 'IP version', {
                'v4': 'IPv4',
                'v6': 'IPv6',
                'both': 'IPv4 + IPv6',
              }, icon: Symbols.language_rounded),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _loading ? null : _scan,
                icon: Icon(_hasScanned ? Symbols.refresh_rounded : Symbols.manage_search_rounded),
                label: Text(_hasScanned ? 'Scan again' : 'Scan'),
              ),
              if (_loading)
                OutlinedButton.icon(
                  onPressed: _stopping
                      ? null
                      : () async {
                          setState(() => _stopping = true);
                          try {
                            await AppScope.of(context).cancelAetherEndpointScan();
                          } catch (error) {
                            if (mounted) {
                              setState(() {
                                _stopping = false;
                                _error = '$error';
                              });
                            }
                          }
                        },
                  icon: const Icon(Icons.stop_rounded),
                  label: Text(_stopping ? 'Stopping…' : 'Stop'),
                ),
            ],
          ),
          if (_loading) ...[
            const SizedBox(height: 18),
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Center(child: Text(_stopping ? 'Stopping Aether scan…' : 'Aether is scanning and verifying endpoints…')),
          ] else if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ] else if (_hasScanned) ...[
            const SizedBox(height: 18),
            Text('${_endpoints.length} healthy endpoint(s) saved', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final (index, endpoint) in _endpoints.indexed)
              ListTile(
                leading: CircleAvatar(radius: 14, child: Text('${index + 1}', style: const TextStyle(fontSize: 12))),
                title: Text(endpoint),
                subtitle: Text(index == 0 ? 'Fastest · selected for connection' : 'Verified endpoint'),
                trailing: IconButton(
                  tooltip: 'Copy endpoint',
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () => Clipboard.setData(ClipboardData(text: endpoint)),
                ),
              ),
          ],
        ],
      ),
    );
  }
}


class _CompactSettingsTheme extends StatelessWidget {
  final Widget child;
  const _CompactSettingsTheme({required this.child});
  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        textTheme: base.textTheme.copyWith(
          titleLarge: base.textTheme.titleLarge?.copyWith(fontSize: 18),
          titleMedium: base.textTheme.titleMedium?.copyWith(fontSize: 14),
          titleSmall: base.textTheme.titleSmall?.copyWith(fontSize: 13),
          bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 13),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 12.5),
          bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: 11.5),
          labelLarge: base.textTheme.labelLarge?.copyWith(fontSize: 12.5),
          labelMedium: base.textTheme.labelMedium?.copyWith(fontSize: 11.5),
        ),
        iconTheme: base.iconTheme.copyWith(size: 18, color: base.colorScheme.primary),
        listTileTheme: base.listTileTheme.copyWith(
          visualDensity: VisualDensity.compact,
          minTileHeight: 44,
          minVerticalPadding: 4,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        ),
      ),
      child: child,
    );
  }
}

/// Desktop settings navigation: keep the section list fixed while the selected
/// section's settings are shown independently on the right.
class _SettingsSections extends StatefulWidget {
  final List<Widget> children;
  final ValueChanged<bool>? onSectionChanged;
  const _SettingsSections({required this.children, this.onSectionChanged});

  @override
  State<_SettingsSections> createState() => _SettingsSectionsState();
}

class CoreGroupHeader extends StatelessWidget {
  final String title;
  const CoreGroupHeader(this.title, {super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class CoreGroupEnd extends StatelessWidget {
  const CoreGroupEnd({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _SettingsSectionEntry {
  final String id;
  final String title;
  final List<Widget> children;
  const _SettingsSectionEntry(this.id, this.title, this.children);
}

class _SettingsGroupEntry {
  final String title;
  final List<_SettingsSectionEntry> sections;
  const _SettingsGroupEntry(this.title, this.sections);
}

class _SettingsSectionsState extends State<_SettingsSections> {
  String _selectedId = 'root::Global';
  final Set<String> _expandedGroups = {};

  List<Object> _navigation() {
    final result = <Object>[];
    final groupSections = <_SettingsSectionEntry>[];
    String? groupTitle;
    String? sectionTitle;
    var sectionChildren = <Widget>[];

    void finishSection() {
      if (sectionTitle == null) return;
      final id = groupTitle == null
          ? 'root::$sectionTitle'
          : '$groupTitle::$sectionTitle';
      final section = _SettingsSectionEntry(id, sectionTitle!, sectionChildren);
      if (groupTitle == null) {
        result.add(section);
      } else {
        groupSections.add(section);
      }
      sectionTitle = null;
      sectionChildren = <Widget>[];
    }

    void finishGroup() {
      if (groupTitle == null) return;
      result.add(_SettingsGroupEntry(groupTitle!, List.of(groupSections)));
      groupSections.clear();
      groupTitle = null;
    }

    for (final child in widget.children) {
      if (child is CoreGroupHeader) {
        finishSection();
        finishGroup();
        groupTitle = child.title;
      } else if (child is CoreGroupEnd) {
        finishSection();
        finishGroup();
      } else if (child is SectionHeader) {
        finishSection();
        sectionTitle = child.title;
      } else if (sectionTitle != null) {
        sectionChildren.add(child);
      }
    }
    finishSection();
    finishGroup();
    return result;
  }

  Widget _sectionTile(
    BuildContext context,
    _SettingsSectionEntry section,
    bool active,
    ThemeData theme, {
    bool nested = false,
  }) =>
      Padding(
        padding: EdgeInsets.only(left: nested ? 18 : 0, bottom: 2),
        child: Material(
          color: active ? theme.colorScheme.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: () => setState(() {
              _selectedId = section.id;
              widget.onSectionChanged?.call(section.title == 'SSH');
            }),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: nested ? 10 : 12, vertical: 10),
              child: Row(
                children: [
                  _sectionIconWidget(section.title, 17),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      section.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: active ? theme.colorScheme.onSecondaryContainer : theme.colorScheme.onSurfaceVariant,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _groupTile(BuildContext context, _SettingsGroupEntry group, ThemeData theme) {
    final expanded = _expandedGroups.contains(group.title);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: () => setState(() {
            if (expanded) {
              _expandedGroups.remove(group.title);
            } else {
              _expandedGroups.add(group.title);
            }
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                _sectionIconWidget(group.title, 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(group.title, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                ),
                Icon(expanded ? Icons.expand_less_rounded : Icons.chevron_right_rounded, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final navigation = _navigation();
    final allSections = <_SettingsSectionEntry>[
      for (final item in navigation)
        if (item is _SettingsSectionEntry) item
        else if (item is _SettingsGroupEntry) ...item.sections,
    ];
    if (allSections.isEmpty) return const SizedBox.shrink();
    final selected = allSections.where((s) => s.id == _selectedId).firstOrNull ?? allSections.first;
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 176,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              border: Border(right: BorderSide(color: theme.colorScheme.outlineVariant)),
            ),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 12),
              children: [
                for (final item in navigation)
                  if (item is _SettingsSectionEntry)
                    _sectionTile(context, item, item.id == selected.id, theme)
                  else if (item is _SettingsGroupEntry) ...[
                    _groupTile(context, item, theme),
                    if (_expandedGroups.contains(item.title))
                      for (final section in item.sections)
                        _sectionTile(context, section, section.id == selected.id, theme, nested: true),
                  ],
              ],
            ),
          ),
        ),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: const AssetImage('images/icon/bgs.jpg'),
                fit: BoxFit.cover,
                opacity: 0.24,
              ),
            ),
            child: Theme(
            data: theme.copyWith(
              textTheme: theme.textTheme.copyWith(
                titleMedium: theme.textTheme.titleMedium?.copyWith(fontSize: 14),
                bodyMedium: theme.textTheme.bodyMedium?.copyWith(fontSize: 12.5),
                bodySmall: theme.textTheme.bodySmall?.copyWith(fontSize: 11.5),
              ),
              iconTheme: theme.iconTheme.copyWith(size: 18, color: theme.colorScheme.primary),
              listTileTheme: theme.listTileTheme.copyWith(
                visualDensity: VisualDensity.compact,
                minTileHeight: 44,
                minVerticalPadding: 4,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32, top: 4),
              children: selected.children,
            ),
            ),
          ),
        ),
      ],
    );
  }
}



Color _sectionColor(String title) => switch (title) {
  'Global' => const Color(0xFF3B82F6),
  'VLESS' => const Color(0xFF22A6B3),
  'BPB Core' => const Color(0xFF64748B),
  'Aether Core' => const Color(0xFF8B5CF6),
  'MASQUE' => const Color(0xFFF28C28),
  'WARP' => const Color(0xFFF48120),
  'SSH' => const Color(0xFF18A999),
  'Tor' => const Color(0xFF7D4698),
  'Serverless' => const Color(0xFF568BFF),
  'Routing' => const Color(0xFF0D9488),
  'Import / Export' => const Color(0xFF3B82F6),
  'Appearance' => const Color(0xFF78B7FF),
  'About' => const Color(0xFF64748B),
  _ => const Color(0xFF64748B),
};

Widget _sectionIconWidget(String title, double size) {
  final color = _sectionColor(title);
  final fallback = Icon(_sectionIcon(title), size: size, color: color);
  final asset = switch (title) {
    'Serverless' => 'images/icon/Serverless.png',
    _ => null,
  };
  final Widget icon = asset == null
      ? fallback
      : Image.asset(asset, width: size, height: size, fit: BoxFit.contain,
          filterQuality: FilterQuality.high, errorBuilder: (_, _, _) => fallback);
  return HoverAnimatedIcon(child: SizedBox(width: size, height: size, child: Center(child: icon)));
}

/// Consistent rounded icons for the Settings navigation.
IconData _sectionIcon(String title) => switch (title) {
  'Global' => Icons.tune_rounded,
  'VLESS' => Icons.route_rounded,
  'BPB Core' => Icons.memory_rounded,
  'Aether Core' => Icons.bubble_chart_rounded,
  'MASQUE' => Icons.shield_rounded,
  'WARP' => Icons.cloud_rounded,
  'SSH' => Icons.key_rounded,
  'Tor' => Icons.visibility_off_rounded,
  'Serverless' => Icons.cloud_queue_rounded,
  'Routing' => Icons.alt_route_rounded,
  'Import / Export' => Icons.import_export_rounded,
  'Appearance' => Icons.palette_rounded,
  'About' => Icons.info_outline_rounded,
  _ => Icons.settings_rounded,
};

/// App-wide text size, independent of the Windows display scaling.
class _FontScaleTile extends StatelessWidget {
  const _FontScaleTile();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return ValueListenableBuilder<double>(
      valueListenable: state.fontScale,
      builder: (context, scale, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: const Icon(Symbols.text_fields_rounded),
            title: const Text('Font size'),
            subtitle: Text('${(scale * 100).round()}%'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Slider(
              value: scale,
              min: 0.8,
              max: 1.3,
              divisions: 10,
              label: '${(scale * 100).round()}%',
              onChanged: state.setFontScale,
            ),
          ),
        ],
      ),
    );
  }
}

/// Light / dark / follow the OS.
class _ThemeModeTile extends StatelessWidget {
  const _ThemeModeTile();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return ValueListenableBuilder(
      valueListenable: state.themeMode,
      builder: (context, mode, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ListTile(
            leading: Icon(Symbols.contrast_rounded),
            title: Text('Theme mode'),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Center(
              child: SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('System')),
                  ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                ],
                selected: {mode},
                onSelectionChanged: (v) => state.setThemeMode(v.first),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Theme colour picker: a row of colour circles, the selected one checked.
class _ThemeColorTile extends StatelessWidget {
  const _ThemeColorTile();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder(
      valueListenable: state.themeColor,
      builder: (context, selected, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ListTile(
            leading: Icon(Symbols.palette_rounded),
            title: Text('Theme color'),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Center(
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in ThemeColor.values)
                    Tooltip(
                      message: c.label,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => state.setThemeColor(c),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: c.seed,
                            // Ring around the selected colour.
                            border: Border.all(
                              color: c == selected
                                  ? scheme.onSurface
                                  : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                          child: c == selected
                              ? const Icon(
                                  Symbols.check_rounded,
                                  color: Colors.white,
                                  size: 20,
                                )
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A routing group: the presets on and how many custom entries; opens its page.
class _RulesTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final String group;
  final Map<String, String> labels;
  final String domainHint;

  /// Null for a group without custom IPs.
  final String? ipHint;
  final String? help;
  const _RulesTile({
    required this.title,
    required this.icon,
    required this.group,
    required this.labels,
    required this.domainHint,
    this.ipHint,
    this.help,
  });

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final enabled = [
      for (final e in labels.entries)
        if (state.readBool('routing.$group.presets.${e.key}')) e.value,
    ];
    final custom =
        state.readList('routing.$group.domains').length +
        (ipHint == null ? 0 : state.readList('routing.$group.ips').length);
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(
        [
          enabled.isEmpty ? 'No presets' : enabled.join(', '),
          if (custom > 0) '$custom custom',
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Symbols.chevron_right_rounded),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>_CompactSettingsTheme(child:  RoutingPage(
            title: title,
            group: group,
            labels: labels,
            domainHint: domainHint,
            ipHint: ipHint,
            help: help,
          )),
        ),
      ),
    );
  }
}

/// Custom domain row: tap to attach a domain while none is set; the trash icon detaches it.
class _CustomDomainTile extends StatefulWidget {
  const _CustomDomainTile();

  @override
  State<_CustomDomainTile> createState() => _CustomDomainTileState();
}

class _CustomDomainTileState extends State<_CustomDomainTile> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String success) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(success)));
    } on StateError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final state = AppScope.read(context);
    final domain = await showTextInputDialog(
      context,
      title: 'Add custom domain',
      hint: 'vpn.example.com',
      help:
          'The domain must be registered on the same Cloudflare account. '
          'Just add a desired subdomain which is not available on Cloudflare yet. '
          'BPB creates the DNS record and adds it to the worker.',
      validator: (v) => isDomain(v) ? null : 'Invalid domain',
    );
    if (domain == null || !mounted) return;
    await _run(
      () => state.setCustomDomain(domain.toLowerCase()),
      'Custom domain added',
    );
  }

  Future<void> _delete() async {
    final state = AppScope.read(context);
    final domain = state.worker!.customDomain ?? '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete custom domain?'),
        content: Text(
          '$domain will be detached from the worker in Cloudflare. '
          'Configs fall back to the workers.dev address.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(state.removeCustomDomain, 'Custom domain deleted');
  }

  @override
  Widget build(BuildContext context) {
    final domain = AppScope.of(context).worker?.customDomain ?? '';
    return ListTile(
      leading: const Icon(Symbols.host_rounded),
      title: const Text('Custom domain'),
      subtitle: Text(domain.isEmpty ? 'Not set' : domain),
      onTap: _busy || domain.isNotEmpty ? null : _add,
      trailing: _busy
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : domain.isEmpty
          ? null
          : IconButton(
              tooltip: 'Delete custom domain',
              icon: const Icon(Symbols.delete_outline_rounded),
              onPressed: _delete,
            ),
    );
  }
}

/// Windows CA creation and installation guide for Serverless Domain Fronting.
class _CertificateStep extends StatelessWidget {
  final String number;
  final String text;

  const _CertificateStep(this.number, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 26,
            child: Text(number, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _WindowsMitmCaTile extends StatefulWidget {
  const _WindowsMitmCaTile();

  @override
  State<_WindowsMitmCaTile> createState() => _WindowsMitmCaTileState();
}

class _WindowsMitmCaTileState extends State<_WindowsMitmCaTile> {
  late Future<({bool created, bool installed})> _status = _loadStatus();
  bool _busy = false;

  Future<({bool created, bool installed})> _loadStatus() async {
    final state = AppScope.read(context);
    final created = await state.hasMitmCa();
    final installed = created && await state.isMitmCaInstalled();
    return (created: created, installed: installed);
  }

  void _refresh() {
    if (mounted) setState(() => _status = _loadStatus());
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      await AppScope.read(context).createMitmCa();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Certificate created successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create the certificate: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _refresh();
      }
    }
  }

  Future<void> _install() async {
    final state = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    var installStarted = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          icon: const Icon(Symbols.verified_user_rounded, size: 36, weight: 600),
          title: const Text('Install BPB MITM certificate'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const _CertificateStep('1.', 'Press “Install” below to open the certificate.'),
                const _CertificateStep('2.', 'In the certificate window, click “Install Certificate...”.'),
                const _CertificateStep('3.', 'Choose “Current User” and click Next.'),
                const _CertificateStep('4.', 'Select “Place all certificates in the following store”.'),
                const _CertificateStep('5.', 'Click Browse, then choose “Trusted Root Certification Authorities”.'),
                const _CertificateStep('6.', 'Click Next → Finish and confirm the Windows security prompt.'),
                const SizedBox(height: 16),
                const Text('Edge and Chrome use the Windows certificate store.'),
                const SizedBox(height: 8),
                const Text('For Firefox:'),
                const Padding(
                  padding: EdgeInsets.only(left: 12, top: 4),
                  child: Text('Import the certificate under Settings → Privacy & Security → Certificates.'),
                ),
                const SizedBox(height: 16),
                const Text('⚠️ Only trust the certificate generated by this BPB installation.'),
                const SizedBox(height: 6),
                const Text('⚠️ Never share bpb-cert.key.'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(installStarted ? 'Close' : 'Cancel'),
            ),
            FilledButton(
              onPressed: installStarted
                  ? null
                  : () async {
                      setDialogState(() => installStarted = true);
                      try {
                        await state.openMitmCaCertificate();
                      } catch (e) {
                        if (dialogContext.mounted) {
                          setDialogState(() => installStarted = false);
                          messenger.showSnackBar(
                            SnackBar(content: Text('Could not open the certificate: $e')),
                          );
                        }
                      }
                    },
              child: const Text('Install'),
            ),
          ],
        ),
      ),
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({bool created, bool installed})>(
      future: _status,
      builder: (context, snapshot) {
        final status = snapshot.data;
        final created = status?.created ?? false;
        final installed = status?.installed ?? false;
        final subtitle = snapshot.connectionState == ConnectionState.waiting
            ? 'Checking certificate…'
            : !created
                ? 'Not installed'
                : installed
                    ? 'Installed'
                    : 'Created · Not installed';
        return ListTile(
          leading: const Icon(Symbols.vpn_key_rounded),
          title: const Text('MITM certificate'),
          subtitle: Text(subtitle),
          trailing: _busy
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : FilledButton.tonalIcon(
                  icon: Icon(
                    created ? Symbols.security_rounded : Symbols.add_rounded,
                    size: 18,
                  ),
                  label: Text(created ? 'Install' : 'Create'),
                  onPressed: snapshot.connectionState == ConnectionState.waiting
                      ? null
                      : created
                          ? _install
                          : _create,
                ),
        );
      },
    );
  }
}

/// Domain Fronting's CA (bpb-cert.crt / .key): created on this device on first install, then
/// handed to Android's certificate install (like [_WarpAccountTile]).
class _MitmCaTile extends StatefulWidget {
  const _MitmCaTile();

  @override
  State<_MitmCaTile> createState() => _MitmCaTileState();
}

class _MitmCaTileState extends State<_MitmCaTile> {
  late Future<bool> _created = AppScope.read(context).hasMitmCa();
  bool _busy = false;

  Future<void> _install() async {
    final state = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Symbols.verified_user_rounded, size: 36, weight: 600),
        title: const Text('Install certificate'),
        content: const Text(
          'Certificate will be saved to Downloads folder. Install it in Settings → '
          'Security → Encryption & credentials → Install a certificate → CA certificate.\n\n'
          'Never share BPB certificate files with anyone. Whoever has them can sniff your '
          'browser traffic.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Install'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final saved = await state.installMitmCa();
      if (saved != null) {
        messenger.showSnackBar(SnackBar(content: Text('Saved to $saved')));
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not install the certificate: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _created = state.hasMitmCa();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _created,
      builder: (context, snapshot) {
        final created = snapshot.data ?? false;
        return ListTile(
          leading: const Icon(Symbols.vpn_key_rounded),
          title: const Text('MITM certificate'),
          subtitle: Text(created ? 'Created' : 'Not created'),
          trailing: _busy
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : FilledButton.tonalIcon(
                  icon: const Icon(Symbols.security_rounded, size: 18),
                  label: const Text('Install'),
                  onPressed: _install,
                ),
        );
      },
    );
  }
}

/// Shows the registered WARP account and renews it (panel: "Renew Warp Accounts").
class _WarpAccountTile extends StatelessWidget {
  const _WarpAccountTile();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final registered = state.profile.warp.account != null;
    return ListTile(
      leading: const Icon(Symbols.vpn_key_rounded),
      title: const Text('WARP account'),
      subtitle: Text(registered ? 'Registered' : 'Not registered'),
      trailing: state.renewingWarp
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : FilledButton.tonalIcon(
              icon: const Icon(Symbols.autorenew_rounded, size: 18),
              label: Text(registered ? 'Renew' : 'Register'),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                if (registered) {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Renew WARP account'),
                      content: const Text(
                        'Are you sure? A new account replaces the current one.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Renew'),
                        ),
                      ],
                    ),
                  );
                  if (ok != true) return;
                }
                try {
                  await state.renewWarpAccount();
                  messenger.showSnackBar(
                    const SnackBar(content: Text('WARP account updated')),
                  );
                } on StateError catch (e) {
                  messenger.showSnackBar(SnackBar(content: Text(e.message)));
                }
              },
            ),
    );
  }
}

/// Shows Aether's local MASQUE identity and can replace it with a newly registered identity.
class _AetherMasqueAccountTile extends StatelessWidget {
  const _AetherMasqueAccountTile();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return FutureBuilder<bool>(
      future: state.hasAetherMasqueIdentity,
      builder: (context, snapshot) {
        final registered = snapshot.data == true;
        return ListTile(
          leading: const Icon(Symbols.vpn_key_rounded),
          title: const Text('MASQUE account'),
          subtitle: Text(snapshot.connectionState == ConnectionState.waiting
              ? 'Checking…'
              : registered ? 'Registered' : 'Not registered'),
          trailing: state.renewingAetherMasque
              ? const SizedBox(width: 24, height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : FilledButton.tonalIcon(
                  icon: const Icon(Symbols.autorenew_rounded, size: 18),
                  label: Text(registered ? 'Renew' : 'Register'),
                  onPressed: snapshot.connectionState == ConnectionState.waiting ||
                          state.isConnected || state.isBusy
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          if (registered) {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Renew Aether MASQUE identity'),
                                content: const Text(
                                  'A new MASQUE identity will replace the current one. Continue?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.of(context).pop(true),
                                    child: const Text('Renew'),
                                  ),
                                ],
                              ),
                            );
                            if (ok != true) return;
                          }
                          try {
                            await state.renewAetherMasqueIdentity();
                            messenger.showSnackBar(
                              const SnackBar(content: Text('Aether MASQUE identity updated')),
                            );
                          } catch (e) {
                            messenger.showSnackBar(SnackBar(content: Text('$e')));
                          }
                        },
                ),
        );
      },
    );
  }
}

/// Shows Aether's independent WireGuard/WARP identity and can register or renew it.
class _AetherWgAccountTile extends StatelessWidget {
  const _AetherWgAccountTile();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return FutureBuilder<bool>(
      future: state.hasAetherWgIdentity,
      builder: (context, snapshot) {
        final registered = snapshot.data == true;
        return ListTile(
          leading: const Icon(Symbols.vpn_key_rounded),
          title: const Text('WARP account'),
          subtitle: Text(snapshot.connectionState == ConnectionState.waiting
              ? 'Checking…'
              : registered ? 'Registered' : 'Not registered'),
          trailing: state.renewingAetherWg
              ? const SizedBox(width: 24, height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : FilledButton.tonalIcon(
                  icon: const Icon(Symbols.autorenew_rounded, size: 18),
                  label: Text(registered ? 'Renew' : 'Register'),
                  onPressed: snapshot.connectionState == ConnectionState.waiting ||
                          state.isConnected || state.isBusy
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          if (registered) {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Renew Aether WARP identity'),
                                content: const Text(
                                  'A new WireGuard/WARP identity will replace the current one without changing the MASQUE identity. Continue?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.of(context).pop(true),
                                    child: const Text('Renew'),
                                  ),
                                ],
                              ),
                            );
                            if (ok != true) return;
                          }
                          try {
                            await state.renewAetherWgIdentity();
                            messenger.showSnackBar(
                              const SnackBar(content: Text('Aether WARP identity updated')),
                            );
                          } catch (e) {
                            messenger.showSnackBar(SnackBar(content: Text('$e')));
                          }
                        },
                ),
        );
      },
    );
  }
}

/// Shows the registered MASQUE account and renews it, like [_WarpAccountTile].
class _MasqueAccountTile extends StatelessWidget {
  const _MasqueAccountTile();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final registered = state.profile.masque.account != null;
    return ListTile(
      leading: const Icon(Symbols.vpn_key_rounded),
      title: const Text('MASQUE account'),
      subtitle: Text(registered ? 'Registered' : 'Not registered'),
      trailing: state.renewingMasque
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : FilledButton.tonalIcon(
              icon: const Icon(Symbols.autorenew_rounded, size: 18),
              label: Text(registered ? 'Renew' : 'Register'),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                if (registered) {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Renew MASQUE account'),
                      content: const Text(
                        'Are you sure? A new account replaces the current one.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Renew'),
                        ),
                      ],
                    ),
                  );
                  if (ok != true) return;
                }
                try {
                  await state.renewMasqueAccount();
                  messenger.showSnackBar(
                    const SnackBar(content: Text('MASQUE account updated')),
                  );
                } on StateError catch (e) {
                  messenger.showSnackBar(SnackBar(content: Text(e.message)));
                }
              },
            ),
    );
  }
}

/// "1 fragment", "3 fragments", like the noises' subtitles.
String _fragmentSummary(List<Fragment> fragments) =>
    '${fragments.length} fragment${fragments.length == 1 ? '' : 's'}';

/// Which of the selected account's deployments (Workers or Pages) Worker mode connects to; the
/// VLESS settings below are its own. The account is picked in Cloudflare accounts.
class _DeploymentTile extends StatelessWidget {
  const _DeploymentTile();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final s = state.selected;
    if (s == null) {
      return const ListTile(
        leading: Icon(Symbols.deployed_code_rounded),
        title: Text('Type'),
        subtitle: Text('None. Add a Cloudflare account below.'),
      );
    }
    final key = AppState.deploymentKey(s.account, s.deployment);
    final deploying = state.isDeploying(s.account, s.deployment);
    final error = state.deployErrors[key];
    // Proxy IPs and the fallback website deploy right away; only a failure stays on screen.
    final status = deploying
        ? 'Deploying…'
        : s.deployment.pending
        ? 'Not deployed${error != null ? ': $error' : ' yet'}'
        : null;
    final all = s.account.deployments;
    return ListTile(
      leading: const Icon(Symbols.deployed_code_rounded),
      title: const Text('Type'),
      subtitle: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: s.deployment.type.label),
            if (status != null)
              TextSpan(
                text: '\n$status',
                style: TextStyle(
                  color: deploying ? null : theme.colorScheme.error,
                ),
              ),
          ],
        ),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: deploying
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : s.deployment.pending
          ? IconButton(
              tooltip: 'Deploy again',
              icon: const Icon(Symbols.refresh_rounded),
              onPressed: () => state.redeploy(s.account, s.deployment.type),
            )
          : null,
      onTap: all.length < 2
          ? null
          : () async {
              final picked = await showDialog<WorkerType>(
                context: context,
                builder: (context) => SimpleDialog(
                  title: const Text('Type'),
                  children: [
                    RadioGroup<WorkerType>(
                      groupValue: s.deployment.type,
                      onChanged: (v) => Navigator.of(context).pop(v),
                      child: Column(
                        children: [
                          for (final d in all)
                            RadioListTile<WorkerType>(
                              value: d.type,
                              title: Text(d.type.label),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
              final d = picked == null ? null : s.account.deployment(picked);
              if (d != null) state.selectDeployment(s.account, d);
            },
    );
  }
}

/// Opens the Cloudflare accounts (like the WARP account tile in the WARP section).
class _CloudflareAccountsTile extends StatelessWidget {
  const _CloudflareAccountsTile();

  @override
  Widget build(BuildContext context) {
    final account = AppScope.of(context).selected?.account;
    return ListTile(
      leading: const Icon(Symbols.cloud_rounded),
      title: const Text('Cloudflare accounts'),
      subtitle: account == null
          ? null
          : Text(account.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Symbols.chevron_right_rounded),
      onTap: () =>
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) =>_CompactSettingsTheme(child:  const CfAccountsPage()))),
    );
  }
}


/// The installed app's version (pubspec.yaml's); opens the cores' versions.
class _VersionTile extends StatelessWidget {
  const _VersionTile();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: VpnChannel.appInfo().then((i) => i.version).catchError((_) => ''),
      builder: (context, snapshot) => ListTile(
        leading: const Icon(Symbols.info_rounded),
        title: const Text('Version'),
        subtitle: Text(snapshot.data ?? '…'),
        trailing: const Icon(Symbols.chevron_right_rounded),
        onTap: () =>
            Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) =>_CompactSettingsTheme(child:  const _VersionsPage()))),
      ),
    );
  }
}

/// The cores' versions: Xray, Psiphon and Tor.
class _VersionsPage extends StatelessWidget {
  const _VersionsPage();

  /// The core's module version as its short commit, as Psiphon's own builds record it: Psiphon
  /// no longer tags releases, so it's a pseudo-version (v1.0.11-0.20261005170209-c4a09096ab40 →
  /// Commit c4a0909).
  static String _psiphon(String s) {
    final commit = RegExp(r'-([0-9a-f]{7})[0-9a-f]{5}$')
        .firstMatch(s)
        ?.group(1);
    return commit != null ? 'Commit $commit' : s.replaceFirst(RegExp('^v'), '');
  }

  /// "Tor version 0.4.8.17." → 0.4.8.17.
  static String _tor(String s) =>
      RegExp(r'Tor version (\S+?)\.?(\s|$)').firstMatch(s)?.group(1) ??
      s.split('\n').first;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Version')),
      body: FutureBuilder(
        future: VpnChannel.versions(),
        builder: (context, snapshot) {
          final v = snapshot.data;
          String shown(String Function(String) format, String? raw) =>
              switch (raw) {
                null => snapshot.hasError ? 'Unknown' : '…',
                '' => 'Unknown',
                final r => format(r),
              };
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              SettingsCard(
                children: [
                  ListTile(
                    leading: const Icon(Symbols.widgets_rounded),
                    title: const Text('Xray core · Mod'),
                    subtitle: Text(shown((s) => s, v?.xray)),
                  ),
                  ListTile(
                    leading: const Icon(Symbols.cloud_rounded),
                    title: const Text('Worker version'),
                    subtitle: Text('v${CloudflareApi.workerVersion}'),
                  ),
                  ListTile(
                    leading: const Icon(Symbols.widgets_rounded),
                    title: const Text('Psiphon tunnel core · Mod'),
                    subtitle: Text(shown(_psiphon, v?.psiphon)),
                  ),
                  ListTile(
                    leading: const Icon(Symbols.widgets_rounded),
                    title: const Text('Tor Expert Bundle'),
                    subtitle: Text(shown(_tor, v?.tor)),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Checks GitHub for a newer release on request; the APK is downloaded in the browser.
class _UpdateTile extends StatefulWidget {
  const _UpdateTile();

  @override
  State<_UpdateTile> createState() => _UpdateTileState();
}

class _UpdateTileState extends State<_UpdateTile> {
  bool _checking = false;

  Future<void> _check() async {
    final state = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _checking = true);
    try {
      final update = await state.checkForUpdate();
      if (!mounted) return;
      if (update == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('BPB is up to date')),
        );
      } else {
        await _offer(update);
      }
    } on StateError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _offer(AppUpdate update) async {
    final download = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('BPB ${update.version} is available'),
        content: SingleChildScrollView(
          child: Text(
            update.notes.isEmpty ? 'No release notes.' : update.notes,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Download'),
          ),
        ],
      ),
    );
    if (download != true || !mounted) return;
    final url = update.apkUrl ?? update.pageUrl;
    final messenger = ScaffoldMessenger.of(context);
    if (!await VpnChannel.openUrl(url)) {
      await Clipboard.setData(ClipboardData(text: url));
      messenger.showSnackBar(
        const SnackBar(content: Text('Link copied. Open it in your browser.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Symbols.update_rounded),
      title: const Text('Check for updates'),
      subtitle: const Text('Latest release on GitHub'),
      trailing: _checking
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: _checking ? null : _check,
    );
  }
}

/// Downloads the latest geo assets (geoip.dat, geosite.dat) on request.
class _GeoAssetsTile extends StatefulWidget {
  const _GeoAssetsTile();

  @override
  State<_GeoAssetsTile> createState() => _GeoAssetsTileState();
}

class _GeoAssetsTileState extends State<_GeoAssetsTile>
    with AutomaticKeepAliveClientMixin<_GeoAssetsTile> {
  bool _updating = false;

  // Settings uses a lazy ListView. Keep this tile (and its in-flight download)
  // alive while it is scrolled out of view.
  @override
  bool get wantKeepAlive => _updating;
  String? _downloadingFile;
  double? _progress;

  Future<void> _update() async {
    final state = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _updating = true;
      _downloadingFile = null;
      _progress = null;
    });
    updateKeepAlive();
    try {
      await state.updateGeoAssets(
        onProgress: (file, received, total) {
          if (!mounted) return;
          setState(() {
            _downloadingFile = file;
            _progress = total != null && total > 0
                ? (received / total).clamp(0.0, 1.0).toDouble()
                : null;
          });
        },
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            state.isConnected
                ? 'Geo assets updated. Reconnect to use them.'
                : 'Geo assets updated successfully',
          ),
        ),
      );
    } on StateError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Geo assets update failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _updating = false;
          _downloadingFile = null;
          _progress = null;
        });
        updateKeepAlive();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final progressLabel = _downloadingFile == null
        ? 'Preparing download...'
        : 'Downloading $_downloadingFile'
              '${_progress == null ? '' : ' · ${(_progress! * 100).round()}%'}';
    final updatedAt = AppScope.of(context).geoAssetsUpdatedAt;
    final updatedLabel = updatedAt == null
        ? 'Latest Chocolate4U assets'
        : 'Last updated: ${updatedAt.year.toString().padLeft(4, '0')}-'
              '${updatedAt.month.toString().padLeft(2, '0')}-'
              '${updatedAt.day.toString().padLeft(2, '0')} '
              '${updatedAt.hour.toString().padLeft(2, '0')}:'
              '${updatedAt.minute.toString().padLeft(2, '0')}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: const Icon(Symbols.update_rounded),
          title: const Text('Update Geo assets'),
          subtitle: Text(
            _updating ? progressLabel : updatedLabel,
          ),
          trailing: _updating
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          onTap: _updating ? null : _update,
        ),
        if (_updating)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: LinearProgressIndicator(value: _progress),
          ),
      ],
    );
  }
}

/// Pretty JSON for display/copy.
String prettyJson(Object value) =>
    const JsonEncoder.withIndent('  ').convert(value);

/// Exports the profile (everything but the WARP account) as a JSON file: shared with an
/// app or saved to Downloads. Device settings and the worker are never included.
class _ExportSettingsTile extends StatelessWidget {
  /// Save to Downloads instead of opening the share sheet.
  final bool download;
  const _ExportSettingsTile({required this.download});

  Future<void> _export(BuildContext context) async {
    final state = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final name =
        'bpb-settings-${DateTime.now().toIso8601String().substring(0, 10)}.json';
    final content = state.exportSettingsFile();
    try {
      if (download) {
        final where = await VpnChannel.saveFile(name: name, content: content);
        if (where != null) {
          messenger.showSnackBar(SnackBar(content: Text('Saved to $where')));
        }
      } else {
        await VpnChannel.shareFile(
          name: name,
          content: content,
          title: 'Share settings',
        );
      }
    } on PlatformException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text("Couldn't export: ${e.message}")),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(download ? Symbols.download_rounded : Symbols.send_rounded),
    title: Text(download ? 'Export settings' : 'Share settings'),
    subtitle: Text(
      download
          ? 'Save settings file to Downloads'
          : 'Send settings file to other users',
    ),
    onTap: () => _export(context),
  );
}

/// Loads settings from a file made by "Share settings" or "Download settings".
class _ImportSettingsTile extends StatelessWidget {
  const _ImportSettingsTile();

  Future<void> _import(BuildContext context) async {
    final state = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final String? text;
    try {
      text = (await VpnChannel.pickFile())?.content;
    } on PlatformException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text("Couldn't read the file: ${e.message}")),
      );
      return;
    }
    if (text == null || !context.mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import settings?'),
        content: const Text(
          'Your settings are replaced with the ones in this file. '
          'Your WARP account, worker and this device\'s setup (per-app list, LAN sharing, theme…) stay as they are.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      state.importSettingsFile(text);
      messenger.showSnackBar(
        const SnackBar(content: Text('Settings imported')),
      );
    } on FormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Symbols.upload_rounded),
    title: const Text('Import settings'),
    subtitle: const Text('Load settings from a file'),
    onTap: () => _import(context),
  );
}
