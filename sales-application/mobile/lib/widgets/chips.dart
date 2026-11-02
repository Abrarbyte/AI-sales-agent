import 'package:flutter/material.dart';

import '../pipeline_labels.dart';
import '../theme.dart';

/// `bg-primary/10 text-primary` pill with a shield, from the design's
/// role-chip component.
class RoleChip extends StatelessWidget {
  const RoleChip({super.key, required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_user_outlined, size: 14, color: primary),
          const SizedBox(width: 6),
          Text(
            role,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: primary),
          ),
        ],
      ),
    );
  }
}

/// Lead status pill. The design tints the background at 10% and uses the
/// darker shade for text, so each status reads as its own colour without
/// shouting.
class LeadStatusBadge extends StatelessWidget {
  const LeadStatusBadge({super.key, required this.status});

  final String status;

  static const _colors = <String, (Color, Color)>{
    'new': (AppTheme.blue500, AppTheme.blue600),
    'demo': (AppTheme.violet500, AppTheme.violet600),
    'negotiation': (AppTheme.orange500, AppTheme.orange600),
    'proposal': (AppTheme.violet500, AppTheme.violet600),
    'converted': (AppTheme.emerald500, AppTheme.emerald600),
    'closed': (AppTheme.rose500, AppTheme.rose600),
  };

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final pair = _colors[status] ?? _colors['new']!;
    // The design brightens the text a shade in dark mode so it stays legible
    // against the near-black background.
    final text = dark ? pair.$1 : pair.$2;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: pair.$1.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.isEmpty ? '' : PipelineLabels.label(PipelineLabels.stages, status),
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: text),
      ),
    );
  }
}

/// One of the three counters under the attendance card: big number first,
/// small label beneath, both left-aligned.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.danger = false,
  });

  final String label;
  final String value;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              height: 1.1,
              // Digits line up across the three tiles.
              fontFeatures: const [FontFeature.tabularFigures()],
              color: danger ? scheme.error : scheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// A status pill in a named colour: `bg` at 10%, `fg` for the text. Used
/// for delivery, support and negotiation states, which each have their own
/// vocabulary but the same shape.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

/// Wire status -> (label, colour) for each vocabulary the API speaks.
class Statuses {
  const Statuses._();

  static (String, Color) delivery(String? s) => switch (s) {
        'pending' => ('Scheduled', AppTheme.blue500),
        'out_for_delivery' => ('In progress', AppTheme.amber500),
        'delivered' => ('Done', AppTheme.emerald500),
        'not_delivered' => ('Blocked', AppTheme.rose500),
        'cancelled' => ('Cancelled', const Color(0xFF8A8A93)),
        _ => ('No milestone', const Color(0xFF8A8A93)),
      };

  static (String, Color) support(String? s) => switch (s) {
        'open' => ('Issue open', AppTheme.orange500),
        'resolved' => ('Resolved', AppTheme.emerald500),
        _ => ('No issues', const Color(0xFF8A8A93)),
      };

  static (String, Color) negotiation(String? s) => switch (s) {
        'in_progress' => ('In progress', AppTheme.blue500),
        'proposal_sent' => ('Proposal sent', AppTheme.violet500),
        'on_hold' => ('On hold', AppTheme.amber500),
        _ => ('Not opened', const Color(0xFF8A8A93)),
      };

  static (String, Color) demoOutcome(String? s) => switch (s) {
        'successful' => ('Successful', AppTheme.emerald500),
        'partial' => ('Partial', AppTheme.amber500),
        'unsuccessful' => ('Unsuccessful', AppTheme.rose500),
        'rescheduled' => ('Rescheduled', AppTheme.violet500),
        _ => ('No demo', const Color(0xFF8A8A93)),
      };
}
