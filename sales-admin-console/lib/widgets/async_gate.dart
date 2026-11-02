import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_palette.dart';
import '../core/theme/app_theme.dart';
import '../features/dashboard/dashboard_panels.dart';
import '../data/api/api_client.dart';
import '../features/auth/auth_state.dart';

/// Renders [data] once loaded, and something sensible before then.
///
/// Every screen reads through a provider now, so each one needs the same three
/// states. Putting them here keeps a loading spinner from being spelled a
/// slightly different way on eight screens - and makes sure an auth failure is
/// never shown as a generic error, since "log in again" and "something broke"
/// need different responses from the admin.
class AsyncGate<T> extends StatelessWidget {
  const AsyncGate({
    super.key,
    required this.value,
    required this.data,
    this.onRetry,
    this.loadingHeight = 240,
  });

  final AsyncValue<T> value;
  final Widget Function(T value) data;
  final VoidCallback? onRetry;
  final double loadingHeight;

  @override
  Widget build(BuildContext context) {
    return value.when(
      // A reload after a filter change keeps the previous page on screen
      // and lets the figures roll to their new values, rather than dropping
      // to a spinner and back.
      skipLoadingOnReload: true,
      data: data,
      loading: () => SizedBox(
        height: loadingHeight,
        child: const Center(child: CircularProgressIndicator()),
      ),
      error: (Object error, StackTrace _) =>
          _ErrorPanel(error: error, onRetry: onRetry),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    final (String title, String detail) = switch (error) {
      final ApiException e when e.isAuthFailure => (
        'Session expired',
        'Sign in again to continue.',
      ),
      final ApiException e when e.isForbidden => (
        'Not permitted',
        'This console needs an Admin or Super Admin account. $e',
      ),
      final ApiException e => ('Request failed', e.message),
      _ => (
        'Cannot reach the server',
        'Check that the backend is running and that API_BASE points at it.\n'
            '$error',
      ),
    };

    return Panel(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.error_outline,
                  size: 20,
                  color: VizPalette.statusCritical,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(title, style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              detail,
              style: theme.textTheme.bodySmall?.copyWith(
                color: VizPalette.inkMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child:
                  (error is ApiException &&
                      (error as ApiException).isAuthFailure)
                  ? TextButton.icon(
                      onPressed: signOut,
                      icon: const Icon(Icons.login, size: 16),
                      label: const Text('Sign in'),
                    )
                  : onRetry == null
                  ? const SizedBox.shrink()
                  : TextButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Try again'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An empty-state row for a table or panel that loaded fine but has no rows.
class EmptyNote extends StatelessWidget {
  const EmptyNote(this.message, {super.key, this.height = 120});

  final String message;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: VizPalette.inkMuted),
        ),
      ),
    );
  }
}
