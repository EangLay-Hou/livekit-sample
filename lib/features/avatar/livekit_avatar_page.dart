import 'package:avatar_livekit_app/features/avatar/models/chat_message.dart';
import 'package:avatar_livekit_app/features/avatar/state/avatar_chat_controller.dart';
import 'package:avatar_livekit_app/features/avatar/state/avatar_chat_state.dart';
import 'package:avatar_livekit_app/features/avatar/widgets/chat_input_row.dart';
import 'package:avatar_livekit_app/features/avatar/widgets/message_layer.dart';
import 'package:avatar_livekit_app/features/avatar/widgets/status_overlay.dart';
import 'package:avatar_livekit_app/features/avatar/widgets/video_layer.dart';
import 'package:avatar_livekit_app/ui/palette.dart';
import 'package:avatar_livekit_app/ui/widgets/widgets.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart' show LocalVideoTrack, VideoTrack, VideoTrackRenderer, VideoViewFit;

class AvatarChatPage extends ConsumerStatefulWidget {
  const AvatarChatPage({super.key, this.autoConnect = true});

  final bool autoConnect;

  @override
  ConsumerState<AvatarChatPage> createState() => _AvatarChatPageState();
}

class _AvatarChatPageState extends ConsumerState<AvatarChatPage> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  late final ProviderSubscription<AvatarChatState> _messageSubscription;
  double _previewDx = 0;
  double _previewDy = 0;
  bool _previewInitialized = false;

  @override
  void initState() {
    super.initState();
    ref.read(avatarChatControllerProvider.notifier).initialize(autoConnect: widget.autoConnect);
    _messageSubscription = ref.listenManual<AvatarChatState>(avatarChatControllerProvider, (previous, next) {
      final prevLength = previous?.messages.length ?? 0;
      final nextLength = next.messages.length;
      if (nextLength > prevLength) {
        for (var i = prevLength; i < nextLength; i++) {
          _listKey.currentState?.insertItem(i, duration: const Duration(milliseconds: 180));
        }
        _scrollToBottom(force: true);
        return;
      }
      if (nextLength == 0 || previous == null) return;
      final prevLast = previous.messages[prevLength - 1];
      final nextLast = next.messages[nextLength - 1];
      final textChanged = prevLast.text != nextLast.text;
      final streamChanged = prevLast.isStreaming != nextLast.isStreaming;
      if (textChanged || streamChanged) {
        _scrollToBottom();
      }
    }, fireImmediately: false);
  }

  @override
  void dispose() {
    _messageSubscription.close();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      if (!force) {
        final distance = _scroll.position.maxScrollExtent - _scroll.position.pixels;
        if (distance > 80) return;
      }
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Widget _buildMessageItem(ChatMessage msg, Animation<double> animation) {
    return SizeTransition(
      sizeFactor: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: Align(
        alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          key: ValueKey('${msg.isUser}-${msg.text}-${msg.streamId ?? ''}'),
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: msg.isUser ? AppPalette.greenDeep.withValues(alpha: 0.14) : AppPalette.mint.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: msg.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (msg.label != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    msg.label!,
                    style: TextStyle(fontSize: 12, color: AppPalette.greenDeep, fontWeight: FontWeight.w600),
                  ),
                ),
              AnimatedSize(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                alignment: Alignment.centerLeft,
                child: msg.isStreaming && !msg.isUser
                    ? Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: msg.text),
                            WidgetSpan(
                              alignment: PlaceholderAlignment.baseline,
                              baseline: TextBaseline.alphabetic,
                              child: AnimatedDots(
                                maxDots: 3,
                                period: const Duration(milliseconds: 240),
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                          ],
                          style: const TextStyle(fontSize: 16),
                        ),
                        softWrap: true,
                      )
                    : Text(msg.text, style: const TextStyle(fontSize: 16), softWrap: true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocalPreview({required BoxConstraints constraints, required VideoTrack track}) {
    const baseHeight = 72.0;
    const portraitHeight = 76.0;
    const margin = 12.0;
    const radius = 8.0;
    const innerPadding = 0.0;
    const borderWidth = 1.5;
    const borderColor = Colors.white;
    const shadowColor = Colors.black;
    const minWidth = 48.0;
    const maxWidth = 120.0;
    const maxPortraitWidth = 104.0;

    double aspect = 4 / 3;
    if (track is LocalVideoTrack) {
      final dims = track.currentOptions.params.dimensions;
      if (dims.width > 0 && dims.height > 0) {
        aspect = dims.width / dims.height;
      }
    }
    aspect = aspect.clamp(0.5, 2.0);

    final isPortraitScreen = constraints.maxHeight > constraints.maxWidth;
    final effectiveAspect = (isPortraitScreen && aspect > 1.1) ? (1 / aspect) : aspect;
    final isPortrait = effectiveAspect < 1.0;
    double previewHeight = isPortrait ? portraitHeight : baseHeight;
    double previewWidth = previewHeight * effectiveAspect;
    if (previewWidth < minWidth) {
      previewWidth = minWidth;
      previewHeight = previewWidth / effectiveAspect;
    } else if (previewWidth > (isPortrait ? maxPortraitWidth : maxWidth)) {
      previewWidth = isPortrait ? maxPortraitWidth : maxWidth;
      previewHeight = previewWidth / effectiveAspect;
    }
    previewWidth += innerPadding * 2;
    previewHeight += innerPadding * 2;

    final maxX = (constraints.maxWidth - previewWidth).clamp(0.0, double.infinity);
    final maxY = (constraints.maxHeight - previewHeight).clamp(0.0, double.infinity);

    final clampedDx = _previewDx.clamp(0.0, maxX).toDouble();
    final clampedDy = _previewDy.clamp(0.0, maxY).toDouble();

    if (!_previewInitialized && maxX > 0 && maxY > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _previewDx = (maxX - margin).clamp(0.0, maxX).toDouble();
          _previewDy = margin;
          _previewInitialized = true;
        });
      });
    } else if (clampedDx != _previewDx || clampedDy != _previewDy) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _previewDx = clampedDx;
          _previewDy = clampedDy;
          _previewInitialized = true;
        });
      });
    }

    return Positioned(
      left: clampedDx,
      top: clampedDy,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) {
          final nextDx = (clampedDx + details.delta.dx).clamp(0.0, maxX).toDouble();
          final nextDy = (clampedDy + details.delta.dy).clamp(0.0, maxY).toDouble();
          setState(() {
            _previewDx = nextDx;
            _previewDy = nextDy;
            _previewInitialized = true;
          });
        },
        child: Container(
          height: previewHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: borderColor.withValues(alpha: 0.7), width: borderWidth),
            boxShadow: [
              BoxShadow(color: shadowColor.withValues(alpha: 0.18), blurRadius: 10, offset: const Offset(0, 6)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: IgnorePointer(
              ignoring: true,
              child: AspectRatio(
                aspectRatio: effectiveAspect,
                child: Padding(
                  padding: const EdgeInsets.all(innerPadding),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(radius - innerPadding),
                    child: VideoTrackRenderer(track, fit: VideoViewFit.contain),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(avatarChatControllerProvider);
    final controller = ref.read(avatarChatControllerProvider.notifier);
    final connected = state.connected;

    return Scaffold(
      backgroundColor: AppPalette.background,
      extendBody: true,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppPalette.heroGradient)),
        title: const Text('Avatar Chat'),
        actions: [
          TextButton(
            onPressed: state.connecting || connected ? null : controller.connect,
            style: TextButton.styleFrom(
              foregroundColor: AppPalette.greenDeep,
              textStyle: const TextStyle(fontWeight: FontWeight.w600),
            ),
            child: const Text('Connect'),
          ),
          IconButton(
            onPressed: connected ? controller.toggleCamera : null,
            icon: state.cameraBusy
                ? const AnimatedDots(
                    maxDots: 2,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppPalette.greenDeep),
                  )
                : Icon(state.cameraEnabled ? Icons.videocam : Icons.videocam_off),
            tooltip: state.cameraEnabled ? 'Stop camera' : 'Start camera',
            color: AppPalette.greenDeep,
          ),
          TextButton(
            onPressed: connected ? controller.disconnect : null,
            style: TextButton.styleFrom(
              foregroundColor: AppPalette.neutralDark,
              textStyle: const TextStyle(fontWeight: FontWeight.w600),
            ),
            child: const Text('Disconnect'),
          ),
        ],
      ),
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(decoration: BoxDecoration(gradient: AppPalette.heroGradient)),
          ),
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusScope.of(context).unfocus(),
            child: SafeArea(
              top: false,
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                child: Column(
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final areaHeight = constraints.maxHeight;
                          final videoHeight = areaHeight / 2;
                          final listHeight = areaHeight / 1.7;
                          return Stack(
                            children: [
                              VideoLayer(
                                height: videoHeight,
                                tracks: state.remoteVideoTracks,
                                localVideoTrack: state.localVideoTrack,
                                previewDx: _previewDx,
                                previewDy: _previewDy,
                                onPreviewPositionChanged: (offset) {
                                  setState(() {
                                    _previewDx = offset.dx;
                                    _previewDy = offset.dy;
                                  });
                                },
                                statusOverlay: StatusOverlay(
                                  status: state.status,
                                  activeRoom: state.activeRoom,
                                  remoteCount: state.remoteParticipantCount,
                                  error: state.error,
                                  connectionPhase: state.connectionPhase,
                                ),
                                showLocalPreview: false,
                              ),
                              MessageLayer(
                                height: listHeight,
                                listKey: _listKey,
                                scrollController: _scroll,
                                messages: state.messages,
                                itemBuilder: _buildMessageItem,
                                chatStatus: state.chatStatus,
                              ),
                              if (state.localVideoTrack != null)
                                _buildLocalPreview(constraints: constraints, track: state.localVideoTrack!),
                            ],
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 30, top: 12),
                      // padding: const EdgeInsets.all(4),
                      child: ChatInputRow(
                        isTextMode: state.chatMode == ChatMode.text,
                        micEnabled: state.micEnabled,
                        micBusy: state.micBusy,
                        sending: state.sending,
                        inputController: _input,
                        onSend: state.sending
                            ? () {}
                            : () {
                                final text = _input.text;
                                if (text.trim().isEmpty) return;
                                _input.clear();
                                controller.sendMessage(text);
                              },
                        onMicToggle: controller.handleMicTap,
                        onHoldStart: controller.holdToTalkStart,
                        onHoldEnd: controller.holdToTalkEnd,
                        holdActive: state.holdToTalkActive,
                        micLatched: state.micLatched,
                        onSubmitted: (_) {
                          final text = _input.text;
                          if (text.trim().isEmpty) return;
                          _input.clear();
                          controller.sendMessage(text);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
