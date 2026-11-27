import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';

class V2rayManagerPage extends StatefulWidget {
  const V2rayManagerPage({super.key});
  @override
  State<V2rayManagerPage> createState() => _V2rayManagerPageState();
}

class _Subscription {
  final String id, name, url;
  const _Subscription(this.id, this.name, this.url);
  Map<String, String> toJson() => {'id': id, 'name': name, 'url': url};
  static _Subscription? parse(Object? v) {
    if (v is! Map || v['id'] is! String || v['name'] is! String) return null;
    final id = v['id'] as String, name = (v['name'] as String).trim();
    if (id.isEmpty || name.isEmpty) return null;
    return _Subscription(id, name, v['url'] is String ? (v['url'] as String).trim() : '');
  }
}

class _V2rayManagerPageState extends State<V2rayManagerPage> {
  static const _key = 'v2ray.subscriptions.v1';
  List<_Subscription> _items = [];
  String? _selectedId;
  bool _loading = true, _saving = false;
  _Subscription? get _selected => _items.where((s) => s.id == _selectedId).firstOrNull;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      var items = <_Subscription>[];
      if (raw == null) {
        items = [const _Subscription('default', 'Default', '')];
        await prefs.setString(_key, jsonEncode(items.map((s) => s.toJson()).toList()));
      } else {
        final decoded = jsonDecode(raw);
        if (decoded is List) items = decoded.map(_Subscription.parse).whereType<_Subscription>().toList();
      }
      if (!mounted) return;
      setState(() { _items = items; _selectedId = items.firstOrNull?.id; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(_items.map((s) => s.toJson()).toList()));
    } finally { if (mounted) setState(() => _saving = false); }
  }

  Future<void> _edit({_Subscription? item}) async {
    final name = TextEditingController(text: item?.name ?? '');
    final url = TextEditingController(text: item?.url ?? '');
    final result = await showDialog<({String name, String url})>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item == null ? 'Add subscription' : 'Edit subscription'),
        content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Name', prefixIcon: Icon(Symbols.label_outline_rounded))),
          const SizedBox(height: 12),
          TextField(controller: url, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Subscription URL', hintText: 'https://example.com/sub', prefixIcon: Icon(Symbols.link_rounded))),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            if (name.text.trim().isNotEmpty) Navigator.pop(ctx, (name: name.text.trim(), url: url.text.trim()));
          }, child: Text(item == null ? 'Add' : 'Save')),
        ],
      ),
    );
    name.dispose(); url.dispose();
    if (result == null || !mounted) return;
    setState(() {
      if (item == null) {
        final id = DateTime.now().microsecondsSinceEpoch.toString();
        _items = [..._items, _Subscription(id, result.name, result.url)];
        _selectedId = id;
      } else {
        _items = [for (final s in _items) if (s.id == item.id) _Subscription(s.id, result.name, result.url) else s];
      }
    });
    await _save();
  }

  Future<void> _delete() async {
    final item = _selected;
    if (item == null) return;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Delete subscription?'),
      content: Text('Remove ' + item.name + ' from this device?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD94B4B), foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
      ],
    ));
    if (ok != true || !mounted) return;
    setState(() {
      final index = _items.indexWhere((s) => s.id == item.id);
      _items = _items.where((s) => s.id != item.id).toList();
      _selectedId = _items.isEmpty ? null : _items[index.clamp(0, _items.length - 1)].id;
    });
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final selected = _selected;
    return Scaffold(
      appBar: AppBar(titleSpacing: 18, title: const Row(children: [
        Icon(Symbols.hub_rounded, color: Color(0xFFFFA34D), size: 23), SizedBox(width: 10),
        Text('V2Ray', style: TextStyle(fontWeight: FontWeight.w800)),
      ])),
      body: SafeArea(top: false, child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text('Subscriptions', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const Spacer(),
            IconButton.filledTonal(tooltip: 'Test server delay', onPressed: null, icon: const Icon(Symbols.bolt_rounded)),
            const SizedBox(width: 4),
            IconButton.filledTonal(tooltip: 'Edit selected subscription', onPressed: selected == null ? null : () => _edit(item: selected), icon: const Icon(Symbols.edit_rounded)),
            const SizedBox(width: 4),
            IconButton.filledTonal(tooltip: 'Add subscription', onPressed: _loading ? null : () => _edit(), icon: const Icon(Symbols.add_rounded)),
            const SizedBox(width: 4),
            IconButton(tooltip: 'Delete selected subscription', onPressed: selected == null ? null : _delete, icon: const Icon(Symbols.delete_outline_rounded)),
          ]),
          if (_saving) const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 8),
          SizedBox(height: 42, child: _loading
            ? const Align(alignment: Alignment.centerLeft, child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))
            : ListView(scrollDirection: Axis.horizontal, children: [
                for (final s in _items) Padding(padding: const EdgeInsets.only(right: 8),
                  child: _SubscriptionTab(label: s.name, selected: s.id == _selectedId, onTap: () => setState(() => _selectedId = s.id))),
              ])),
          const SizedBox(height: 14),
          Container(height: 44, padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withValues(alpha: .55),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: .65))),
            child: Row(children: [
              const Expanded(flex: 5, child: _ColumnHeading('Remark')),
              const Expanded(flex: 4, child: _ColumnHeading('Address')),
              SizedBox(width: 92, child: Align(alignment: Alignment.centerRight, child: _ColumnHeading('Delay (ms)'))),
            ])),
          Expanded(child: Container(
            decoration: BoxDecoration(border: Border(
              left: BorderSide(color: scheme.outlineVariant.withValues(alpha: .65)),
              right: BorderSide(color: scheme.outlineVariant.withValues(alpha: .65)),
              bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: .65))),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12))),
            child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 62, height: 62, decoration: BoxDecoration(color: const Color(0xFFFFA34D).withValues(alpha: .12), borderRadius: BorderRadius.circular(18)),
                  child: const Icon(Symbols.dns_rounded, size: 30, color: Color(0xFFFFA34D))),
                const SizedBox(height: 16),
                Text(_loading ? 'Loading subscriptions' : selected == null ? 'No subscription selected' : 'No configurations yet',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800), textAlign: TextAlign.center),
                const SizedBox(height: 7),
                Text(selected == null ? 'Add a subscription with the + button to get started.'
                  : selected.url.isEmpty ? 'Add a subscription URL with the edit button. Server links will appear here in the next step.'
                  : 'This subscription is saved. Importing and parsing its server links will be added in the next step.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant), textAlign: TextAlign.center),
              ]))))),
        ]),
      )),
    );
  }
}

class _SubscriptionTab extends StatelessWidget {
  final String label; final bool selected; final VoidCallback onTap;
  const _SubscriptionTab({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(mouseCursor: WidgetStateMouseCursor.clickable, onTap: onTap, borderRadius: BorderRadius.circular(9),
      child: Container(constraints: const BoxConstraints(minWidth: 76), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(color: selected ? scheme.primary.withValues(alpha: .13) : Colors.transparent,
          borderRadius: BorderRadius.circular(9), border: selected ? Border.all(color: scheme.primary.withValues(alpha: .35)) : null),
        child: Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: selected ? scheme.primary : scheme.onSurfaceVariant, fontWeight: FontWeight.w700))));
  }
}

class _ColumnHeading extends StatelessWidget {
  final String label; const _ColumnHeading(this.label);
  @override
  Widget build(BuildContext context) => Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
    style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w800));
}
