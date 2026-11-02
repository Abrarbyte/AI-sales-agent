import 'package:flutter/material.dart';

import '../api.dart';
import '../location.dart';
import '../place_name.dart';
import '../theme.dart';
import '../widgets/form_sheet.dart';

/// Start the day, or end it.
///
/// Check-in asks where the day is worked from - office or field - because
/// the answer is settled once and never edited; check-out only needs where
/// the person is. Both send the phone's position, so the console can show
/// where the day began and ended.
class AttendanceSheet extends StatefulWidget {
  const AttendanceSheet({super.key, required this.checkingIn});

  /// True for check-in, false for check-out.
  final bool checkingIn;

  @override
  State<AttendanceSheet> createState() => _AttendanceSheetState();
}

class _AttendanceSheetState extends State<AttendanceSheet> {
  final _note = TextEditingController();
  String _kind = 'field';
  bool _saving = false;
  String? _error;
  String _locationLine = 'Fetching your location...';
  double? _lat;
  double? _lng;
  String? _place;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  @override
  void dispose() {
    _note.dispose();
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
            '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}'
            '  ·  ±${pos.accuracy.round()} m';
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

  Future<void> _save() async {
    if (_lat == null || _lng == null) {
      setState(() => _error = 'Location is needed. Tap the location line to retry.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await Api.instance.post(
        widget.checkingIn
            ? '/api/attendance/check-in/'
            : '/api/attendance/check-out/',
        {
          'lat': _lat!.toStringAsFixed(6),
          'lng': _lng!.toStringAsFixed(6),
          'place': ?_place,
          if (widget.checkingIn) 'kind': _kind,
          'note': _note.text.trim(),
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(result ?? true);
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
      title: widget.checkingIn ? 'Check in for the day' : 'Check out',
      saveLabel: widget.checkingIn ? 'Check in' : 'Check out',
      saving: _saving,
      error: _error,
      onSave: _save,
      children: [
        if (widget.checkingIn) ...[
          ChoiceRow<String>(
            label: 'Working from',
            options: const [('field', 'In the field'), ('office', 'Office')],
            value: _kind,
            onChanged: (v) => setState(() => _kind = v),
          ),
          const SizedBox(height: 20),
        ],
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
                    style: TextStyle(fontSize: 13, color: _lat == null
                            ? scheme.onSurfaceVariant
                            : scheme.onSurface))
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
        LabeledField(
          label: 'Note',
          controller: _note,
          hint: widget.checkingIn
              ? 'Plan for the day (optional)'
              : 'How the day went (optional)',
          lines: 2,
        ),
      ],
    );
  }
}
