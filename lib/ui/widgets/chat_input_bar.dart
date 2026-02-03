import 'package:flutter/material.dart';

import 'listening_badge.dart';

/// Chat input bar with dynamic mic / send affordances.
class ChatInputBar extends StatelessWidget {
  const ChatInputBar({
    super.key,
    required this.onMicToggle,
    required this.micOn,
    required this.controller,
    this.onSubmitted,
  });

  final VoidCallback onMicToggle;
  final bool micOn;
  final TextEditingController controller;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    const double barHeight = 52;
    final colorScheme = Theme.of(context).colorScheme;
    final surfaceColor = colorScheme.surface.withValues(alpha: 0.85);
    final borderColor = colorScheme.primary.withValues(alpha: 0.35);
    if (micOn) {
      return SizedBox(
        height: barHeight,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              const ListeningBadge(enabled: true),
              const Spacer(),
              IconButton(
                onPressed: onMicToggle,
                icon: Icon(Icons.stop_circle, color: colorScheme.primary),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: barHeight,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                style: TextStyle(color: colorScheme.onSurface),
                cursorColor: colorScheme.primary,
                onSubmitted: onSubmitted,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Text message',
                  hintStyle: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.6)),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
