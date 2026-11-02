import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../photo_upload.dart';
import '../pipeline_labels.dart';
import '../theme.dart';
import '../widgets/form_sheet.dart';

/// The three delivery forms: schedule one, mark it delivered, or record a
/// failed attempt. Together in one file because they share the same small
/// vocabulary and are only ever reached from the customer or delivery
/// detail screens.

// ------------------------------------------------------------ schedule

class ScheduleDeliverySheet extends StatefulWidget {
  const ScheduleDeliverySheet({
    super.key,
    required this.customerId,
    this.address = '',
  });

  final int customerId;
  final String address;

  @override
  State<ScheduleDeliverySheet> createState() => _ScheduleDeliverySheetState();
}

class _ScheduleDeliverySheetState extends State<ScheduleDeliverySheet> {
  late final _address = TextEditingController(text: widget.address);
  final _notes = TextEditingController();

  List<dynamic> _products = const [];
  int? _productId;
  bool _required = true;
  String _milestone = 'handover';
  DateTime _on = DateTime.now().add(const Duration(days: 1));
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    try {
      final data = await Api.instance.get('/api/crm/products/?active=true');
      if (!mounted) return;
      setState(() {
        _products = data as List<dynamic>;
        if (_products.isNotEmpty) _productId ??= _products.first['id'] as int;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load the product list.');
    }
  }

  Future<void> _save() async {
    if (_productId == null) {
      setState(() => _error = 'Pick a product.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await Api.instance.post('/api/delivery/deliveries/', {
        'customer': widget.customerId,
        'product': _productId,
        'required': _required,
        'milestone': _milestone,
        'scheduled_on': apiDate(_on),
        'address': _address.text.trim(),
        'notes': _notes.text.trim(),
      });
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Cannot reach the server.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormSheet(
      title: 'Schedule handover',
      saveLabel: 'Schedule',
      saving: _saving,
      error: _error,
      onSave: _save,
      children: [
        const FieldLabel('Product / service'),
        DropdownButtonFormField<int>(
          initialValue: _productId,
          isExpanded: true,
          decoration: const InputDecoration(
              prefixIcon: Icon(Icons.inventory_2_outlined, size: 20)),
          items: [
            for (final p in _products)
              DropdownMenuItem(
                  value: p['id'] as int, child: Text(p['name'].toString())),
          ],
          onChanged: (v) => setState(() => _productId = v),
        ),
        const SizedBox(height: 20),
        ChoiceRow<String>(
          label: 'Milestone',
          options: PipelineLabels.milestones,
          value: _milestone,
          onChanged: (v) => setState(() => _milestone = v),
        ),
        const SizedBox(height: 20),
        ToggleRow(
          label: 'Client sign-off needed?',
          hint: 'Off for internal steps nobody signs',
          value: _required,
          onChanged: (v) => setState(() => _required = v),
        ),
        const SizedBox(height: 20),
        DateField(
          label: 'Target date',
          value: _on,
          firstDate: DateTime.now().subtract(const Duration(days: 1)),
          onChanged: (d) => setState(() => _on = d ?? _on),
        ),
        const SizedBox(height: 20),
        LabeledField(
          label: 'Where (meeting place or URL)',
          controller: _address,
          hint: 'Client office, Google Meet, staging link...',
          icon: Icons.place_outlined,
          lines: 2,
        ),
        const SizedBox(height: 20),
        LabeledField(
          label: 'Notes',
          controller: _notes,
          hint: 'What must be ready, who to meet...',
          lines: 2,
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ delivered

class DeliveredSheet extends StatefulWidget {
  const DeliveredSheet({super.key, required this.deliveryId});

  final int deliveryId;

  @override
  State<DeliveredSheet> createState() => _DeliveredSheetState();
}

class _DeliveredSheetState extends State<DeliveredSheet> {
  final _receivedBy = TextEditingController();
  final _notes = TextEditingController();
  XFile? _proof;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _receivedBy.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _takeProof() async {
    try {
      final shot = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: kPhotoMaxSide,
        maxHeight: kPhotoMaxSide,
        imageQuality: kCameraQuality,
      );
      if (shot != null && mounted) setState(() => _proof = shot);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not open the camera: $e');
    }
  }

  Future<void> _save() async {
    if (_receivedBy.text.trim().isEmpty) {
      setState(() => _error = 'Who received it?');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final proof =
          _proof == null ? null : await photoForUpload(_proof!, 'proof');
      final result = await Api.instance.postMultipart(
        '/api/delivery/deliveries/${widget.deliveryId}/deliver/',
        fields: {
          'received_by': _receivedBy.text.trim(),
          'notes': _notes.text.trim(),
        },
        fileField: 'proof',
        fileBytes: proof?.bytes,
        fileName: proof?.name ?? 'proof.jpg',
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Cannot reach the server.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FormSheet(
      title: 'Mark done',
      saveLabel: 'Done',
      saving: _saving,
      error: _error,
      onSave: _save,
      children: [
        LabeledField(
          label: 'Signed off by (client) *',
          controller: _receivedBy,
          hint: 'Who approved it on their side',
          icon: Icons.person_outline,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 20),
        const FieldLabel('Proof / document'),
        _proofBox(scheme),
        const SizedBox(height: 20),
        LabeledField(
          label: 'Notes',
          controller: _notes,
          hint: 'What was handed over, credentials shared...',
          lines: 2,
        ),
      ],
    );
  }

  Widget _proofBox(ColorScheme scheme) {
    if (_proof == null) {
      return OutlinedButton.icon(
        onPressed: _takeProof,
        icon: const Icon(Icons.photo_camera_outlined, size: 20),
        label: const Text('Take a photo'),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: Stack(
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: kIsWeb
                ? Image.network(_proof!.path, fit: BoxFit.cover)
                : Image.file(File(_proof!.path), fit: BoxFit.cover),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton.filled(
              style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                  foregroundColor: Colors.white),
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() => _proof = null),
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------- blocked

class NotDeliveredSheet extends StatefulWidget {
  const NotDeliveredSheet({super.key, required this.deliveryId});

  final int deliveryId;

  @override
  State<NotDeliveredSheet> createState() => _NotDeliveredSheetState();
}

class _NotDeliveredSheetState extends State<NotDeliveredSheet> {
  static const _reasons = PipelineLabels.blockedReasons;

  final _reasonNote = TextEditingController();
  final _notes = TextEditingController();
  String _reason = 'content_pending';
  DateTime? _retryOn = DateTime.now().add(const Duration(days: 1));
  bool _contacted = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _reasonNote.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await Api.instance.post(
        '/api/delivery/deliveries/${widget.deliveryId}/attempts/',
        {
          'reason': _reason,
          'reason_note': _reasonNote.text.trim(),
          'retry_on': _retryOn == null ? null : apiDate(_retryOn!),
          'customer_contacted': _contacted,
          'notes': _notes.text.trim(),
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Cannot reach the server.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormSheet(
      title: 'Blocked',
      saveLabel: 'Record attempt',
      saving: _saving,
      error: _error,
      destructive: true,
      onSave: _save,
      children: [
        ChoiceRow<String>(
          label: 'Reason',
          options: _reasons,
          value: _reason,
          onChanged: (v) => setState(() => _reason = v),
        ),
        const SizedBox(height: 20),
        LabeledField(
          label: 'What happened',
          controller: _reasonNote,
          hint: 'Gate locked, nobody answered...',
          icon: Icons.notes_outlined,
        ),
        const SizedBox(height: 20),
        DateField(
          label: 'Next date',
          value: _retryOn,
          allowClear: true,
          firstDate: DateTime.now(),
          onChanged: (d) => setState(() => _retryOn = d),
        ),
        const SizedBox(height: 20),
        ToggleRow(
          label: 'Customer contacted?',
          hint: 'Do they know it did not arrive',
          value: _contacted,
          onChanged: (v) => setState(() => _contacted = v),
        ),
        const SizedBox(height: 20),
        LabeledField(
          label: 'Notes',
          controller: _notes,
          hint: '',
          lines: 2,
        ),
      ],
    );
  }
}
