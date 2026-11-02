import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';
import '../../data/models/customer.dart';
import '../../data/models/delivery.dart';
import '../../widgets/primitives.dart';

/// Status colours are semantic, not ordinal: delivered is good, not
/// delivered is critical, and the two in-flight states are neutral.
Color deliveryStatusColor(DeliveryStatus status) => switch (status) {
  DeliveryStatus.pending => VizPalette.inkMuted,
  DeliveryStatus.outForDelivery => VizPalette.statusWarning,
  DeliveryStatus.delivered => VizPalette.statusGood,
  DeliveryStatus.notDelivered => VizPalette.statusCritical,
  DeliveryStatus.cancelled => VizPalette.inkMuted,
};

IconData deliveryStatusIcon(DeliveryStatus status) => switch (status) {
  DeliveryStatus.pending => Icons.schedule_outlined,
  DeliveryStatus.outForDelivery => Icons.local_shipping_outlined,
  DeliveryStatus.delivered => Icons.check_circle_outline,
  DeliveryStatus.notDelivered => Icons.error_outline,
  DeliveryStatus.cancelled => Icons.cancel_outlined,
};

class DeliveryStatusChip extends StatelessWidget {
  const DeliveryStatusChip({
    super.key,
    required this.status,
    this.dense = false,
  });

  final DeliveryStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) => StatusChip(
    label: status.label,
    color: deliveryStatusColor(status),
    icon: deliveryStatusIcon(status),
    dense: dense,
  );
}

class SupportStatusChip extends StatelessWidget {
  const SupportStatusChip({super.key, required this.status});

  final SupportStatus status;

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon) = switch (status) {
      SupportStatus.none => (VizPalette.inkMuted, Icons.support_agent_outlined),
      SupportStatus.open => (VizPalette.statusSerious, Icons.support_agent),
      SupportStatus.resolved => (VizPalette.statusGood, Icons.task_alt),
    };
    return StatusChip(
      label: status.label,
      color: color,
      icon: icon,
      dense: true,
    );
  }
}
