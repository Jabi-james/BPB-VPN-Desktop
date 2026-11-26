import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/cf_account.dart';
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
        if (state.worker != null && state.mode.needsWorker) ...[
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
    final scheme = theme.colorScheme;
    final accounts = state.cfAccounts.where((a) => a.isComplete).toList();
    final account = accounts.where((a) => a.id == _selectedAccountId).firstOrNull
        ?? state.selected?.account;
    final activeAccount = account != null &&
        account.id == state.selected?.account.id;
    final usage = account == null
        ? null
        : activeAccount ? state.usage : state.usageByAccount[account.id];
    final loading = account != null && (activeAccount
        ? state.loadingUsage
        : state.loadingUsageAccounts.contains(account.id));
    final usageError = account == null
        ? null
        : activeAccount ? state.usageError : state.usageErrorsByAccount[account.id];
    final total = usage?.total ?? 0;
    final ratio = (total / _limit).clamp(0.0, 1.0).toDouble();
    final remaining = (_limit - total).clamp(0, _limit).toInt();

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surfaceContainer.withValues(alpha: 0.92),
      shape: roundedShape(kHeroRadius,
        side: BorderSide(color: _worker.withValues(alpha: 0.42))),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [_worker.withValues(alpha: 0.28), _worker.withValues(alpha: 0.08)],
                ),
              ),
              child: const Icon(Symbols.cloud_sync_rounded, color: _worker, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Worker Request', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              Text('Cloudflare · Last 24 hours', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ])),
            if (accounts.length > 1 && account != null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 126),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: account.id,
                    isDense: true,
                    isExpanded: true,
                    icon: const Icon(Symbols.expand_more_rounded, size: 18),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurface, fontWeight: FontWeight.w700,
                    ),
                    items: [
                      for (final item in accounts)
                        DropdownMenuItem(
                          value: item.id,
                          child: Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                    ],
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
                  ),
                ),
              ),
            IconButton(
              tooltip: 'Refresh Worker requests',
              onPressed: loading || account == null ? null : () {
                if (activeAccount) {
                  unawaited(state.refreshUsage());
                } else {
                  unawaited(state.refreshUsageForAccount(account));
                }
              },
              icon: loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Symbols.refresh_rounded),
            ),
          ]),
          const SizedBox(height: 14),
          if (usage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: _worker.withValues(alpha: 0.075),
                border: Border.all(color: _worker.withValues(alpha: 0.18)),
              ),
              child: Row(children: [
                SizedBox(
                  width: 82, height: 82,
                  child: Stack(alignment: Alignment.center, children: [
                    SizedBox.expand(child: CircularProgressIndicator(
                      value: ratio, strokeWidth: 8, strokeCap: StrokeCap.round,
                      backgroundColor: scheme.surfaceContainerHighest,
                      color: ratio >= 0.9 ? scheme.error : _worker,
                    )),
                    Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('${(ratio * 100).toStringAsFixed(1)}%',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                      Text('USED', style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant, letterSpacing: 0.8)),
                    ]),
                  ]),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(formatCount(total), style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900, fontFeatures: const [FontFeature.tabularFigures()])),
                  ),
                  const SizedBox(height: 2),
                  Text('requests in the last 24 hours',
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 9),
                  Row(children: [
                    Icon(Symbols.hourglass_bottom_rounded, size: 15, color: _worker),
                    const SizedBox(width: 5),
                    Flexible(child: Text('${formatCount(remaining)} remaining',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700))),
                  ]),
                ])),
              ]),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _WorkerBreakdown(label: 'THIS WORKER', value: formatCount(usage.worker), color: _worker)),
              const SizedBox(width: 7),
              Expanded(child: _WorkerBreakdown(label: 'ACCOUNT TOTAL', value: formatCount(usage.total), color: _total)),
              const SizedBox(width: 7),
              Expanded(child: _WorkerBreakdown(label: 'DAILY LIMIT', value: formatCount(_limit), color: scheme.onSurfaceVariant)),
            ]),
          ] else if (usageError != null) ...[
            Text(usageError, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error)),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(child: Text(
                loading ? 'Loading request usage…' : 'No request data available',
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))),
            ),
        ]),
      ),
    );
  }

  static const _limit = 100000;
}

class _WorkerBreakdown extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _WorkerBreakdown({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 11, 8, 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant, fontSize: 9, letterSpacing: 0.25)),
        const SizedBox(height: 5),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
          child: Text(value, style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()]))),
      ]),
    );
  }
}
