import 'package:avatar_livekit_app/ui/palette.dart';
import 'package:flutter/material.dart';

class ListeningBadge extends StatelessWidget {
  const ListeningBadge({super.key, required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? AppPalette.greenDeep : AppPalette.neutral;
    final text = enabled ? 'Listening...' : 'Mic is off';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(enabled ? Icons.hearing : Icons.hearing_disabled, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
