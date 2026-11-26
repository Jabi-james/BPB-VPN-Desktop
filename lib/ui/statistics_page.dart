import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../state/app_state.dart';
import 'format.dart';
import 'theme.dart';

const _download = Color(0xFF39FF75);
const _upload = Color(0xFF8B7CFF);
const _worker = Color(0xFF8B7CFF);
const _total = Color(0xFF46B8FF);

class StatisticsPage extends StatelessWidget {
  const StatisticsPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Statistics')),
    body: const SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: StatisticsPanel(),
    ),
  );
}

/// The same statistics cards can be embedded in the home dashboard or opened
/// from Settings. The cards themselves keep one shared implementation.
class StatisticsPanel extends StatelessWidget {
  const StatisticsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TrafficCard(
          download: state.allTimeDown,
          upload: state.allTimeUp,
          total: state.allTimeDown + state.allTimeUp,
        ),
        if (state.worker != null) ...[
          const SizedBox(height: 12),
          _WorkerRequestCard(),
        ],
      ],
    );
  }
}

/// One unified traffic panel: Download, Upload and Total always share one row.
class _TrafficCard extends StatelessWidget {
  final int download;
  final int upload;
  final int total;
  const _TrafficCard({required this.download, required this.upload, required this.total});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainer.withValues(alpha: 0.9),
      shape: roundedShape(kHeroRadius,
        side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.65))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 17, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: _total.withValues(alpha: 0.14),
                ),
                child: const Icon(Symbols.swap_vert_rounded, color: _total),
              ),
              const SizedBox(width: 11),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Traffic usage', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  Text('All-time data transfer', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              )),
            ]),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(child: _TrafficValue(label: 'DOWNLOAD', value: formatBytes(download), icon: Symbols.south_rounded, color: _download)),
              _verticalDivider(theme),
              Expanded(child: _TrafficValue(label: 'UPLOAD', value: formatBytes(upload), icon: Symbols.north_rounded, color: _upload)),
              _verticalDivider(theme),
              Expanded(child: _TrafficValue(label: 'TOTAL', value: formatBytes(total), icon: Symbols.swap_vert_rounded, color: _total)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _verticalDivider(ThemeData theme) => Container(
    width: 1, height: 48, margin: const EdgeInsets.symmetric(horizontal: 7),
    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
  );
}

class _TrafficValue extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _TrafficValue({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 7),
        Text(label, maxLines: 1, style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant, letterSpacing: 0.35, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
          child: Text(value, style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()]))),
      ],
    );
  }
}

class _WorkerRequestCard extends StatefulWidget {
  @override
  State<_WorkerRequestCard> createState() => _WorkerRequestCardState();
}
class _WorkerRequestCardState extends State<_WorkerRequestCard> {
  String? _selectedAccountId;
  static const _limit = 100000;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    if (_selectedAccountId == null) {
      final account = state.selected?.account ?? state.cfAccounts.firstOrNull;
      _selectedAccountId = account?.id;
      if (account != null && account.id != state.selected?.account.id) {
        unawaited(state.refreshUsageForAccount(account));
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final accounts = state.cfAccounts.where((a) => a.isComplete).toList();
    final account = accounts.where((a) => a.id == _selectedAccountId).firstOrNull ?? state.selected?.account;
    final active = account != null && account.id == state.selected?.account.id;
    final usage = account == null ? null : active ? state.usage : state.usageByAccount[account.id];
    final loading = account != null && (active ? state.loadingUsage : state.loadingUsageAccounts.contains(account.id));
    final error = account == null ? null : active ? state.usageError : state.usageErrorsByAccount[account.id];
    return Card(
      margin: EdgeInsets.zero, elevation: 0,
      color: theme.colorScheme.surfaceContainer.withValues(alpha: 0.9),
      shape: roundedShape(kHeroRadius,
        side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.65))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Symbols.data_usage_rounded, size: 21, color: _worker),
            const SizedBox(width: 9),
            Expanded(child: Text('Worker Request',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            if (accounts.length > 1 && account != null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 130),
                child: DropdownButtonHideUnderline(child: DropdownButton<String>(
                  value: account.id, isDense: true, isExpanded: true,
                  items: [for (final item in accounts)
                    DropdownMenuItem(value: item.id,
                      child: Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis))],
                  onChanged: state.isBusy ? null : (id) {
                    if (id == null) return;
                    final next = accounts.firstWhere((a) => a.id == id);
                    setState(() => _selectedAccountId = id);
                    if (next.id == state.selected?.account.id) {
                      unawaited(state.refreshUsage());
                    } else {
                      unawaited(state.refreshUsageForAccount(next));
                    }
                  },
                )),
              ),
            IconButton(
              tooltip: 'Refresh Worker requests',
              onPressed: loading || account == null ? null : () {
                if (active) { unawaited(state.refreshUsage()); }
                else { unawaited(state.refreshUsageForAccount(account)); }
              },
              icon: loading ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Symbols.refresh_rounded, size: 20),
            ),
          ]),
          const SizedBox(height: 12),
          if (usage != null) ...[
            _KeyValue('This worker', Text(formatCount(usage.worker),
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold,
                fontFeatures: const [FontFeature.tabularFigures()]))),
            const SizedBox(height: 10),
            _AccountUsage(total: usage.total, limit: _limit),
          ] else if (error != null)
            Text(error, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error))
          else
            Text(loading ? 'Loading…' : '—',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ]),
      ),
    );
  }
}
class _KeyValue extends StatelessWidget {
  final String label;
  final Widget value;
  const _KeyValue(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(children: [
      Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      const SizedBox(width: 12),
      Expanded(child: Align(alignment: AlignmentDirectional.centerEnd, child: value)),
    ]);
  }
}
class _AccountUsage extends StatelessWidget {
  final int total;
  final int limit;
  const _AccountUsage({required this.total, required this.limit});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = total / limit;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _KeyValue('Account total', Text.rich(TextSpan(children: [
        TextSpan(text: '${(ratio * 100).toStringAsFixed(1)}% · '),
        TextSpan(text: formatCount(total), style: const TextStyle(fontWeight: FontWeight.bold)),
      ]), style: theme.textTheme.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]))),
      const SizedBox(height: 10),
      LinearProgressIndicator(value: ratio.clamp(0.0, 1.0), minHeight: 6,
        borderRadius: BorderRadius.circular(3),
        color: ratio >= 0.9 ? theme.colorScheme.error : _worker),
    ]);
  }
}

