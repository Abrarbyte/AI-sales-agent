import '../api/api_client.dart';

/// What the console may do to a delivery: schedule it (#44), move it between
/// people and dates, or call it off. Marking one delivered, and recording a
/// failed attempt, stay with the field app - both need someone at the door
/// with the proof.
class DeliveryRepository {
  DeliveryRepository(this._api);

  final ApiClient _api;

  Future<void> schedule(Map<String, dynamic> body) =>
      _api.post('/api/delivery/deliveries/', body);

  /// The catalogue's active products, for picking what a milestone is for.
  Future<List<({String id, String name})>> products() async =>
      <({String id, String name})>[
        for (final Map<String, dynamic> p in await _api.getList(
          '/api/crm/products/?active=true',
        ))
          (id: p['id'].toString(), name: p['name']?.toString() ?? ''),
      ];

  Future<void> reassign(String deliveryId, String toRepId) => _api.patch(
    '/api/delivery/deliveries/$deliveryId/',
    <String, dynamic>{'assigned_to': int.tryParse(toRepId)},
  );

  Future<void> reschedule(String deliveryId, DateTime on) =>
      _api.patch('/api/delivery/deliveries/$deliveryId/', <String, dynamic>{
        'scheduled_on':
            '${on.year.toString().padLeft(4, '0')}-'
            '${on.month.toString().padLeft(2, '0')}-'
            '${on.day.toString().padLeft(2, '0')}',
      });

  Future<void> cancel(String deliveryId, {String notes = ''}) => _api.post(
    '/api/delivery/deliveries/$deliveryId/cancel/',
    <String, dynamic>{if (notes.isNotEmpty) 'notes': notes},
  );
}
