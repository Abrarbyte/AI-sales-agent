import 'package:flutter/material.dart';

import '../../core/utils/responsive.dart';
import '../../widgets/primitives.dart';

/// Audit log - full build in progress.
class AuditScreen extends StatelessWidget {
  const AuditScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: Responsive.pagePadding(Responsive.of(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const <Widget>[
          PageHeader(title: 'Audit log', subtitle: 'Every Admin and Rep action'),
          Card(
            child: EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Building this section next',
              message: 'Chronological log filterable by user, date and action type.',
            ),
          ),
        ],
      ),
    );
  }
}
