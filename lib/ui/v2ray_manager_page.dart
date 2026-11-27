import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'theme.dart';

/// V2Ray's independent server-management workspace.
/// Subscription data, parsing and latency testing are intentionally added in later steps.
class V2rayManagerPage extends StatefulWidget {
  const V2rayManagerPage({super.key});

  @override
  State<V2rayManagerPage> createState() => _V2rayManagerPageState();
}

class _V2rayManagerPageState extends State<V2rayManagerPage> {
  int _selectedSubscription = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 18,
        title: Row(
          children: [
            const Icon(Symbols.hub_rounded, color: Color(0xFFFFA34D), size: 23),
            const SizedBox(width: 10),
            const Text('V2Ray', style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'Subscriptions',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  IconButton.filledTonal(
                    tooltip: 'Test server delay',
                    onPressed: null,
                    icon: const Icon(Symbols.bolt_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 42,
                child: Row(
                  children: [
                    _SubscriptionTab(
                      label: 'All',
                      selected: _selectedSubscription == 0,
                      onTap: () => setState(() => _selectedSubscription = 0),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.65)),
                ),
                child: Row(
                  children: [
                    const Expanded(flex: 5, child: _ColumnHeading('Remark')),
                    const Expanded(flex: 4, child: _ColumnHeading('Address')),
                    SizedBox(
                      width: 92,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _ColumnHeading('Delay (ms)'),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.65)),
                      right: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.65)),
                      bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.65)),
                    ),
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 62,
                              height: 62,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFA34D).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: const Icon(
                                Symbols.dns_rounded,
                                size: 30,
                                color: Color(0xFFFFA34D),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No configurations yet',
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 7),
                            Text(
                              'Your V2Ray servers will appear here. Importing links and subscriptions will be available in the next step.',
                              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubscriptionTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SubscriptionTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      mouseCursor: WidgetStateMouseCursor.clickable,
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        constraints: const BoxConstraints(minWidth: 76),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? scheme.primary.withValues(alpha: 0.13) : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: selected ? Border.all(color: scheme.primary.withValues(alpha: 0.35)) : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ColumnHeading extends StatelessWidget {
  final String label;
  const _ColumnHeading(this.label);

  @override
  Widget build(BuildContext context) => Text(
    label,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: Theme.of(context).textTheme.labelMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w800,
    ),
  );
}
