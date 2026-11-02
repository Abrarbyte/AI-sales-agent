import '../api/api_client.dart';
import '../api/mappers.dart';
import '../models/lead.dart';
import '../models/ops.dart';

/// Leads, the stages they sit in, and the activity recorded against them.
///
/// The backend has no configurable pipeline: `Lead.Status` is the pipeline, and
/// its four values are fixed in code. `stages` therefore returns a constant set
/// rather than a fetched one, and the Configuration screen can show it but not
/// meaningfully edit it.
class PipelineSnapshot {
  const PipelineSnapshot({required this.leads, required this.activityByLead});

  final List<Lead> leads;

  /// Visits and follow-ups recorded against each lead, newest first.
  final Map<String, List<LeadActivity>> activityByLead;

  List<PipelineStage> get stages => Mappers.fixedStages;

  PipelineStage stageById(String id) => Mappers.stageFor(id);

  /// Stages with their live lead counts, for the funnel chart.
  List<PipelineStage> get stagesWithCounts => Mappers.fixedStages
      .map(
        (PipelineStage s) => PipelineStage(
          id: s.id,
          name: s.name,
          order: s.order,
          kind: s.kind,
          probability: s.probability,
          leadCount: leads.where((Lead l) => l.stageId == s.id).length,
        ),
      )
      .toList(growable: false);

  List<Lead> leadsForRep(String repId) =>
      leads.where((Lead l) => l.repId == repId).toList(growable: false);

  List<LeadActivity> activityFor(String leadId) =>
      activityByLead[leadId] ?? const <LeadActivity>[];
}

class PipelineRepository {
  PipelineRepository(this._api);

  final ApiClient _api;

  /// Loads the activity timeline.
  ///
  /// Both the leads and the visit rows come from [CompanySnapshot], which has
  /// already fetched them - this runs after that load, so requesting either
  /// again would download the same rows a second time. Only follow-ups, which
  /// nothing else reads, are fetched here.
  Future<PipelineSnapshot> load(
    List<Lead> leads,
    List<Map<String, dynamic>> visitRows,
  ) async {
    final List<Map<String, dynamic>> followUpRows = await _api.getList(
      '/api/visits/followups/',
    );

    final Map<String, List<LeadActivity>> byLead =
        <String, List<LeadActivity>>{};

    void record(String leadId, LeadActivity item) {
      (byLead[leadId] ??= <LeadActivity>[]).add(item);
    }

    for (final Map<String, dynamic> row in visitRows) {
      final String? leadId = row['lead']?.toString();
      if (leadId == null || leadId.isEmpty) continue;
      final DateTime? at = DateTime.tryParse(
        row['visited_at']?.toString() ?? '',
      );
      if (at == null) continue;
      final String outcome = row['outcome']?.toString() ?? '';
      record(
        leadId,
        LeadActivity(
          id: 'visit_${row['id']}',
          leadId: leadId,
          kind: LeadActivityKind.visit,
          summary: outcome.isEmpty
              ? 'Field visit to ${row['target_name'] ?? 'the account'}'
              : 'Field visit - $outcome',
          actorName: row['username']?.toString() ?? '',
          actorRole: 'sales_rep',
          at: at,
          detail: row['notes']?.toString(),
          visitId: row['id'].toString(),
        ),
      );
    }

    for (final Map<String, dynamic> row in followUpRows) {
      final String? leadId = row['lead']?.toString();
      if (leadId == null || leadId.isEmpty) continue;
      final DateTime? at = DateTime.tryParse(
        (row['completed_at'] ?? row['due_at'])?.toString() ?? '',
      );
      if (at == null) continue;
      record(
        leadId,
        LeadActivity(
          id: 'followup_${row['id']}',
          leadId: leadId,
          kind: LeadActivityKind.note,
          summary: row['status']?.toString() == 'completed'
              ? 'Follow-up completed'
              : 'Follow-up due',
          actorName: row['assigned_to_name']?.toString() ?? '',
          actorRole: 'sales_rep',
          at: at,
          detail: row['notes']?.toString(),
        ),
      );
    }

    for (final List<LeadActivity> items in byLead.values) {
      items.sort((LeadActivity a, LeadActivity b) => b.at.compareTo(a.at));
    }

    return PipelineSnapshot(leads: leads, activityByLead: byLead);
  }

  // -------------------------------------------------------------- mutations

  /// Moves a lead between stages.
  ///
  /// `converted` is rejected by the serializer on purpose - a lead becomes a
  /// customer through the convert endpoint, which creates the customer record
  /// too. [convert] is the way to reach that stage.
  Future<void> setStage(String leadId, String stageId) => _api.patch(
    '/api/crm/leads/$leadId/',
    <String, dynamic>{'status': stageId},
  );

  Future<void> convert(String leadId) =>
      _api.post('/api/crm/leads/$leadId/convert/');

  /// A lead entered at the office and handed to a rep. `body` is the API
  /// shape straight from [NewLeadDialog]; the server validates it.
  Future<void> createLead(Map<String, dynamic> body) =>
      _api.post('/api/crm/leads/', body);

  Future<void> reassignLead(String leadId, String toRepId) =>
      _api.patch('/api/crm/leads/$leadId/', <String, dynamic>{
        'assigned_to': int.tryParse(toRepId),
        // A lead handed to someone is being worked, not still untriaged.
        'status': 'assigned',
      });
}
