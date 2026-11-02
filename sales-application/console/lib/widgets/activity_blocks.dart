import 'package:flutter/material.dart';

import '../core/company_profile.dart';
import '../core/theme/app_palette.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';
import '../data/models/activity.dart';
import '../data/models/delivery.dart';

/// The pieces an expanded lead or customer row is built from: a labelled
/// key/value block, and the visit, follow-up and handover lists that show
/// what the rep actually did with the account.

/// A small heading in the muted caps style every drawer block uses.
class BlockTitle extends StatelessWidget {
  const BlockTitle(this.text, {super.key, this.warn = false});

  final String text;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: warn ? VizPalette.statusCritical : VizPalette.inkMuted,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Label / value rows under a heading.
class KeyValueBlock extends StatelessWidget {
  const KeyValueBlock({
    super.key,
    required this.title,
    required this.rows,
    this.warn = false,
    this.width = 240,
    this.keyWidth = 96,
  });

  final String title;
  final List<(String, String)> rows;
  final bool warn;
  final double width;
  final double keyWidth;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          BlockTitle(title, warn: warn),
          for (final (String k, String v) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: keyWidth,
                    child: Text(
                      k,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: VizPalette.inkMuted,
                      ),
                    ),
                  ),
                  Expanded(child: Text(v, style: theme.textTheme.bodySmall)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A photo thumbnail that opens full-size in a dialog. Renders nothing when
/// there is no photo, so callers can drop it into a row unconditionally.
class PhotoThumb extends StatelessWidget {
  const PhotoThumb({super.key, required this.url, this.size = 40});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final String? u = url;
    if (u == null) return SizedBox(width: size, height: size);
    return SizedBox(
      width: size,
      height: size,
      child: InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => showDialog<void>(
        context: context,
        builder: (BuildContext context) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(AppSpacing.xl),
          child: Stack(
            children: <Widget>[
              InteractiveViewer(
                child: Image.network(
                  u,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Padding(
                    padding: EdgeInsets.all(AppSpacing.xxl),
                    child: Text(
                      'Photo could not be loaded',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          u,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            width: size,
            height: size,
            color: VizPalette.inkMuted.withValues(alpha: 0.15),
            child: Icon(
              Icons.broken_image_outlined,
              size: size * 0.5,
              color: VizPalette.inkMuted,
            ),
          ),
        ),
      ),
      ),
    );
  }
}

/// The visits logged against one account, newest first, with the count in
/// the heading - the number a manager asks for most.
class VisitsBlock extends StatelessWidget {
  const VisitsBlock({
    super.key,
    required this.visits,
    this.width = 360,
    this.limit = 6,
  });

  final List<FieldVisit> visits;
  final double width;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? muted = theme.textTheme.labelSmall?.copyWith(
      color: VizPalette.inkMuted,
    );
    final List<FieldVisit> sorted = List<FieldVisit>.of(visits)
      ..sort((FieldVisit a, FieldVisit b) => b.visitedAt.compareTo(a.visitedAt));
    final int withPhoto = visits.where((FieldVisit v) => v.photoUrl != null).length;

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          BlockTitle(
            'Visits (${visits.length})'
            '${visits.isEmpty ? '' : ' - $withPhoto with photo'}',
          ),
          if (sorted.isEmpty)
            Text('No visits logged yet.', style: muted)
          else
            for (final FieldVisit v in sorted.take(limit))
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    PhotoThumb(url: v.photoUrl, size: 36),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '${Fmt.dateTime(v.visitedAt)} - ${v.repName}'
                            '${v.durationMinutes == null ? '' : ' - ${v.durationMinutes} min'}',
                            style: muted,
                          ),
                          Text(
                            CompanyProfile.labelOf(
                              CompanyProfile.visitOutcomeLabels,
                              v.outcome,
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (v.notes.isNotEmpty)
                            Text(v.notes, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          if (sorted.length > limit)
            Text('+ ${sorted.length - limit} earlier', style: muted),
        ],
      ),
    );
  }
}

/// Follow-ups against one account: what is pending (overdue in red) and
/// how the done ones went.
class FollowUpsBlock extends StatelessWidget {
  const FollowUpsBlock({
    super.key,
    required this.followUps,
    this.width = 300,
    this.limit = 6,
  });

  final List<FollowUp> followUps;
  final double width;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? muted = theme.textTheme.labelSmall?.copyWith(
      color: VizPalette.inkMuted,
    );
    final List<FollowUp> sorted = List<FollowUp>.of(followUps)
      ..sort((FollowUp a, FollowUp b) {
        // Pending first, soonest due at the top; then done, newest first.
        if (a.isPending != b.isPending) return a.isPending ? -1 : 1;
        return a.isPending
            ? a.dueAt.compareTo(b.dueAt)
            : b.dueAt.compareTo(a.dueAt);
      });
    final int pending = followUps.where((FollowUp f) => f.isPending).length;

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          BlockTitle(
            'Follow-ups (${followUps.length})'
            '${pending > 0 ? ' - $pending pending' : ''}',
          ),
          if (sorted.isEmpty)
            Text('Nothing scheduled.', style: muted)
          else
            for (final FollowUp f in sorted.take(limit))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${CompanyProfile.labelOf(CompanyProfile.followUpKindLabels, f.kind)}'
                      ' - ${Fmt.dateTime(f.dueAt)}'
                      '${f.isPending ? (f.isOverdue ? '  (overdue)' : '') : '  - ${CompanyProfile.labelOf(CompanyProfile.followUpStatusLabels, f.status)}'}',
                      style: muted?.copyWith(
                        color: f.isPending && f.isOverdue
                            ? VizPalette.statusCritical
                            : null,
                      ),
                    ),
                    if (f.note.isNotEmpty)
                      Text(f.note, style: theme.textTheme.bodySmall),
                    if (f.outcomeNote.isNotEmpty)
                      Text(
                        'Outcome: ${f.outcomeNote}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: VizPalette.statusGood,
                        ),
                      ),
                  ],
                ),
              ),
          if (sorted.length > limit)
            Text('+ ${sorted.length - limit} more', style: muted),
        ],
      ),
    );
  }
}

/// A customer's handover milestones in one list.
class HandoversBlock extends StatelessWidget {
  const HandoversBlock({super.key, required this.deliveries, this.width = 320});

  final List<Delivery> deliveries;
  final double width;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? muted = theme.textTheme.labelSmall?.copyWith(
      color: VizPalette.inkMuted,
    );
    final List<Delivery> sorted = List<Delivery>.of(deliveries)
      ..sort((Delivery a, Delivery b) => b.scheduledOn.compareTo(a.scheduledOn));

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          BlockTitle('Handovers (${deliveries.length})'),
          if (sorted.isEmpty)
            Text('No milestones scheduled.', style: muted)
          else
            for (final Delivery d in sorted)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text.rich(
                  TextSpan(
                    style: theme.textTheme.bodySmall,
                    children: <InlineSpan>[
                      TextSpan(
                        text: CompanyProfile.labelOf(
                          CompanyProfile.milestoneLabels,
                          d.milestone,
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(
                        text: ' - ${Fmt.dateShort(d.scheduledOn)} - ',
                        style: muted,
                      ),
                      TextSpan(
                        text: d.status.label,
                        style: TextStyle(
                          color: switch (d.status) {
                            DeliveryStatus.delivered => VizPalette.statusGood,
                            DeliveryStatus.notDelivered =>
                              VizPalette.statusCritical,
                            _ => null,
                          },
                        ),
                      ),
                      if (d.receivedBy.isNotEmpty)
                        TextSpan(
                          text: ' - signed off by ${d.receivedBy}',
                          style: muted,
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
