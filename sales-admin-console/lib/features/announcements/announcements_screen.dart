import 'package:flutter/material.dart';

import '../../core/utils/responsive.dart';
import '../../widgets/primitives.dart';

/// Announcements - full build in progress.
class AnnouncementsScreen extends StatelessWidget {
  const AnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: Responsive.pagePadding(Responsive.of(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const <Widget>[
          PageHeader(title: 'Announcements', subtitle: 'Broadcast to Admins and Reps'),
          Card(
            child: EmptyState(
              icon: Icons.campaign_outlined,
              title: 'Building this section next',
              message: 'Compose and send notifications, with delivery and read tracking.',
            ),
          ),
        ],
      ),
    );
  }
}
