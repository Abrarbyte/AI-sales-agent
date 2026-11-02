import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';

import '../theme.dart';
import '../updates.dart';

/// The strip at the top of Home when a newer build is on the server (#94).
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key, required this.release, required this.onLater});

  final AppRelease release;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.system_update, color: scheme.onPrimaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Update available: ${release.version}',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: scheme.onPrimaryContainer)),
              ),
            ],
          ),
          if (release.notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 8),
              child: Text(release.notes,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13, color: scheme.onPrimaryContainer)),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: onLater, child: const Text('Later')),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: () => showUpdateSheet(context, release),
                child: const Text('Update'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shown instead of Home when this build is below the release's minimum:
/// an important fix that cannot wait.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key, required this.release});

  final AppRelease release;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.system_update, size: 56, color: scheme.primary),
              const SizedBox(height: 20),
              Text('Please update SalesHub',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface)),
              const SizedBox(height: 8),
              Text(
                  'Version ${release.version} fixes something important. '
                  'Update to carry on - your data stays as it is.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              if (release.notes.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(release.notes,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurface)),
              ],
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: () => showUpdateSheet(context, release),
                icon: const Icon(Icons.download),
                label: const Text('Update'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showUpdateSheet(BuildContext context, AppRelease release) =>
    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => _UpdateSheet(release: release),
    );

/// Download progress, then Android's own Install prompt takes over.
class _UpdateSheet extends StatefulWidget {
  const _UpdateSheet({required this.release});

  final AppRelease release;

  @override
  State<_UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<_UpdateSheet> {
  StreamSubscription<OtaEvent>? _sub;
  double? _progress;
  String _status = 'Starting download...';
  String? _error;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    setState(() {
      _error = null;
      _progress = null;
      _status = 'Starting download...';
    });
    try {
      _sub = Updates.install(widget.release).listen(_onEvent,
          onError: (Object e) => _fail('$e'));
    } catch (e) {
      _fail('$e');
    }
  }

  void _onEvent(OtaEvent event) {
    if (!mounted) return;
    switch (event.status) {
      case OtaStatus.DOWNLOADING:
        final percent = double.tryParse(event.value ?? '');
        setState(() {
          _progress = percent == null ? null : percent / 100;
          _status = percent == null
              ? 'Downloading...'
              : 'Downloading... ${percent.round()}%';
        });
      case OtaStatus.INSTALLING:
      case OtaStatus.INSTALLATION_DONE:
        setState(() {
          _done = true;
          _progress = 1;
          _status = 'Tap Install on the next screen.';
        });
      case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
        _fail('Allow SalesHub to install apps (Android asks the first time), '
            'then try again.');
      case OtaStatus.ALREADY_RUNNING_ERROR:
        setState(() => _status = 'Already downloading...');
      default:
        _fail('The download did not finish. Check your connection and try '
            'again.');
    }
  }

  void _fail(String message) {
    if (mounted) setState(() => _error = message);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Updating to ${widget.release.version}',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface)),
            const SizedBox(height: 16),
            if (_error == null) ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 10),
              Text(_status, style: TextStyle(color: scheme.onSurfaceVariant)),
            ] else
              Text(_error!, style: TextStyle(color: scheme.error)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(_done || _error != null ? 'Close' : 'Cancel'),
                ),
                if (_error != null) ...[
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _start, child: const Text('Try again')),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
