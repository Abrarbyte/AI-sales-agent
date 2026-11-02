import 'package:flutter/foundation.dart';

/// Pipeline stage. The set is configurable per company (Configuration screen),
/// so this enum mirrors the DEFAULT seed only - `Lead.stageId` carries the
/// configured stage's id and `stageName` its label, which is what the UI shows.
enum LeadStageKind {
  open('open'),
  won('won'),
  lost('lost');

  const LeadStageKind(this.wire);

  final String wire;

  static LeadStageKind fromWire(String? v) => LeadStageKind.values.firstWhere(
    (LeadStageKind k) => k.wire == v,
    orElse: () => LeadStageKind.open,
  );
}

/// The latest demo given to a lead, as the lead row carries it.
@immutable
class DemoSummary {
  const DemoSummary({
    required this.id,
    required this.heldAt,
    required this.product,
    required this.outcome,
    this.interested,
    this.mode = '',
    this.shown = '',
    this.attendees = '',
    this.feedback = '',
    this.notes = '',
    this.givenBy = '',
  });

  final String id;
  final DateTime heldAt;
  final String product;

  /// successful | partial | unsuccessful | rescheduled
  final String outcome;
  final bool? interested;

  /// online | client_site | office
  final String mode;

  /// portfolio | prototype | live_project | other
  final String shown;
  final String attendees;
  final String feedback;
  final String notes;
  final String givenBy;

  factory DemoSummary.fromJson(Map<String, dynamic> json) => DemoSummary(
    id: json['id'].toString(),
    heldAt:
        DateTime.tryParse(json['held_at']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    product: json['product']?.toString() ?? '',
    outcome: json['outcome']?.toString() ?? '',
    interested: json['interested'] as bool?,
    mode: json['mode']?.toString() ?? '',
    shown: json['shown']?.toString() ?? '',
    attendees: json['attendees']?.toString() ?? '',
    feedback: json['feedback']?.toString() ?? '',
    notes: json['notes']?.toString() ?? '',
    givenBy: json['given_by_name']?.toString() ?? '',
  );
}

/// The lead's negotiation, as the lead row carries it.
@immutable
class NegotiationSummary {
  const NegotiationSummary({
    required this.id,
    required this.status,
    required this.decisionMaker,
    required this.isSlipping,
    this.expectedCloseOn,
    this.quotedAmount,
    this.paymentTerms = '',
    this.startedAt,
    this.requirements = '',
    this.scope = '',
    this.objections = '',
    this.proposedSolution = '',
    this.terms = '',
    this.discountPct,
    this.paymentTermsNote = '',
    this.timelineWeeks,
    this.competitor = '',
    this.proposalUrl,
    this.notes = '',
  });

  final String id;

  /// in_progress | proposal_sent | on_hold | won | lost
  final String status;
  final String decisionMaker;

  /// Past the expected close and still open.
  final bool isSlipping;
  final DateTime? expectedCloseOn;
  final double? quotedAmount;
  final String paymentTerms;
  final DateTime? startedAt;
  final String requirements;
  final String scope;
  final String objections;
  final String proposedSolution;
  final String terms;
  final double? discountPct;
  final String paymentTermsNote;
  final int? timelineWeeks;
  final String competitor;
  final String? proposalUrl;
  final String notes;

  String get statusLabel => switch (status) {
    'in_progress' => 'In progress',
    'proposal_sent' => 'Proposal sent',
    'on_hold' => 'On hold',
    'won' => 'Won',
    'lost' => 'Lost',
    _ => status,
  };

  factory NegotiationSummary.fromJson(Map<String, dynamic> json) =>
      NegotiationSummary(
        id: json['id'].toString(),
        status: json['status']?.toString() ?? '',
        decisionMaker: json['decision_maker']?.toString() ?? '',
        isSlipping: json['is_slipping'] as bool? ?? false,
        quotedAmount: json['quoted_amount'] == null
            ? null
            : double.tryParse(json['quoted_amount'].toString()),
        paymentTerms: json['payment_terms']?.toString() ?? '',
        startedAt: json['started_at'] == null
            ? null
            : DateTime.tryParse(json['started_at'].toString()),
        requirements: json['requirements']?.toString() ?? '',
        scope: json['scope']?.toString() ?? '',
        objections: json['objections']?.toString() ?? '',
        proposedSolution: json['proposed_solution']?.toString() ?? '',
        terms: json['terms']?.toString() ?? '',
        discountPct: json['discount_pct'] == null
            ? null
            : double.tryParse(json['discount_pct'].toString()),
        paymentTermsNote: json['payment_terms_note']?.toString() ?? '',
        timelineWeeks: (json['timeline_weeks'] as num?)?.toInt(),
        competitor: json['competitor']?.toString() ?? '',
        proposalUrl: json['proposal']?.toString(),
        notes: json['notes']?.toString() ?? '',
        expectedCloseOn: json['expected_close_on'] == null
            ? null
            : DateTime.tryParse(json['expected_close_on'].toString()),
      );
}

@immutable
class Lead {
  const Lead({
    required this.id,
    required this.companyName,
    required this.contactName,
    required this.phone,
    required this.email,
    required this.stageId,
    required this.stageName,
    required this.stageKind,
    required this.stageOrder,
    required this.source,
    required this.value,
    required this.repId,
    required this.repName,
    required this.adminId,
    required this.teamName,
    required this.createdAt,
    required this.updatedAt,
    this.lastVisitAt,
    this.nextActionAt,
    this.convertedAt,
    this.city = '',
    this.notes = '',
    this.requirement = '',
    this.designation = '',
    this.industry = '',
    this.projectType = '',
    this.platforms = '',
    this.existingUrl = '',
    this.priority = 'warm',
    this.budget,
    this.expectedStart,
    this.lostReason = '',
    this.demoCount = 0,
    this.latestDemo,
    this.negotiation,
  });

  final String id;
  final String companyName;
  final String contactName;
  final String phone;
  final String email;

  /// Configured stage this lead sits in.
  final String stageId;
  final String stageName;

  /// Whether that stage counts as open / won / lost for conversion maths.
  final LeadStageKind stageKind;

  /// Position of the stage in the pipeline, used to order the funnel chart.
  final int stageOrder;

  final String source;

  /// Deal value in company currency.
  final double value;

  final String repId;
  final String repName;

  /// Denormalised owning team, so cross-team filtering needs no join client-side.
  final String adminId;
  final String teamName;

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastVisitAt;
  final DateTime? nextActionAt;

  /// When the lead became a customer; null while open or lost.
  final DateTime? convertedAt;
  final String city;
  final String notes;

  /// What the account wants - a product line, a quantity, a problem.
  final String requirement;

  // The agency fields: who we talk to, what business they are in, what
  // they want built, and what they said they can spend.
  final String designation;
  final String industry;
  final String projectType;
  final String platforms;
  final String existingUrl;
  final String priority;
  final double? budget;
  final DateTime? expectedStart;
  final String lostReason;

  final int demoCount;
  final DemoSummary? latestDemo;
  final NegotiationSummary? negotiation;

  bool get isOpen => stageKind == LeadStageKind.open;

  /// Days since anything happened on this lead. Drives the "stale" flag.
  int get ageDays => DateTime.now().difference(updatedAt).inDays;

  bool get isStale => isOpen && ageDays >= 14;

  factory Lead.fromJson(Map<String, dynamic> json) => Lead(
    id: json['id'].toString(),
    companyName: json['company_name']?.toString() ?? '',
    contactName: json['contact_name']?.toString() ?? '',
    phone: json['phone']?.toString() ?? '',
    email: json['email']?.toString() ?? '',
    stageId: json['stage_id'].toString(),
    stageName: json['stage_name']?.toString() ?? '',
    stageKind: LeadStageKind.fromWire(json['stage_kind']?.toString()),
    stageOrder: (json['stage_order'] as num?)?.toInt() ?? 0,
    source: json['source']?.toString() ?? '',
    value: (json['value'] as num?)?.toDouble() ?? 0,
    repId: json['rep_id'].toString(),
    repName: json['rep_name']?.toString() ?? '',
    adminId: json['admin_id'].toString(),
    teamName: json['team_name']?.toString() ?? '',
    createdAt: DateTime.parse(json['created_at'].toString()),
    updatedAt: DateTime.parse(json['updated_at'].toString()),
    lastVisitAt: json['last_visit_at'] == null
        ? null
        : DateTime.parse(json['last_visit_at'].toString()),
    nextActionAt: json['next_action_at'] == null
        ? null
        : DateTime.parse(json['next_action_at'].toString()),
    city: json['city']?.toString() ?? '',
    notes: json['notes']?.toString() ?? '',
    requirement: json['requirement']?.toString() ?? '',
    demoCount: (json['demo_count'] as num?)?.toInt() ?? 0,
    latestDemo: json['latest_demo'] == null
        ? null
        : DemoSummary.fromJson(
            (json['latest_demo'] as Map).cast<String, dynamic>(),
          ),
    negotiation: json['negotiation'] == null
        ? null
        : NegotiationSummary.fromJson(
            (json['negotiation'] as Map).cast<String, dynamic>(),
          ),
  );

  Lead copyWith({
    String? repId,
    String? repName,
    String? adminId,
    String? teamName,
    String? stageId,
    String? stageName,
    LeadStageKind? stageKind,
    int? stageOrder,
  }) => Lead(
    id: id,
    companyName: companyName,
    contactName: contactName,
    phone: phone,
    email: email,
    stageId: stageId ?? this.stageId,
    stageName: stageName ?? this.stageName,
    stageKind: stageKind ?? this.stageKind,
    stageOrder: stageOrder ?? this.stageOrder,
    source: source,
    value: value,
    repId: repId ?? this.repId,
    repName: repName ?? this.repName,
    adminId: adminId ?? this.adminId,
    teamName: teamName ?? this.teamName,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
    lastVisitAt: lastVisitAt,
    nextActionAt: nextActionAt,
    convertedAt: convertedAt,
    city: city,
    notes: notes,
    requirement: requirement,
    demoCount: demoCount,
    latestDemo: latestDemo,
    negotiation: negotiation,
  );
}

/// One entry in a lead's timeline: a note, a stage move, a visit, a reassignment.
enum LeadActivityKind {
  created('created', 'Created'),
  stageChange('stage_change', 'Stage changed'),
  note('note', 'Note'),
  call('call', 'Call'),
  visit('visit', 'Visit'),
  reassigned('reassigned', 'Reassigned'),
  merged('merged', 'Merged'),
  valueChange('value_change', 'Value changed');

  const LeadActivityKind(this.wire, this.label);

  final String wire;
  final String label;

  static LeadActivityKind fromWire(String? v) =>
      LeadActivityKind.values.firstWhere(
        (LeadActivityKind k) => k.wire == v,
        orElse: () => LeadActivityKind.note,
      );
}

@immutable
class LeadActivity {
  const LeadActivity({
    required this.id,
    required this.leadId,
    required this.kind,
    required this.summary,
    required this.actorName,
    required this.actorRole,
    required this.at,
    this.detail,
    this.visitId,
  });

  final String id;
  final String leadId;
  final LeadActivityKind kind;
  final String summary;
  final String actorName;
  final String actorRole;
  final DateTime at;
  final String? detail;

  /// Set when [kind] is [LeadActivityKind.visit], so the row can deep-link into
  /// the visit's proof.
  final String? visitId;

  factory LeadActivity.fromJson(Map<String, dynamic> json) => LeadActivity(
    id: json['id'].toString(),
    leadId: json['lead_id'].toString(),
    kind: LeadActivityKind.fromWire(json['kind']?.toString()),
    summary: json['summary']?.toString() ?? '',
    actorName: json['actor_name']?.toString() ?? '',
    actorRole: json['actor_role']?.toString() ?? '',
    at: DateTime.parse(json['at'].toString()),
    detail: json['detail']?.toString(),
    visitId: json['visit_id']?.toString(),
  );
}
