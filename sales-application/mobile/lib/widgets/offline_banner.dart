import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../theme.dart';

/// A thin amber strip that appears while the screen is showing cached data
/// because the server could not be reached, and disappears on the next
/// successful request. Wrap a screen body with [OfflineAware] to get it.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Api.instance.offline,
      builder: (context, offline, _) {
        if (!offline) return const SizedBox.shrink();
        final at = Api.instance.cachedAt;
        final when = at == null
            ? ''
            : ' · saved ${DateFormat('d MMM, h:mm a').format(at)}';
        return Material(
          color: Tw.amber100,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off_rounded,
                      size: 16, color: Tw.amber700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Offline - showing last saved data$when',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Tw.amber700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class OfflineAware extends StatelessWidget {
  const OfflineAware({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const OfflineBanner(),
        Expanded(child: child),
      ],
    );
  }
}
