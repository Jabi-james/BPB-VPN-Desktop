import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'models/theme_color.dart';
import 'ui/theme.dart';
import 'ui/v2ray_manager_page.dart';

void main() => runApp(const PreviewApp());

class PreviewApp extends StatefulWidget {
  const PreviewApp({super.key});
  @override
  State<PreviewApp> createState() => _PreviewAppState();
}

class _PreviewAppState extends State<PreviewApp> {
  ThemeMode _themeMode = ThemeMode.dark;
  ThemeColor _themeColor = ThemeColor.blue;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'BPB VPN (NotDev)',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(Brightness.light, _themeColor),
    darkTheme: buildTheme(Brightness.dark, _themeColor),
    themeMode: _themeMode,
    home: _PreviewHome(
      onOpenV2Ray: _openV2Ray,
      onOpenSettings: (context) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _PreviewSettings(
          themeMode: _themeMode,
          themeColor: _themeColor,
          onThemeMode: (v) => setState(() => _themeMode = v),
          onThemeColor: (v) => setState(() => _themeColor = v),
          onOpenV2Ray: _openV2Ray,
        ),
      )),
    ),
  );

  void _openV2Ray(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const V2rayManagerPage(),
    ));
  }
}

class _PreviewHome extends StatefulWidget {
  final ValueChanged<BuildContext> onOpenV2Ray, onOpenSettings;
  const _PreviewHome({required this.onOpenV2Ray, required this.onOpenSettings});
  @override
  State<_PreviewHome> createState() => _PreviewHomeState();
}

class _PreviewHomeState extends State<_PreviewHome> {
  bool _panelOpen = false;
  bool _connected = false;
  String _backend = 'BPB';
  String _type = 'VLESS';
  String _core = 'BPB Core';
  String _mode = 'Default';
  String _exit = 'Default';
  bool _tun = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          const CustomPaint(size: Size(24, 24), painter: _BpbMarkPainter()),
          const SizedBox(width: 6),
          const Text.rich(TextSpan(children: [
            TextSpan(text: 'BPB VPN', style: TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(text: ' (NotDev)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ])),
        ]),
        actions: [
          IconButton(tooltip: 'Settings', onPressed: () => widget.onOpenSettings(context),
            icon: const Icon(Symbols.settings_rounded, color: Color(0xFF4C8BF5))),
        ],
      ),
      body: Stack(fit: StackFit.expand, children: [
        Positioned.fill(child: IgnorePointer(child: ClipRect(child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Image.asset('images/icon/bg.jpg', fit: BoxFit.cover,
            alignment: const Alignment(0, -0.18),
            errorBuilder: (_, _, _) => const SizedBox.shrink()),
        )))),
        SafeArea(bottom: false, child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(children: [
            const SizedBox(height: 6),
            _connectionCard(context, scheme, theme),
            const SizedBox(height: 10),
            _statusCard(context, scheme, theme),
          ]),
        )),
      ]),
    );
  }

  Widget _connectionCard(BuildContext context, ColorScheme scheme, ThemeData theme) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      shape: roundedShape(kHeroRadius, side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .75), width: .75)),
      color: scheme.surfaceContainer.withValues(alpha: .72),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          onTap: () => setState(() => _panelOpen = !_panelOpen),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(children: [
              Container(width: 36, height: 36,
                decoration: BoxDecoration(color: scheme.primary.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)),
                child: Icon(Symbols.wifi_tethering_rounded, color: scheme.primary, size: 21)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Connections', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                Text('Configure How to Connect and Routing Options', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ])),
              Icon(_panelOpen ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: scheme.onSurfaceVariant),
            ]),
          ),
        ),
        if (_panelOpen) Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Column(children: [
            Align(alignment: Alignment.centerLeft,
              child: Container(padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: scheme.surface.withValues(alpha: .55), borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: .65))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(width: 64, child: _backendTab('BPB', _backend == 'BPB', () => setState(() => _backend = 'BPB'))),
                  const SizedBox(width: 4),
                  SizedBox(width: 64, child: _backendTab('V2Ray', _backend == 'V2Ray', () {
                    setState(() => _backend = 'V2Ray');
                    widget.onOpenV2Ray(context);
                  })),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            _selectorRow(Symbols.category_rounded, const Color(0xFF4F9BFF), 'Type', _type,
              ['VLESS', 'WARP', 'MASQUE', 'Aether', 'SSH', 'Tor', 'Psiphon', 'Serverless'],
              (v) => setState(() => _type = v)),
            _selectorRow(Symbols.memory_rounded, const Color(0xFF9B7CFF), 'Core', _core,
              ['BPB Core', 'Aether'], (v) => setState(() => _core = v)),
            _selectorRow(Symbols.tune_rounded, const Color(0xFF26BFA5), 'Mode', _mode,
              ['Default', 'Global', 'Direct'], (v) => setState(() => _mode = v)),
            _selectorRow(Symbols.exit_to_app_rounded, const Color(0xFFFFA34D), 'Exit Node', _exit,
              ['Default', 'Chain proxy', 'Psiphon', 'Tor'], (v) => setState(() => _exit = v)),
          ]),
        ),
      ]),
    );
  }

  Widget _backendTab(String label, bool selected, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return Material(color: selected ? scheme.primary.withValues(alpha: .18) : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(mouseCursor: WidgetStateMouseCursor.clickable, borderRadius: BorderRadius.circular(10), onTap: onTap,
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 9),
          child: Center(child: Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800, color: selected ? scheme.primary : scheme.onSurfaceVariant))))));
  }

  Widget _selectorRow(IconData icon, Color color, String label, String selected,
      List<String> options, ValueChanged<String> onSelected) {
    final theme = Theme.of(context);
    return SizedBox(height: 42, child: Row(children: [
      Icon(icon, size: 20, color: color), const SizedBox(width: 8),
      Expanded(child: Text(label, style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
      PopupMenuButton<String>(tooltip: 'Select $label', initialValue: selected, onSelected: onSelected,
        itemBuilder: (_) => options.map((v) => PopupMenuItem(value: v, child: Text(v))).toList(),
        child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(selected, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(width: 4), const Icon(Icons.expand_more_rounded, size: 18),
          ])),
      ),
    ]));
  }

  Widget _statusCard(BuildContext context, ColorScheme scheme, ThemeData theme) {
    final green = const Color(0xFF39FF75);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: Colors.transparent, surfaceTintColor: Colors.transparent, elevation: 0,
      shape: roundedShape(kHeroRadius, side: BorderSide.none),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(children: [
          const SizedBox(height: 4),
          AnimatedContainer(duration: const Duration(milliseconds: 180), width: 104, height: 104,
            decoration: BoxDecoration(shape: BoxShape.circle,
              color: _connected ? const Color(0xFF168A49) : const Color(0xFFB52D3A),
              boxShadow: [BoxShadow(color: (_connected ? green : const Color(0xFFFF4D5A)).withValues(alpha: .22), blurRadius: 26, spreadRadius: 3)]),
            child: IconButton(tooltip: 'Preview only', onPressed: () => setState(() => _connected = !_connected),
              icon: const Icon(Icons.power_settings_new_rounded, size: 48, color: Colors.white))),
          const SizedBox(height: 12),
          Text(_connected ? 'CONNECTED' : 'DISCONNECTED', textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: .5,
              color: _connected ? green : scheme.onSurface)),
          const SizedBox(height: 4),
          Text(_connected ? 'Preview connection active' : 'Tap to connect',
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 18),
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Proxy'), icon: Icon(Symbols.swap_horiz_rounded)),
                ButtonSegment(value: true, label: Text('TUN'), icon: Icon(Symbols.language_rounded)),
              ],
              selected: {_tun}, onSelectionChanged: (v) => setState(() => _tun = v.first),
              showSelectedIcon: false,
              style: ButtonStyle(visualDensity: VisualDensity.compact,
                padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                shape: WidgetStateProperty.all(const StadiumBorder())),
            )),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: _metric(Symbols.location_on_rounded, 'My IP', '—')),
            const SizedBox(width: 8), Expanded(child: _metric(Symbols.speed_rounded, 'Ping', '—')),
            const SizedBox(width: 8), Expanded(child: _metric(Symbols.timer_rounded, 'Duration', '—')),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _speedMetric(Symbols.download_rounded, '0 B/s', const Color(0xFF39FF75))),
            const SizedBox(width: 8), const Expanded(child: SizedBox.shrink()),
            const SizedBox(width: 8), Expanded(child: _speedMetric(Symbols.upload_rounded, '0 B/s', const Color(0xFF8B7CFF))),
          ]),
        ]),
      ),
    );
  }

  Widget _metric(IconData icon, String label, String value) {
    final theme = Theme.of(context);
    return Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .48),
        borderRadius: BorderRadius.circular(14), border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: .48), width: .7)),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant), const SizedBox(width: 4),
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
        ]),
        const SizedBox(height: 6), Text(value, textAlign: TextAlign.center),
      ]),
    );
  }

  Widget _speedMetric(IconData icon, String value, Color color) {
    final theme = Theme.of(context);
    return Container(height: 44, padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .48),
        borderRadius: BorderRadius.circular(14), border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: .48), width: .7)),
      alignment: Alignment.center,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 16, color: color), const SizedBox(width: 6), Text(value, style: theme.textTheme.titleSmall),
      ]),
    );
  }
}

class _PreviewSettings extends StatelessWidget {
  final ThemeMode themeMode;
  final ThemeColor themeColor;
  final ValueChanged<ThemeMode> onThemeMode;
  final ValueChanged<ThemeColor> onThemeColor;
  final ValueChanged<BuildContext> onOpenV2Ray;
  const _PreviewSettings({required this.themeMode, required this.themeColor, required this.onThemeMode,
    required this.onThemeColor, required this.onOpenV2Ray});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Card(child: Column(children: [
          SwitchListTile(title: const Text('Dark theme'), value: themeMode == ThemeMode.dark,
            onChanged: (v) => onThemeMode(v ? ThemeMode.dark : ThemeMode.light)),
          ListTile(title: const Text('Accent color'), subtitle: Wrap(spacing: 8, children: [
            for (final c in ThemeColor.values) ChoiceChip(label: Text(c.label), selected: themeColor == c, onSelected: (_) => onThemeColor(c)),
          ])),
        ])),
        const SizedBox(height: 12),
        Card(child: ListTile(
          leading: const Icon(Symbols.hub_rounded, color: Color(0xFFFFA34D)),
          title: const Text('V2Ray'),
          subtitle: const Text('Manage V2Ray subscriptions and profiles'),
          trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
          onTap: () => onOpenV2Ray(context),
        )),
      ]),
    );
  }
}

class _BpbMarkPainter extends CustomPainter {
  const _BpbMarkPainter();
  @override
  void paint(Canvas canvas, Size size) {
    void circle(Offset center, double radius, List<Color> colors) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      final paint = Paint()..shader = RadialGradient(
        center: const Alignment(-.35, -.4), radius: 1.25, colors: colors,
      ).createShader(rect);
      canvas.drawCircle(center, radius, paint);
    }
    circle(Offset(size.width * .36, size.height * .65), size.width * .34,
      const [Color(0xFF42B7FF), Color(0xFF0874E8), Color(0xFF0752B5)]);
    circle(Offset(size.width * .66, size.height * .27), size.width * .17,
      const [Color(0xFF8ADFFF), Color(0xFF36AFFF), Color(0xFF168BFF)]);
    circle(Offset(size.width * .79, size.height * .57), size.width * .115,
      const [Color(0xFF62C8FF), Color(0xFF168BFF), Color(0xFF0752B5)]);
  }
  @override
  bool shouldRepaint(covariant _BpbMarkPainter oldDelegate) => false;
}
