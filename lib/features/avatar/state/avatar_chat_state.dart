import 'package:avatar_livekit_app/features/avatar/models/chat_message.dart';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' show VideoTrack;

enum ChatMode { text, voice }

enum ConnectionPhase { disconnected, connecting, connected, reconnecting, disconnecting, error }

@immutable
class AvatarChatState {
  const AvatarChatState({
    this.status = 'Disconnected',
    this.chatStatus = 'Ready',
    this.error,
    this.connecting = false,
    this.connected = false,
    this.connectionPhase = ConnectionPhase.disconnected,
    this.sending = false,
    this.activeRoom,
    this.chatMode = ChatMode.text,
    this.micEnabled = false,
    this.cameraEnabled = false,
    this.micBusy = false,
    this.cameraBusy = false,
    this.holdToTalkActive = false,
    this.micLatched = false,
    this.localSpeaking = false,
    this.remoteAudioPaused = false,
    this.remoteParticipantCount = 0,
    this.remoteVideoTracks = const <VideoTrack>[],
    this.localVideoTrack,
    this.messages = const <ChatMessage>[],
  });

  final String status;
  final String chatStatus;
  final String? error;
  final bool connecting;
  final bool connected;
  final ConnectionPhase connectionPhase;
  final bool sending;
  final String? activeRoom;
  final ChatMode chatMode;
  final bool micEnabled;
  final bool cameraEnabled;
  final bool micBusy;
  final bool cameraBusy;
  final bool holdToTalkActive;
  final bool micLatched;
  final bool localSpeaking;
  final bool remoteAudioPaused;
  final int remoteParticipantCount;
  final List<VideoTrack> remoteVideoTracks;
  final VideoTrack? localVideoTrack;
  final List<ChatMessage> messages;

  AvatarChatState copyWith({
    String? status,
    String? chatStatus,
    String? error,
    bool clearError = false,
    bool? connecting,
    bool? connected,
    ConnectionPhase? connectionPhase,
    bool? sending,
    String? activeRoom,
    bool clearActiveRoom = false,
    ChatMode? chatMode,
    bool? micEnabled,
    bool? cameraEnabled,
    bool? micBusy,
    bool? cameraBusy,
    bool? holdToTalkActive,
    bool? micLatched,
    bool? localSpeaking,
    bool? remoteAudioPaused,
    int? remoteParticipantCount,
    List<VideoTrack>? remoteVideoTracks,
    VideoTrack? localVideoTrack,
    bool clearLocalVideoTrack = false,
    List<ChatMessage>? messages,
  }) {
    return AvatarChatState(
      status: status ?? this.status,
      chatStatus: chatStatus ?? this.chatStatus,
      error: clearError ? null : (error ?? this.error),
      connecting: connecting ?? this.connecting,
      connected: connected ?? this.connected,
      connectionPhase: connectionPhase ?? this.connectionPhase,
      sending: sending ?? this.sending,
      activeRoom: clearActiveRoom ? null : (activeRoom ?? this.activeRoom),
      chatMode: chatMode ?? this.chatMode,
      micEnabled: micEnabled ?? this.micEnabled,
      cameraEnabled: cameraEnabled ?? this.cameraEnabled,
      micBusy: micBusy ?? this.micBusy,
      cameraBusy: cameraBusy ?? this.cameraBusy,
      holdToTalkActive: holdToTalkActive ?? this.holdToTalkActive,
      micLatched: micLatched ?? this.micLatched,
      localSpeaking: localSpeaking ?? this.localSpeaking,
      remoteAudioPaused: remoteAudioPaused ?? this.remoteAudioPaused,
      remoteParticipantCount: remoteParticipantCount ?? this.remoteParticipantCount,
      remoteVideoTracks: remoteVideoTracks ?? this.remoteVideoTracks,
      localVideoTrack: clearLocalVideoTrack ? null : (localVideoTrack ?? this.localVideoTrack),
      messages: messages ?? this.messages,
    );
  }
}
