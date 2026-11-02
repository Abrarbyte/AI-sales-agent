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
    );
  }
}
