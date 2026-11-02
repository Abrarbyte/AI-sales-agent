import 'package:flutter/foundation.dart';

/// Whether a customer has a support issue open. A flag on the backend, not a
/// ticket system - so three values and no history.
enum SupportStatus {
  none('none', 'No issues'),
  open('open', 'Issue open'),
  resolved('resolved', 'Resolved');

  const SupportStatus(this.wire, this.label);

  final String wire;
  final String label;

  static SupportStatus fromWire(String? v) => SupportStatus.values.firstWhere(
    (SupportStatus s) => s.wire == v,
    orElse: () => SupportStatus.none,
  );
}

/// One payment received from a customer (#42).
@immutable
class CustomerPayment {
  const CustomerPayment({
    required this.id,
    required this.amount,
    required this.receivedOn,
    required this.method,
    this.reference = '',
    this.notes = '',
    this.recordedBy = '',
  });

  final String id;
  final double amount;
  final DateTime receivedOn;

  /// upi | bank_transfer | cash | cheque | card | other
  final String method;
  final String reference;
  final String notes;
  final String recordedBy;

  factory CustomerPayment.fromJson(Map<String, dynamic> json) =>
      CustomerPayment(
        id: json['id'].toString(),
        amount: double.tryParse(json['amount']?.toString() ?? '') ?? 0,
        receivedOn:
            DateTime.tryParse(json['received_on']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        method: json['method']?.toString() ?? 'other',
        reference: json['reference']?.toString() ?? '',
        notes: json['notes']?.toString() ?? '',
        recordedBy: json['recorded_by_name']?.toString() ?? '',
      );
}

/// Someone who has bought. Created by converting a lead, or directly.
@immutable
class Customer {
  const Customer({
    required this.id,
    required this.name,
    required this.companyName,
    required this.phone,
    required this.email,
    required this.address,
    required this.city,
    required this.repId,
    required this.repName,
    required this.products,
    required this.customerSince,
    required this.supportStatus,
    required this.isActive,
    required this.createdAt,
    this.deliveryStatus,
    this.notes = '',
    this.projectStatus = 'not_started',
    this.goLiveOn,
    this.domain = '',
    this.hosting = 'none',
    this.maintenancePlan = 'none',
    this.maintenanceRenewsOn,
    this.price,
    this.amountPaid = 0,
    this.isPaidInFull = false,
    this.payments = const <CustomerPayment>[],
    this.completedAt,
  });

  final String id;
  final String name;
  final String companyName;
  final String phone;
  final String email;
  final String address;
  final String city;
  final String repId;
  final String repName;

  /// Catalogue names, e.g. "Solar 5kW".
  final List<String> products;

  final DateTime customerSince;
  final SupportStatus supportStatus;

  /// Wire status of the most recent delivery, or null if none was scheduled.
  final String? deliveryStatus;

  final bool isActive;
  final DateTime createdAt;
  final String notes;

  // The build and what outlives it.
  final String projectStatus;
  final DateTime? goLiveOn;
  final String domain;
  final String hosting;
  final String maintenancePlan;
  final DateTime? maintenanceRenewsOn;

  /// The agreed price for everything they've bought; null until agreed
  /// (#41). What's been paid comes from [payments].
  final double? price;
  final double amountPaid;
  final bool isPaidInFull;
  final List<CustomerPayment> payments;

  /// When the project was marked completed (#43); null until then.
  final DateTime? completedAt;

  /// Still due; null while no price has been agreed. Negative only for old
  /// data where more was recorded than the price.
  double? get balance => price == null ? null : price! - amountPaid;

  bool get onMaintenance => maintenancePlan != 'none';

  String get displayName => companyName.isEmpty ? name : companyName;

  factory Customer.fromJson(Map<String, dynamic> json, {String? repName}) {
    final DateTime created =
        DateTime.tryParse(json['created_at']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return Customer(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? '',
      companyName: json['company_name']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      repId: json['assigned_to']?.toString() ?? '',
      repName: repName ?? json['assigned_to_name']?.toString() ?? 'Unassigned',
      products: (json['product_names'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic e) => e.toString())
          .toList(growable: false),
      customerSince:
          DateTime.tryParse(json['customer_since']?.toString() ?? '') ??
          created,
      supportStatus: SupportStatus.fromWire(json['support_status']?.toString()),
      deliveryStatus: json['delivery_status']?.toString(),
      isActive: json['is_active'] as bool? ?? true,
      createdAt: created,
      notes: json['notes']?.toString() ?? '',
      projectStatus: json['project_status']?.toString() ?? 'not_started',
      goLiveOn: DateTime.tryParse(json['go_live_on']?.toString() ?? ''),
      domain: json['domain']?.toString() ?? '',
      hosting: json['hosting']?.toString() ?? 'none',
      maintenancePlan: json['maintenance_plan']?.toString() ?? 'none',
      maintenanceRenewsOn:
          DateTime.tryParse(json['maintenance_renews_on']?.toString() ?? ''),
      price: json['price'] == null
          ? null
          : double.tryParse(json['price'].toString()),
      amountPaid: double.tryParse(json['amount_paid']?.toString() ?? '') ?? 0,
      isPaidInFull: json['is_paid_in_full'] as bool? ?? false,
      completedAt: DateTime.tryParse(json['completed_at']?.toString() ?? ''),
      payments: <CustomerPayment>[
        for (final dynamic raw
            in json['payments'] as List<dynamic>? ?? const <dynamic>[])
          if (raw is Map)
            CustomerPayment.fromJson(raw.cast<String, dynamic>()),
      ],
    );
  }
}
