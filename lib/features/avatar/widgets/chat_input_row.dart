import 'package:avatar_livekit_app/ui/widgets/widgets.dart';
import 'package:flutter/material.dart';

import 'hold_to_talk_button.dart';

class ChatInputRow extends StatelessWidget {
  const ChatInputRow({
    super.key,
    required this.isTextMode,
    required this.micEnabled,
    required this.micBusy,
    required this.sending,
    required this.inputController,
    required this.onSend,
    required this.onMicToggle,
    required this.onHoldStart,
    required this.onHoldEnd,
    required this.holdActive,
    required this.micLatched,
    required this.onSubmitted,
  });

  final bool isTextMode;
  final bool micEnabled;
  final bool micBusy;
  final bool sending;
  final TextEditingController inputController;
  final VoidCallback onSend;
  final VoidCallback onMicToggle;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;
  final bool holdActive;
  final bool micLatched;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    if (!isTextMode) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ListeningBadge(enabled: micEnabled),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: !micBusy ? onMicToggle : null,
            icon: Icon(micEnabled ? Icons.mic : Icons.mic_off),
            label: micBusy
                ? const AnimatedDots(maxDots: 3, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))
                : Text(micEnabled ? 'Stop Mic' : 'Start Mic'),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: ChatInputBar(
            controller: inputController,
            micOn: micEnabled,
            onMicToggle: onMicToggle,
            onSubmitted: onSubmitted,
          ),
        ),
        const SizedBox(width: 10),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: inputController,
          builder: (context, value, _) {
            final hasText = value.text.trim().isNotEmpty;
            final loading = hasText ? sending : micBusy;
            return HoldToTalkButton(
              hasText: hasText,
              isHolding: holdActive,
              isLatched: micLatched,
              isLoading: loading,
              onSend: onSend,
              onMicTap: onMicToggle,
              onHoldStart: onHoldStart,
              onHoldEnd: onHoldEnd,
            );
          },
        ),
      ],
    );
  }
}
