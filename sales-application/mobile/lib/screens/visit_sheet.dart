import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../location.dart';
import '../place_name.dart';
import '../photo_upload.dart';
import '../theme.dart';
import '../widgets/form_sheet.dart';

/// Log a field visit against a lead or a customer: how it went, how long it
/// took, a photo from the site, and where the phone was. One multipart POST.
class VisitSheet extends StatefulWidget {
  const VisitSheet({super.key, this.leadId, this.customerId, this.targetName = ''})
      : assert((leadId == null) != (customerId == null),
            'A visit is against exactly one lead or one customer');

  final int? leadId;
  final int? customerId;
  final String targetName;

  @override
  State<VisitSheet> createState() => _VisitSheetState();
}

class _VisitSheetState extends State<VisitSheet> {
  static const _outcomes = [
    ('interested', 'Interested'),
    ('not_interested', 'Not interested'),
    ('follow_up', 'Follow up'),
    ('order_placed', 'Agreed to go ahead'),
    ('not_available', 'Not available'),
  ];

  final _notes = TextEditingController();
  final _duration = TextEditingController();
  String _outcome = 'interested';
  XFile? _photo;
  double? _lat;
  double? _lng;
  String? _place;
  String _locationLine = 'Fetching your location...';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  @override
  void dispose() {
    _notes.dispose();
    _duration.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    setState(() {
      _locationLine = 'Fetching your location...';
      _place = null;
    });
    try {
      final pos = await LocationService.current();
      if (!mounted) return;
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _locationLine =
            '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
      });
    // The place name follows on its own; saving never waits for it (#91).
    final place = await placeName(pos.latitude, pos.longitude);
    if (mounted && _lat == pos.latitude && _lng == pos.longitude) {
      setState(() => _place = place);
    }
    } catch (e) {
      if (mounted) setState(() => _locationLine = '$e');
    }
  }

  Future<void> _takePhoto() async {
    try {
      final shot = await ImagePicker().pickImage(
          source: ImageSource.camera,
          maxWidth: kPhotoMaxSide,
          maxHeight: kPhotoMaxSide,
          imageQuality: kCameraQuality);
      if (shot != null && mounted) setState(() => _photo = shot);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not open the camera: $e');
    }
  }

  Future<void> _save() async {
    if (_lat == null || _lng == null) {
      setState(() => _error = 'Location is needed to log a visit.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final photo =
          _photo == null ? null : await photoForUpload(_photo!, 'visit');
      final result = await Api.instance.postMultipart(
        '/api/visits/',
        fields: {
          if (widget.leadId != null) 'lead': '${widget.leadId}',
          if (widget.customerId != null) 'customer': '${widget.customerId}',
          'lat': _lat!.toStringAsFixed(6),
          'lng': _lng!.toStringAsFixed(6),
          'place': ?_place,
          'outcome': _outcome,
          'notes': _notes.text.trim(),
          if (_duration.text.trim().isNotEmpty)
            'duration_minutes': _duration.text.trim(),
        },
        fileField: 'photo',
        fileBytes: photo?.bytes,
        fileName: photo?.name ?? 'visit.jpg',
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
      title: widget.targetName.isEmpty
          ? 'Log visit'
          : 'Visit · ${widget.targetName}',
      saveLabel: 'Save visit',
      saving: _saving,
      error: _error,
      onSave: _save,
      children: [
        ChoiceRow<String>(
          label: 'Outcome',
          options: _outcomes,
          value: _outcome,
          onChanged: (v) => setState(() => _outcome = v),
        ),
        const SizedBox(height: 20),
        LabeledField(
          label: 'Duration (minutes)',
          controller: _duration,
          hint: '30',
          icon: Icons.timer_outlined,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 20),
        const FieldLabel('Location'),
        InkWell(
          onTap: _locate,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          child: InputDecorator(
            decoration: InputDecoration(
              prefixIcon: Icon(
                _lat == null ? Icons.location_searching : Icons.my_location,
                size: 20,
                color: _lat == null ? scheme.onSurfaceVariant : scheme.primary,
              ),
              suffixIcon: const Icon(Icons.refresh, size: 18),
            ),
            child: _place == null
                ? Text(_locationLine,
                    style: TextStyle(fontSize: 13, color: scheme.onSurface))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_place!,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface)),
                      const SizedBox(height: 2),
                      Text(_locationLine,
                          style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant)),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 20),
        const FieldLabel('Photo'),
        if (_photo == null)
          OutlinedButton.icon(
            onPressed: _takePhoto,
            icon: const Icon(Icons.photo_camera_outlined, size: 20),
            label: const Text('Take a photo'),
          )
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radius),
            child: Stack(
              children: [
                AspectRatio(
                  aspectRatio: 4 / 3,
                  child: kIsWeb
                      ? Image.network(_photo!.path, fit: BoxFit.cover)
                      : Image.file(File(_photo!.path), fit: BoxFit.cover),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton.filled(
                    style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                        foregroundColor: Colors.white),
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _photo = null),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 20),
        LabeledField(
          label: 'Notes',
          controller: _notes,
          hint: 'What was discussed, what they asked for',
          lines: 3,
        ),
      ],
    );
  }
}
