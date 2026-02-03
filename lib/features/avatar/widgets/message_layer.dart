import 'dart:ui';

import 'package:avatar_livekit_app/features/avatar/models/chat_message.dart';
import 'package:flutter/material.dart';

import 'info_pill.dart';

class MessageLayer extends StatelessWidget {
  const MessageLayer({
    super.key,
    required this.height,
    required this.listKey,
    required this.scrollController,
    required this.messages,
    required this.itemBuilder,
    required this.chatStatus,
  });

  final double height;
  final GlobalKey<AnimatedListState> listKey;
  final ScrollController scrollController;
  final List<ChatMessage> messages;
  final Widget Function(ChatMessage, Animation<double>) itemBuilder;
  final String chatStatus;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: height,
      child: Stack(
        children: [
          ClipRRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: ShaderMask(
                shaderCallback: (rect) {
                  return const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black, Colors.black],
                    stops: [0.0, 0.06, 1.0],
                  ).createShader(rect);
                },
                blendMode: BlendMode.dstIn,
                child: AnimatedList(
                  key: listKey,
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(12, 24, 12, 90),
                  initialItemCount: messages.length,
                  itemBuilder: (context, index, animation) => itemBuilder(messages[index], animation),
                ),
              ),
            ),
          ),
          Positioned(
            left: 12,
            bottom: 12,
            child: InfoPill(label: 'Chat', value: chatStatus),
          ),
        ],
      ),
    );
  }
}
