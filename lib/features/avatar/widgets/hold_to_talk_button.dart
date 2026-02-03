import 'package:flutter/material.dart';

import 'package:avatar_livekit_app/ui/widgets/widgets.dart';

class HoldToTalkButton extends StatelessWidget {
  const HoldToTalkButton({
    super.key,
    required this.hasText,
    required this.isHolding,
    required this.isLatched,
    required this.isLoading,
    required this.onSend,
    required this.onMicTap,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  final bool hasText;
  final bool isHolding;
  final bool isLatched;
  final bool isLoading;
  final VoidCallback onSend;
  final VoidCallback onMicTap;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final active = isHolding || isLatched;
    final showSend = hasText;
    final tapEnabled = !isLoading;
    return GestureDetector(
      onTap: !tapEnabled
          ? null
          : showSend
              ? onSend
              : onMicTap,
      onLongPressStart: showSend || !tapEnabled ? null : (_) => onHoldStart(),
      onLongPressEnd: showSend || !tapEnabled ? null : (_) => onHoldEnd(),
      onLongPressCancel: showSend || !tapEnabled ? null : () => onHoldEnd(),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        scale: isHolding ? 1.06 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color:
                active ? colorScheme.primary.withValues(alpha: 0.18) : colorScheme.surface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colorScheme.primary.withValues(alpha: active ? 0.6 : 0.35)),
          ),
          child: Center(
            child: isLoading
                ? AnimatedDots(
                    maxDots: 3,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: colorScheme.primary),
                  )
                : Icon(
                    showSend ? Icons.send : (isHolding || isLatched ? Icons.mic : Icons.mic_none),
                    color: colorScheme.primary.withValues(alpha: active || showSend ? 1 : 0.9),
                  ),
          ),
        ),
      ),
    );
  }
}
