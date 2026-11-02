import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../data/api/api_client.dart';
import '../../data/models/allowance.dart';
import '../../data/providers.dart';
import '../../data/repositories/company_repository.dart';
import '../../widgets/motion.dart';
import '../../widgets/primitives.dart';
import '../../widgets/table_panel.dart';
import '../dashboard/dashboard_panels.dart';

/// Travel allowance: the rupees-per-km rate a Super Admin sets, and the weekly
/// queue of per-day claims to approve, query, or reject. The distance and the
/// money are computed and frozen on the backend; the console sets the rate and
/// records the decision.
class TravelScreen extends ConsumerStatefulWidget {
  const TravelScreen({super.key});

  @override
  ConsumerState<TravelScreen> createState() => _TravelScreenState();
}

/// How far back the claims queue looks. Claims are costed per day, so a window
/// of days is the natural filter; a week matches the approval cycle.
enum _Range { week, month, quarter }

class _TravelScreenState extends ConsumerState<TravelScreen> {
  AllowanceRate? _rate;
  List<TravelClaim> _claims = const <TravelClaim>[];
  bool _loading = true;
  String? _error;

  _Range _range = _Range.week;
  ClaimStatus? _statusFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime get _since {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    return today.subtract(Duration(
      days: switch (_range) {
        _Range.week => 6,
        _Range.month => 29,
        _Range.quarter => 89,
      },
    ));
  }

  Future<void> _load() async {
    setState(() {
      _loading = _claims.isEmpty && _rate == null;
      _error = null;
    });
    final ApiClient api = ref.read(apiClientProvider);
    try {
      // The rate may legitimately be unset (404) before anyone has set one;
      // that is not an error, just an empty rate panel prompting the first one.
      AllowanceRate? rate;
      try {
        final dynamic raw = await api.get('/api/allowances/rate/');
        if (raw is Map<String, dynamic>) rate = AllowanceRate.fromJson(raw);
      } on ApiException catch (e) {
        if (e.statusCode != 404) rethrow;
      }

      final List<Map<String, dynamic>> rows = await api.getList(
        '/api/allowances/claims/',
        <String, dynamic>{
          'from': Fmt.apiDate(_since),
          if (_statusFilter != null) 'status': _statusFilter!.wire,
        },
      );
      setState(() {
        _rate = rate;
        _claims = rows.map(TravelClaim.fromJson).toList(growable: false);
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Cannot reach the server.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeRate() async {
    final _RateDraft? draft = await showDialog<_RateDraft>(
      context: context,
      builder: (_) => _RateDialog(current: _rate),
    );
    if (draft == null) return;
    try {
      await ref.read(apiClientProvider).post(
        '/api/allowances/rate/',
        <String, dynamic>{
          'rate_per_km': draft.ratePerKm.toStringAsFixed(2),
          'effective_from': Fmt.apiDate(draft.effectiveFrom),
          if (draft.note.isNotEmpty) 'note': draft.note,
        },
      );
    } on ApiException catch (e) {
      _toast(e.message, bad: true);
      return;
    }
    _toast('Rate updated.');
    _load();
  }

  Future<void> _decide(TravelClaim claim, ClaimStatus to) async {
    String note = '';
    // Approving is a yes; querying or rejecting usually carries a reason, so
    // those two ask for a note first.
    if (to != ClaimStatus.approved) {
      final String? entered = await showDialog<String>(
        context: context,
        builder: (_) => _NoteDialog(
          title: to == ClaimStatus.queried ? 'Query claim' : 'Reject claim',
          hint: to == ClaimStatus.queried
              ? 'What should the rep explain?'
              : 'Why is this claim rejected?',
        ),
      );
      if (entered == null) return; // cancelled
      note = entered;
    }

    final String action = switch (to) {
      ClaimStatus.approved => 'approve',
      ClaimStatus.queried => 'query',
      ClaimStatus.rejected => 'reject',
      ClaimStatus.pending => 'approve', // not reachable
    };
    try {
      await ref.read(apiClientProvider).post(
        '/api/allowances/claims/${claim.id}/$action/',
        <String, dynamic>{if (note.isNotEmpty) 'note': note},
      );
    } on ApiException catch (e) {
      _toast(e.message, bad: true);
      return;
    }
    _toast('${claim.repName}: ${to.label.toLowerCase()}.');
    _load();
  }

  void _toast(String message, {bool bad = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: bad ? VizPalette.statusCritical : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final LayoutSize size = Responsive.of(context);
    final SignedInUser? me = ref.watch(currentUserProvider).valueOrNull;
    // Managers and above decide claims on the backend (a manager only their own
    // team's); hide the controls for an employee rather than show buttons that
    // would 403. The backend is the real gate - this just keeps the UI honest.
    final String role = (me?.roleLabel ?? '').toLowerCase();
    final bool canReview = role.contains('admin') || role.contains('manager');

    final double total =
        _claims.fold(0, (double sum, TravelClaim c) => sum + c.amount);
    final int attention =
        _claims.where((TravelClaim c) => c.needsAttention).length;

    return SingleChildScrollView(
      padding: Responsive.pagePadding(size),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const PageHeader(
            title: 'Travel allowance',
            subtitle: 'The rate per kilometre, and the claims to approve',
          ),
          const SizedBox(height: AppSpacing.lg),
          Reveal(
            index: 0,
            child: _RatePanel(
              rate: _rate,
              canEdit: canReview,
              onChange: _changeRate,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Reveal(
            index: 1,
            child: DataBlock(children: <Widget>[
              _Toolbar(
                range: _range,
                status: _statusFilter,
                onRange: (_Range r) {
                  setState(() => _range = r);
                  _load();
                },
                onStatus: (ClaimStatus? s) {
                  setState(() => _statusFilter = s);
                  _load();
                },
                summary: _claims.isEmpty
                    ? ''
                    : '${_claims.length} claim${_claims.length == 1 ? '' : 's'}'
                        ' · ₹${total.toStringAsFixed(2)}'
                        '${attention == 0 ? '' : ' · $attention need a look'}',
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.xxl),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: ErrorNotice(message: _error!, onRetry: _load),
                )
              else if (_claims.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.xxl),
                  child: EmptyState(
                    icon: Icons.route_outlined,
                    title: 'No claims in this range',
                    message:
                        'Claims appear here once the weekly job has costed the '
                        'reps\' travel. Set a rate first if none is shown above.',
                  ),
                )
              else
                _ClaimsTable(
                  claims: _claims,
                  canReview: canReview,
                  onDecide: _decide,
                ),
            ]),
          ),
        ],
      ),
    );
  }
}

/// The current rate, plus a button to set a new one (admins only).
class _RatePanel extends StatelessWidget {
  const _RatePanel({
    required this.rate,
    required this.canEdit,
    required this.onChange,
  });

  final AllowanceRate? rate;
  final bool canEdit;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PanelHeader(
            title: 'Rate',
            subtitle: Text(
              rate == null
                  ? 'No rate set yet - claims cannot be costed until one is.'
                  : 'Applied to every day costed from its effective date. '
                      'Changing it never rewrites claims already paid.',
            ),
            trailing: canEdit
                ? FilledButton.icon(
                    onPressed: onChange,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(rate == null ? 'Set rate' : 'Change rate'),
                  )
                : null,
          ),
          const SizedBox(height: AppSpacing.md),
          if (rate == null)
            Text(
              'Set the rupees-per-km rate to start costing travel.',
              style:
                  theme.textTheme.bodySmall?.copyWith(color: VizPalette.inkMuted),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  '₹${rate!.ratePerKm.toStringAsFixed(2)}',
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('per km', style: theme.textTheme.bodySmall),
                ),
                const Spacer(),
                Flexible(
                  child: Text(
                    'In force from ${Fmt.date(rate!.effectiveFrom)}'
                    '${rate!.updatedByName.isEmpty ? '' : ' · set by ${rate!.updatedByName}'}',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: VizPalette.inkMuted),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.range,
    required this.status,
    required this.onRange,
    required this.onStatus,
    required this.summary,
  });

  final _Range range;
  final ClaimStatus? status;
  final ValueChanged<_Range> onRange;
  final ValueChanged<ClaimStatus?> onStatus;
  final String summary;

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Text('Claims', style: Theme.of(context).textTheme.titleMedium),
          PillDropdown<ClaimStatus?>(
            value: status,
            items: <ClaimStatus?>[null, ...ClaimStatus.values],
            labelOf: (ClaimStatus? s) => s == null ? 'All statuses' : s.label,
            onChanged: onStatus,
          ),
          PillDropdown<_Range>(
            value: range,
            items: _Range.values,
            labelOf: (_Range r) => switch (r) {
              _Range.week => 'Last 7 days',
              _Range.month => 'Last 30 days',
              _Range.quarter => 'Last 90 days',
            },
            onChanged: onRange,
          ),
          if (summary.isNotEmpty)
            Text(
              summary,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: VizPalette.inkMuted),
            ),
        ],
      ),
    );
  }
}

const List<double> _cols = <double>[90, 150, 90, 70, 100, 120, 110];

class _ClaimsTable extends StatelessWidget {
  const _ClaimsTable({
    required this.claims,
    required this.canReview,
    required this.onDecide,
  });

  final List<TravelClaim> claims;
  final bool canReview;
  final void Function(TravelClaim, ClaimStatus) onDecide;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Dt.theme(context);
    final TextStyle head = Dt.head;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final double width = c.maxWidth > 900 ? c.maxWidth : 900;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Row(
                      children: <Widget>[
                        SizedBox(width: _cols[0], child: Text('Date', style: head)),
                        SizedBox(width: _cols[1], child: Text('Rep', style: head)),
                        SizedBox(
                            width: _cols[2],
                            child: Text('Distance', style: head)),
                        SizedBox(width: _cols[3], child: Text('Rate', style: head)),
                        SizedBox(
                            width: _cols[4], child: Text('Amount', style: head)),
                        SizedBox(
                            width: _cols[5], child: Text('Source', style: head)),
                        SizedBox(
                            width: _cols[6], child: Text('Status', style: head)),
                        Expanded(
                          child: Text(
                            canReview ? 'Action' : '',
                            style: head,
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (final TravelClaim claim in claims)
                    _ClaimRow(
                      claim: claim,
                      canReview: canReview,
                      onDecide: onDecide,
                      theme: theme,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ClaimRow extends StatelessWidget {
  const _ClaimRow({
    required this.claim,
    required this.canReview,
    required this.onDecide,
    required this.theme,
  });

  final TravelClaim claim;
  final bool canReview;
  final void Function(TravelClaim, ClaimStatus) onDecide;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final TextStyle? muted =
        theme.textTheme.labelSmall?.copyWith(color: VizPalette.inkMuted);

    return Container(
      constraints:
          const BoxConstraints(minHeight: AppSpacing.tableRowHeight),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: _cols[0],
            child: Text(Fmt.dateShort(claim.date),
                style: theme.textTheme.bodySmall),
          ),
          SizedBox(
            width: _cols[1],
            child: Text(claim.repName,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium),
          ),
          SizedBox(
            width: _cols[2],
            child: Text('${claim.distanceKm.toStringAsFixed(2)} km',
                style: theme.textTheme.bodySmall),
          ),
          SizedBox(
            width: _cols[3],
            child: Text('₹${claim.ratePerKm.toStringAsFixed(2)}', style: muted),
          ),
          SizedBox(
            width: _cols[4],
            child: Text(
              '₹${claim.amount.toStringAsFixed(2)}',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(
            width: _cols[5],
            child: _SourceCell(claim: claim),
          ),
          SizedBox(
            width: _cols[6],
            child: Align(
              alignment: Alignment.centerLeft,
              child: StatusChip(
                label: claim.status.label,
                color: claim.status.color,
                icon: claim.status.icon,
                dense: true,
              ),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: canReview && !claim.status.isSettled
                  ? _ActionMenu(
                      onSelected: (ClaimStatus to) => onDecide(claim, to))
                  : (claim.status.isSettled && claim.approvedByName.isNotEmpty
                      ? Text('by ${claim.approvedByName}',
                          style: muted, overflow: TextOverflow.ellipsis)
                      : const SizedBox.shrink()),
            ),
          ),
        ],
      ),
    );
  }
}

/// Road vs estimate, with the flagged-leg warning folded in - the one column a
/// reviewer scans before trusting the distance.
class _SourceCell extends StatelessWidget {
  const _SourceCell({required this.claim});

  final TravelClaim claim;

  @override
  Widget build(BuildContext context) {
    final List<Widget> chips = <Widget>[
      if (claim.isEstimate)
        StatusChip(
          label: 'Estimate',
          color: VizPalette.statusSerious,
          icon: Icons.near_me_disabled_outlined,
          dense: true,
        )
      else if (claim.method == 'road')
        StatusChip(
          label: 'Road',
          color: VizPalette.statusGood,
          icon: Icons.alt_route_outlined,
          dense: true,
        )
      else
        StatusChip(
          label: 'Straight',
          color: VizPalette.inkMuted,
          icon: Icons.straighten_outlined,
          dense: true,
        ),
      if (claim.flaggedLegs.isNotEmpty)
        Tooltip(
          message:
              '${claim.flaggedLegs.length} leg(s) look like a GPS error - '
              'check the route before approving.',
          child: Icon(Icons.warning_amber_rounded,
              size: 15, color: VizPalette.statusCritical),
        ),
    ];
    return Wrap(spacing: 4, runSpacing: 4, children: chips);
  }
}

class _ActionMenu extends StatelessWidget {
  const _ActionMenu({required this.onSelected});

  final ValueChanged<ClaimStatus> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ClaimStatus>(
      tooltip: 'Decide',
      position: PopupMenuPosition.under,
      onSelected: onSelected,
      itemBuilder: (BuildContext context) => <PopupMenuEntry<ClaimStatus>>[
        const PopupMenuItem<ClaimStatus>(
          value: ClaimStatus.approved,
          child: _MenuRow(icon: Icons.check, label: 'Approve'),
        ),
        const PopupMenuItem<ClaimStatus>(
          value: ClaimStatus.queried,
          child: _MenuRow(icon: Icons.help_outline, label: 'Query'),
        ),
        const PopupMenuItem<ClaimStatus>(
          value: ClaimStatus.rejected,
          child: _MenuRow(icon: Icons.close, label: 'Reject'),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Dt.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('Decide',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: Dt.textSecondary)),
            const SizedBox(width: 2),
            const Icon(Icons.expand_more, size: 16, color: VizPalette.inkMuted),
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 16, color: VizPalette.inkMuted),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }
}

// --- Dialogs ----------------------------------------------------------------

class _RateDraft {
  const _RateDraft(this.ratePerKm, this.effectiveFrom, this.note);
  final double ratePerKm;
  final DateTime effectiveFrom;
  final String note;
}

class _RateDialog extends StatefulWidget {
  const _RateDialog({this.current});

  final AllowanceRate? current;

  @override
  State<_RateDialog> createState() => _RateDialogState();
}

class _RateDialogState extends State<_RateDialog> {
  late final TextEditingController _rate = TextEditingController(
    text: widget.current == null
        ? ''
        : widget.current!.ratePerKm.toStringAsFixed(2),
  );
  final TextEditingController _note = TextEditingController();
  DateTime _effectiveFrom = DateTime.now();
  String? _rateError;

  @override
  void dispose() {
    _rate.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    final double? value = double.tryParse(_rate.text.trim());
    if (value == null || value < 0) {
      setState(() => _rateError = 'Enter a rate like 2.50');
      return;
    }
    Navigator.of(context).pop(
      _RateDraft(value, _effectiveFrom, _note.text.trim()),
    );
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _effectiveFrom,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null) setState(() => _effectiveFrom = picked);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.current == null ? 'Set rate' : 'Change rate'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _rate,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Rate per km (₹)',
                prefixText: '₹ ',
                errorText: _rateError,
              ),
              onChanged: (_) {
                if (_rateError != null) setState(() => _rateError = null);
              },
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AppSpacing.md),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'In force from'),
              child: InkWell(
                onTap: _pickDate,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.event_outlined, size: 18),
                      const SizedBox(width: AppSpacing.sm),
                      Text(Fmt.date(_effectiveFrom)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _note,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                hintText: 'Why the rate changed',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Earlier claims keep the rate they were paid at. This applies to '
              'days costed on or after the date above.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: VizPalette.inkMuted),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.current == null ? 'Set' : 'Save'),
        ),
      ],
    );
  }
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: _note,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: 'Note',
            hintText: widget.hint,
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          // The note is optional; an empty one still records the decision.
          onPressed: () => Navigator.of(context).pop(_note.text.trim()),
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
