import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/activity.dart';
import '../../data/models/common.dart';
import '../../data/models/lead.dart';
import '../../data/models/people.dart';
import '../../data/repositories/company_repository.dart';
import '../shell/console_shell.dart';
import 'design_tokens.dart';

/// The cards only some roles' dashboards show (see `DashboardRole`). Each
/// reads the snapshot already loaded; none makes a request of its own.

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Card header: title on the left, a quiet caption on the right.
class _Header extends StatelessWidget {
  const _Header(this.title, this.caption, {this.onViewAll});

  final String title;
  final String caption;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(child: Text(title, style: Ds.h3)),
        if (onViewAll != null)
          InkWell(
            onTap: onViewAll,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text('View all', style: Ds.t12(Ds.brand600, w: 600)),
            ),
          )
        else
          Text(caption, style: Ds.t11(Ds.slate400)),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(text, style: Ds.t12(Ds.slate400)),
      );
}

/// One line of a list card: a name, a quieter line under it, a figure on the
/// right. The rows after the first get a hairline above.
class _Line extends StatelessWidget {
  const _Line({
    required this.title,
    required this.detail,
    required this.trailing,
    required this.first,
    this.trailingColor = Ds.slate800,
  });

  final String title;
  final String detail;
  final String trailing;
  final bool first;
  final Color trailingColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        border: first ? null : const Border(top: BorderSide(color: Ds.borderSoft)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, overflow: TextOverflow.ellipsis, style: Ds.t12(Ds.slate800, w: 600)),
                Text(detail, overflow: TextOverflow.ellipsis, style: Ds.t11(Ds.slate400)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(trailing, style: Ds.t12(trailingColor, w: 700)),
        ],
      ),
    );
  }
}

/// Super Admin: every team side by side - its reps, its open pipeline and
/// what it closed in the window.
class TeamsCard extends StatelessWidget {
  const TeamsCard({super.key, required this.co, required this.won, required this.days});

  final CompanySnapshot co;
  final List<Lead> won;
  final int days;

  @override
  Widget build(BuildContext context) {
    final List<(AdminUser, int, int, int, double)> rows = <(AdminUser, int, int, int, double)>[
      for (final AdminUser a in co.admins)
        (
          a,
          co.reps.where((SalesRep r) => r.adminId == a.id).length,
          co.reps
              .where((SalesRep r) => r.adminId == a.id && r.status == EntityStatus.active)
              .length,
          co.leads.where((Lead l) => l.adminId == a.id && l.isOpen).length,
          won
              .where((Lead l) => l.adminId == a.id)
              .fold<double>(0, (double s, Lead l) => s + l.value),
        ),
    ]..sort(((AdminUser, int, int, int, double) x, (AdminUser, int, int, int, double) y) =>
        y.$5.compareTo(x.$5));

    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Header('Teams', 'revenue, last $days days',
              onViewAll: () => openSection.value = NavSection.admins),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            const _Empty('No teams yet.')
          else
            for (int i = 0; i < rows.length; i++)
              _Line(
                first: i == 0,
                title: '${rows[i].$1.name} - ${rows[i].$1.roleWire.replaceAll('_', ' ')}',
                detail: '${rows[i].$3}/${rows[i].$2} reps active - '
                    '${rows[i].$4} open leads',
                trailing: Fmt.money(rows[i].$5),
              ),
        ],
      ),
    );
  }
}

/// Admin and Manager: who closed the most in the window.
class TopRepsCard extends StatelessWidget {
  const TopRepsCard({super.key, required this.won, required this.days});

  final List<Lead> won;
  final int days;

  @override
  Widget build(BuildContext context) {
    final Map<String, (String, int, double)> byRep = <String, (String, int, double)>{};
    for (final Lead l in won) {
      final (String, int, double) was = byRep[l.repId] ?? (l.repName, 0, 0);
      byRep[l.repId] = (was.$1, was.$2 + 1, was.$3 + l.value);
    }
    final List<(String, int, double)> top = byRep.values.toList()
      ..sort(((String, int, double) a, (String, int, double) b) => b.$3.compareTo(a.$3));

    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Header('Top reps', 'last $days days'),
          const SizedBox(height: 12),
          if (top.isEmpty)
            const _Empty('Nobody closed a deal in this period.')
          else
            for (int i = 0; i < top.length && i < 5; i++)
              _Line(
                first: i == 0,
                title: '${i + 1}. ${top[i].$1}',
                detail: '${top[i].$2} deal${top[i].$2 == 1 ? '' : 's'} won',
                trailing: Fmt.money(top[i].$3),
              ),
        ],
      ),
    );
  }
}

/// Admin and Manager: the field today - who has started work, how many
/// visits are logged, and which follow-ups are due or late.
class TodayCard extends StatelessWidget {
  const TodayCard({super.key, required this.co});

  final CompanySnapshot co;

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final int activeReps =
        co.reps.where((SalesRep r) => r.status == EntityStatus.active).length;
    final int checkedIn = co.attendance
        .where((AttendanceDay d) => _sameDay(d.date, now))
        .map((AttendanceDay d) => d.repId)
        .toSet()
        .length;
    final int visits = co.visits.where((FieldVisit v) => _sameDay(v.visitedAt, now)).length;
    final List<FollowUp> pending = co.followUps.where((FollowUp f) => f.isPending).toList();
    final int dueToday = pending.where((FollowUp f) => _sameDay(f.dueAt, now)).length;
    final int overdue = pending.where((FollowUp f) => f.isOverdue).length;

    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Header('Today in the field', Fmt.dateShort(now),
              onViewAll: () => openSection.value = NavSection.attendance),
          const SizedBox(height: 12),
          _Line(
            first: true,
            title: 'Checked in',
            detail: 'reps who have started their day',
            trailing: '$checkedIn / $activeReps',
          ),
          _Line(
            first: false,
            title: 'Visits logged',
            detail: 'so far today',
            trailing: Fmt.count(visits),
          ),
          _Line(
            first: false,
            title: 'Follow-ups due today',
            detail: 'still open',
            trailing: Fmt.count(dueToday),
          ),
          _Line(
            first: false,
            title: 'Overdue follow-ups',
            detail: 'past their due time',
            trailing: Fmt.count(overdue),
            trailingColor: overdue == 0 ? Ds.slate800 : Ds.rose700,
          ),
        ],
      ),
    );
  }
}

/// Manager: the team's next open follow-ups, late ones first.
class FollowUpsDueCard extends StatelessWidget {
  const FollowUpsDueCard({super.key, required this.co});

  final CompanySnapshot co;

  static String _due(FollowUp f) {
    final DateTime now = DateTime.now();
    if (f.isOverdue) return 'Late';
    if (_sameDay(f.dueAt, now)) return 'Today';
    if (_sameDay(f.dueAt, now.add(const Duration(days: 1)))) return 'Tomorrow';
    return Fmt.dateShort(f.dueAt);
  }

  @override
  Widget build(BuildContext context) {
    final List<FollowUp> next = co.followUps.where((FollowUp f) => f.isPending).toList()
      ..sort((FollowUp a, FollowUp b) => a.dueAt.compareTo(b.dueAt));

    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Header('Follow-ups due', 'open, soonest first'),
          const SizedBox(height: 12),
          if (next.isEmpty)
            const _Empty('No open follow-ups.')
          else
            for (int i = 0; i < next.length && i < 6; i++)
              _Line(
                first: i == 0,
                title: next[i].targetName,
                detail: '${next[i].repName} - ${next[i].kind}',
                trailing: _due(next[i]),
                trailingColor: next[i].isOverdue ? Ds.rose700 : Ds.slate800,
              ),
        ],
      ),
    );
  }
}
