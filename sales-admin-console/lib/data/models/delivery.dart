import 'package:flutter/foundation.dart';

/// Where a delivery is. Only the backend moves it - through /deliver/,
/// /attempts/ and /cancel/ - so the console reads it and never writes it.
enum DeliveryStatus {
  pending('pending', 'Scheduled'),
  outForDelivery('out_for_delivery', 'In progress'),
  delivered('delivered', 'Done'),
  notDelivered('not_delivered', 'Blocked'),
  cancelled('cancelled', 'Cancelled');

  const DeliveryStatus(this.wire, this.label);

  final String wire;
  final String label;

  bool get isFinal =>
      this == DeliveryStatus.delivered || this == DeliveryStatus.cancelled;

  static DeliveryStatus fromWire(String? v) => DeliveryStatus.values.firstWhere(
    (DeliveryStatus s) => s.wire == v,
    orElse: () => DeliveryStatus.pending,
  );
}

/// Why a delivery did not land.
enum AttemptReason {
  contentPending('content_pending', 'Client content pending'),
  feedbackPending('feedback_pending', 'Client feedback pending'),
  scopeChange('scope_change', 'Scope changed'),
  paymentPending('payment_pending', 'Payment pending'),
  technicalIssue('technical_issue', 'Technical issue'),
  clientUnavailable('client_unavailable', 'Client unavailable'),
  other('other', 'Other');

  const AttemptReason(this.wire, this.label);

  final String wire;
  final String label;

  static AttemptReason fromWire(String? v) => AttemptReason.values.firstWhere(
    (AttemptReason r) => r.wire == v,
    orElse: () => AttemptReason.other,
  );
}

/// One failed try at a delivery.
@immutable
class DeliveryAttempt {
  const DeliveryAttempt({
    required this.id,
    required this.reason,
    required this.reasonNote,
    required this.attemptedAt,
    required this.customerContacted,
    this.retryOn,
  });

  final String id;
  final AttemptReason reason;
  final String reasonNote;
  final DateTime attemptedAt;
  final bool customerContacted;
  final DateTime? retryOn;

  factory DeliveryAttempt.fromJson(Map<String, dynamic> json) =>
      DeliveryAttempt(
        id: json['id'].toString(),
        reason: AttemptReason.fromWire(json['reason']?.toString()),
        reasonNote: json['reason_note']?.toString() ?? '',
        attemptedAt:
            DateTime.tryParse(json['attempted_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        customerContacted: json['customer_contacted'] as bool? ?? false,
        retryOn: json['retry_on'] == null
            ? null
            : DateTime.tryParse(json['retry_on'].toString()),
      );
}

@immutable
class Delivery {
  const Delivery({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.productName,
    this.milestone = 'handover',
    required this.required,
    required this.scheduledOn,
    required this.repId,
    required this.repName,
    required this.address,
    required this.status,
    required this.isOverdue,
    required this.attemptCount,
    required this.createdAt,
    this.deliveredAt,
    this.receivedBy = '',
    this.proofUrl,
    this.lastAttempt,
    this.notes = '',
  });

  final String id;
  final String customerId;
  final String customerName;
  final String productName;

  /// Which step of the project this row hands over.
  final String milestone;

  /// False for a service or a collection - the row exists so the customer's
  /// list is complete, but nobody drives anywhere.
  final bool required;

  final DateTime scheduledOn;
  final String repId;
  final String repName;
  final String address;
  final DeliveryStatus status;
  final bool isOverdue;
  final int attemptCount;
  final DateTime createdAt;

  final DateTime? deliveredAt;
  final String receivedBy;
  final String? proofUrl;
  final DeliveryAttempt? lastAttempt;
  final String notes;

  factory Delivery.fromJson(Map<String, dynamic> json, {String? repName}) {
    final Map<String, dynamic>? last = (json['last_attempt'] as Map?)
        ?.cast<String, dynamic>();
    return Delivery(
      id: json['id'].toString(),
      customerId: json['customer'].toString(),
      customerName: json['customer_name']?.toString() ?? '',
      productName: json['product_name']?.toString() ?? '',
      milestone: json['milestone']?.toString() ?? 'handover',
      required: json['required'] as bool? ?? true,
      scheduledOn:
          DateTime.tryParse(json['scheduled_on']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      repId: json['assigned_to']?.toString() ?? '',
      repName: repName ?? json['assigned_to_name']?.toString() ?? 'Unassigned',
      address: json['address']?.toString() ?? '',
      status: DeliveryStatus.fromWire(json['status']?.toString()),
      isOverdue: json['is_overdue'] as bool? ?? false,
      attemptCount: (json['attempt_count'] as num?)?.toInt() ?? 0,
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      deliveredAt: json['delivered_at'] == null
          ? null
          : DateTime.tryParse(json['delivered_at'].toString()),
      receivedBy: json['received_by']?.toString() ?? '',
      proofUrl: json['proof']?.toString(),
      lastAttempt: last == null ? null : DeliveryAttempt.fromJson(last),
      notes: json['notes']?.toString() ?? '',
    );
  }
}
