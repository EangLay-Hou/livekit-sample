import 'package:flutter/material.dart';

import 'package:avatar_livekit_app/features/avatar/state/avatar_chat_state.dart';
import 'package:avatar_livekit_app/ui/widgets/widgets.dart';
import 'info_pill.dart';

class StatusOverlay extends StatelessWidget {
  const StatusOverlay({
    super.key,
    required this.status,
    required this.activeRoom,
    required this.remoteCount,
    required this.error,
    required this.connectionPhase,
    this.showCenteredDots = false,
  });

  final String status;
  final String? activeRoom;
  final int remoteCount;
  final String? error;
  final ConnectionPhase connectionPhase;
  final bool showCenteredDots;

  @override
  Widget build(BuildContext context) {
    final statusText = activeRoom == null ? status : '$status • $activeRoom';
    final colorScheme = Theme.of(context).colorScheme;
    final showSpinner = connectionPhase == ConnectionPhase.connecting ||
        connectionPhase == ConnectionPhase.reconnecting ||
        connectionPhase == ConnectionPhase.disconnecting;
    final dotsColor = switch (connectionPhase) {
      ConnectionPhase.reconnecting => colorScheme.primary.withValues(alpha: 0.75),
      ConnectionPhase.disconnecting => colorScheme.onSurface.withValues(alpha: 0.6),
      _ => colorScheme.primary,
    };
    return Stack(
      children: [
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: InfoPill(
                      label: 'Status',
                      value: statusText,
                    ),
                  ),
                  const SizedBox(width: 8),
                  InfoPill(label: 'Remote', value: '$remoteCount'),
                ],
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colorScheme.error.withValues(alpha: 0.25)),
                    ),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (showCenteredDots && showSpinner)
          Positioned.fill(
            child: Center(
              child: AnimatedDots(
                maxDots: 3,
                period: Duration(milliseconds: 240),
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: dotsColor,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
