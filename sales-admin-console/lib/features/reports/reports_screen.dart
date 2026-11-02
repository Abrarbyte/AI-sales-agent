import 'package:flutter/material.dart';

import '../../core/utils/responsive.dart';
import '../../widgets/primitives.dart';

/// Reports and analytics - full build in progress.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: Responsive.pagePadding(Responsive.of(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const <Widget>[
          PageHeader(title: 'Reports and analytics', subtitle: 'Revenue, conversion and compliance'),
          Card(
            child: EmptyState(
              icon: Icons.insights_outlined,
              title: 'Building this section next',
              message: 'Date-range and team filtered dashboards with CSV and PDF export.',
            ),
          ),
        ],
      ),
    );
  }
}
