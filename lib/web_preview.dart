import 'package:flutter/material.dart';
import 'models/theme_color.dart';
import 'ui/theme.dart';

void main() => runApp(const PreviewApp());

class PreviewApp extends StatefulWidget {
  const PreviewApp({super.key});
  @override
  State<PreviewApp> createState() => _PreviewAppState();
}

class _PreviewAppState extends State<PreviewApp> {
  ThemeMode mode = ThemeMode.dark;
  ThemeColor accent = ThemeColor.blue;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'BPB VPN (NotDev) · Web Preview',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(Brightness.light, accent),
    darkTheme: buildTheme(Brightness.dark, accent),
    themeMode: mode,
    home: PreviewHome(mode: mode, accent: accent,
      onMode: (v) => setState(() => mode = v),
      onAccent: (v) => setState(() => accent = v)),
  );
}

class PreviewHome extends StatefulWidget {
  final ThemeMode mode;
  final ThemeColor accent;
  final ValueChanged<ThemeMode> onMode;
  final ValueChanged<ThemeColor> onAccent;
  const PreviewHome({super.key, required this.mode, required this.accent, required this.onMode, required this.onAccent});
  @override
  State<PreviewHome> createState() => _PreviewHomeState();
}

class _PreviewHomeState extends State<PreviewHome> {
  int page = 0;
  bool connected = false, busy = false, tun = false, webRtc = true, antiSanctions = true;
  String type = 'VLESS', core = 'BPB Core', routing = 'Default', dns = '1.1.1.1';
  final profiles = <String>['Default', 'Backup'];
  final logs = <String>['Preview initialized', 'Mock services loaded', 'Ready to explore'];

  void notify(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  Future<void> toggle() async {
    if (busy) return;
    setState(() => busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() { connected = !connected; busy = false; });
    logs.insert(0, connected ? 'Preview connection enabled' : 'Preview connection stopped');
    notify(connected ? 'Preview only · No VPN tunnel was created' : 'Preview disconnected');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Row(mainAxisSize: MainAxisSize.min, children: [
        _Mark(), SizedBox(width: 9),
        Text.rich(TextSpan(children: [
          TextSpan(text: 'BPB VPN', style: TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: ' (NotDev)', style: TextStyle(fontSize: 13)),
        ])),
      ]),
      actions: [
        IconButton(tooltip: 'Logs', onPressed: () => setState(() => page = 2), icon: const Icon(Icons.bug_report_rounded, color: Color(0xFFEF5350))),
        IconButton(tooltip: 'View config', onPressed: () => setState(() => page = 3), icon: const Icon(Icons.data_object_rounded, color: Color(0xFF26A69A))),
        IconButton(tooltip: 'Settings', onPressed: () => setState(() => page = 1), icon: const Icon(Icons.settings_rounded, color: Color(0xFF4C8BF5))),
      ],
    ),
    body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: IndexedStack(index: page, children: [home(), settings(), logsPage(), configPage()]))),
    bottomNavigationBar: NavigationBar(selectedIndex: page, onDestinationSelected: (v) => setState(() => page = v), destinations: const [
      NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
      NavigationDestination(icon: Icon(Icons.tune_rounded), label: 'Settings'),
      NavigationDestination(icon: Icon(Icons.article_rounded), label: 'Logs'),
      NavigationDestination(icon: Icon(Icons.code_rounded), label: 'Config'),
    ]),
  );

  Widget home() => ListView(key: const PageStorageKey('home'), padding: const EdgeInsets.all(12), children: [
    card(Column(children: [
      Row(children: [
        const Icon(Icons.wifi_tethering_rounded, color: Color(0xFF4C8BF5)),
        const SizedBox(width: 10),
        const Expanded(child: Text('Connections', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
        PopupMenuButton<String>(initialValue: type, onSelected: (v) => setState(() => type = v),
          itemBuilder: (_) => ['VLESS','WARP','MASQUE','Aether','SSH','Tor','Psiphon','Serverless'].map((v) => PopupMenuItem(value: v, child: Text(v))).toList(),
          child: selector(type)),
      ]),
      const SizedBox(height: 12),
      choiceRow('Core', ['BPB Core','Aether'], core, (v) => setState(() => core = v)),
      choiceRow('Routing', ['Default','Global','Direct'], routing, (v) => setState(() => routing = v)),
    ])),
    const SizedBox(height: 10),
    card(Column(children: [
      const SizedBox(height: 8),
      AnimatedContainer(duration: const Duration(milliseconds: 200), width: 112, height: 112,
        decoration: BoxDecoration(shape: BoxShape.circle, color: busy ? Colors.blueGrey : connected ? const Color(0xFF168A49) : const Color(0xFFB52D3A),
          boxShadow: [BoxShadow(color: (connected ? const Color(0xFF39FF75) : const Color(0xFFFF4D5A)).withValues(alpha: .22), blurRadius: 26, spreadRadius: 3)]),
        child: IconButton(tooltip: 'Connect / disconnect (preview)', onPressed: toggle,
          icon: busy ? const SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white)) : const Icon(Icons.power_settings_new_rounded, size: 50, color: Colors.white))),
      const SizedBox(height: 14),
      Text(busy ? 'CONNECTING' : connected ? 'CONNECTED' : 'DISCONNECTED', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: connected ? const Color(0xFF39FF75) : null)),
      const SizedBox(height: 4),
      Text('Preview mode · VPN connection is simulated', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 18),
      SegmentedButton<bool>(segments: const [
        ButtonSegment(value: false, label: Text('Proxy'), icon: Icon(Icons.swap_horiz_rounded)),
        ButtonSegment(value: true, label: Text('TUN'), icon: Icon(Icons.language_rounded)),
      ], selected: {tun}, onSelectionChanged: (v) => setState(() => tun = v.first), showSelectedIcon: false),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: metric('My IP', connected ? '198.51.100.24' : '—', Icons.public_rounded)),
        const SizedBox(width: 8), Expanded(child: metric('Ping', connected ? '42 ms' : '—', Icons.speed_rounded)),
        const SizedBox(width: 8), Expanded(child: metric('Duration', connected ? '00:12:34' : '—', Icons.timer_rounded)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: metric('Download', connected ? '2.4 MB/s' : '0 B/s', Icons.download_rounded)),
        const SizedBox(width: 8), Expanded(child: metric('Upload', connected ? '640 KB/s' : '0 B/s', Icons.upload_rounded)),
      ]),
    ])),
    const SizedBox(height: 10),
    card(const Row(children: [Icon(Icons.info_outline_rounded, color: Color(0xFF4C8BF5)), SizedBox(width: 10), Expanded(child: Text('Interactive UI preview. Connect, TUN and traffic values are simulated.'))])),
  ]);

  Widget settings() => ListView(key: const PageStorageKey('settings'), padding: const EdgeInsets.all(12), children: [
    Text('Settings', style: Theme.of(context).textTheme.headlineSmall),
    card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Appearance', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Dark theme'), value: widget.mode == ThemeMode.dark, onChanged: (v) => widget.onMode(v ? ThemeMode.dark : ThemeMode.light)),
      const Text('Accent color'),
      Wrap(spacing: 8, children: ThemeColor.values.map((c) => ChoiceChip(label: Text(c.label), selected: widget.accent == c, onSelected: (_) => widget.onAccent(c))).toList()),
    ])),
    const SizedBox(height: 10),
    card(Column(children: [
      SwitchListTile(contentPadding: EdgeInsets.zero, secondary: const Icon(Icons.security_rounded), title: const Text('WebRTC Leak Protection'), subtitle: const Text('Preview preference only'), value: webRtc, onChanged: (v) => setState(() => webRtc = v)),
      const Divider(height: 1),
      SwitchListTile(contentPadding: EdgeInsets.zero, secondary: const Icon(Icons.shield_rounded), title: const Text('Anti-sanctions'), subtitle: const Text('Mock setting'), value: antiSanctions, onChanged: (v) => setState(() => antiSanctions = v)),
    ])),
    const SizedBox(height: 10),
    card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('DNS', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      DropdownButtonFormField<String>(initialValue: dns, decoration: const InputDecoration(labelText: 'Remote DNS'),
        items: const [DropdownMenuItem(value: '1.1.1.1', child: Text('1.1.1.1')), DropdownMenuItem(value: '8.8.8.8', child: Text('8.8.8.8')), DropdownMenuItem(value: '9.9.9.9', child: Text('9.9.9.9'))],
        onChanged: (v) => setState(() => dns = v ?? dns)),
    ])),
    const SizedBox(height: 10),
    card(Column(children: [
      ListTile(leading: const Icon(Icons.link_rounded), title: const Text('Chain Proxy'), subtitle: const Text('Sample profiles'), trailing: const Icon(Icons.chevron_right_rounded), onTap: manageProfiles),
      ListTile(leading: const Icon(Icons.account_tree_rounded), title: const Text('Routing'), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => notify('Routing screen preview')),
      ListTile(leading: const Icon(Icons.cable_rounded), title: const Text('Tor Bridges'), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => notify('Tor settings preview')),
      ListTile(leading: const Icon(Icons.volunteer_activism_rounded), title: const Text('Donation'), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => notify('Donation page preview')),
    ])),
    const SizedBox(height: 10),
    card(const ListTile(leading: Icon(Icons.info_outline_rounded), title: Text('About BPB VPN'), subtitle: Text('BPB VPN (NotDev) · Web UI Preview'))),
  ]);

  Widget logsPage() => ListView(key: const PageStorageKey('logs'), padding: const EdgeInsets.all(16), children: [
    Text('Logs', style: Theme.of(context).textTheme.headlineSmall),
    card(Column(children: [
      Row(children: [const Expanded(child: Text('Preview log')), IconButton(onPressed: () => setState(logs.clear), icon: const Icon(Icons.delete_outline_rounded))]),
      for (final item in logs) ListTile(dense: true, leading: const Icon(Icons.circle, size: 8, color: Color(0xFF39B978)), title: Text(item)),
    ])),
  ]);

  Widget configPage() => ListView(key: const PageStorageKey('config'), padding: const EdgeInsets.all(16), children: [
    Text('Configuration', style: Theme.of(context).textTheme.headlineSmall),
    card(Column(children: [
      const ListTile(title: Text('Sample profiles')),
      for (final item in profiles) ListTile(title: Text(item), trailing: IconButton(onPressed: () => setState(() => profiles.remove(item)), icon: const Icon(Icons.delete_outline_rounded))),
      Align(alignment: Alignment.centerRight, child: FilledButton.icon(onPressed: addProfile, icon: const Icon(Icons.add), label: const Text('Add profile'))),
    ])),
    const SizedBox(height: 10),
    card(const SelectableText('{\n  "preview": true,\n  "connection": "simulated",\n  "core": "mock"\n}', style: TextStyle(fontFamily: 'monospace'))),
  ]);

  void manageProfiles() => showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (ctx) => SafeArea(child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(16), children: [
    const Text('Chain Proxy profiles', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
    for (final item in profiles) ListTile(title: Text(item), trailing: IconButton(icon: const Icon(Icons.delete_outline_rounded), onPressed: () { setState(() => profiles.remove(item)); Navigator.pop(ctx); })),
    FilledButton.icon(onPressed: () { Navigator.pop(ctx); addProfile(); }, icon: const Icon(Icons.add), label: const Text('Add profile')),
  ])));

  Future<void> addProfile() async {
    final input = TextEditingController();
    final value = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Add sample profile'),
      content: TextField(controller: input, autofocus: true, decoration: const InputDecoration(labelText: 'Profile name')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, input.text.trim()), child: const Text('Add'))],
    ));
    input.dispose();
    if (value == null || value.isEmpty) return;
    setState(() => profiles.add(value));
    notify('Sample profile added');
  }

  Widget card(Widget child) => Card(
    margin: EdgeInsets.zero,
    color: Theme.of(context).colorScheme.surfaceContainer.withValues(alpha: .82),
    shape: roundedShape(kHeroRadius, side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .65), width: .75)),
    elevation: 0,
    child: Padding(padding: const EdgeInsets.all(18), child: child),
  );

  Widget selector(String value) => DecoratedBox(
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(20)),
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Row(mainAxisSize: MainAxisSize.min, children: [Text(value, style: const TextStyle(fontWeight: FontWeight.w700)), const SizedBox(width: 5), const Icon(Icons.expand_more_rounded, size: 18)])),
  );

  Widget choiceRow(String label, List<String> options, String value, ValueChanged<String> changed) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      Expanded(child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
      Wrap(spacing: 4, children: options.map((v) => ChoiceChip(label: Text(v), selected: value == v, onSelected: (_) => changed(v))).toList()),
    ]),
  );

  Widget metric(String label, String value, IconData icon) => DecoratedBox(
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .55), borderRadius: BorderRadius.circular(14)),
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 10), child: Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 14), const SizedBox(width: 4), Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)))]),
      const SizedBox(height: 4),
      FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
    ])),
  );
}

class _Mark extends StatelessWidget {
  const _Mark();
  @override
  Widget build(BuildContext context) => const SizedBox(width: 25, height: 25, child: Stack(children: [
    Positioned(left: 1, bottom: 1, child: CircleAvatar(radius: 9, backgroundColor: Color(0xFF0874E8))),
    Positioned(right: 3, top: 0, child: CircleAvatar(radius: 5, backgroundColor: Color(0xFF8ADFFF))),
    Positioned(right: 0, bottom: 4, child: CircleAvatar(radius: 3.5, backgroundColor: Color(0xFF168BFF))),
  ]));
}
