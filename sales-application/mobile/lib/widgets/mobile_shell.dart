import 'package:flutter/material.dart';

/// The design's mobile-shell-layout: on a phone the app fills the screen; on
/// a wide screen it sits in a centred, rounded phone frame rather than
/// stretching a one-column layout across a monitor.
class MobileShell extends StatelessWidget {
  const MobileShell({super.key, required this.child});

  final Widget child;

  /// Tailwind `max-w-md`.
  static const _maxWidth = 448.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;

    if (width <= _maxWidth + 32) return child;

    return ColoredBox(
      // `bg-muted/40` behind the frame, so the card reads as a device.
      color: theme.brightness == Brightness.dark
          ? theme.scaffoldBackgroundColor
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
              maxWidth: _maxWidth, maxHeight: 860),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 32),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: theme.colorScheme.outlineVariant),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x1F000000),
                    blurRadius: 25,
                    offset: Offset(0, 20)),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
