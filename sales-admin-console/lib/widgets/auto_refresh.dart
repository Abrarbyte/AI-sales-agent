import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';

/// Re-fetches the company data on a timer while the console is open, so a
/// lead a rep just saved on the phone shows up without anyone pressing F5.
///
/// Screens keep their old data on screen while the reload is in flight
/// (`AsyncGate` skips the loading state on a reload), so the refresh is
/// invisible except for the numbers changing.
class AutoRefresh extends ConsumerStatefulWidget {
  const AutoRefresh({
    super.key,
    required this.child,
    this.every = const Duration(seconds: 60),
  });

  final Widget child;
  final Duration every;

  @override
  ConsumerState<AutoRefresh> createState() => _AutoRefreshState();
}

class _AutoRefreshState extends ConsumerState<AutoRefresh> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.every, (_) => refreshAll(ref));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Everything the screens read from the API, in one call. Used by the timer
/// above and by the refresh button in the header.
void refreshAll(WidgetRef ref) {
  ref.invalidate(companyProvider);
  ref.invalidate(pipelineProvider);
  ref.invalidate(kpiProvider);
}

/// The header's manual refresh: spins while a reload is in flight.
class RefreshButton extends ConsumerWidget {
  const RefreshButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool loading = ref.watch(companyProvider).isLoading;
    return IconButton(
      tooltip: 'Refresh now',
      onPressed: loading ? null : () => refreshAll(ref),
      icon: loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh, size: 18),
    );
  }
}
