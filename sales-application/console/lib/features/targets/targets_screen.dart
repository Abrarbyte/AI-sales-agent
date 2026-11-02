import 'package:flutter/material.dart';

import '../../core/utils/responsive.dart';
import '../../widgets/primitives.dart';

/// Targets and incentives - full build in progress.
class TargetsScreen extends StatelessWidget {
  const TargetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: Responsive.pagePadding(Responsive.of(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const <Widget>[
          PageHeader(title: 'Targets and incentives', subtitle: 'Quotas, commission rules and payouts'),
          Card(
            child: EmptyState(
              icon: Icons.flag_outlined,
              title: 'Building this section next',
              message: 'Per-team targets, commission rules, payout approvals and attainment charts.',
            ),
          ),
        ],
      ),
    );
  }
}
