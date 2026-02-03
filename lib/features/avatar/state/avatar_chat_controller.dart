import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart' hide ChatMessage;
import 'package:permission_handler/permission_handler.dart';

import 'package:avatar_livekit_app/core/app_config.dart';
import 'package:avatar_livekit_app/core/livekit_token_api.dart';
import 'package:avatar_livekit_app/features/avatar/avatar_room_controller.dart';
import 'package:avatar_livekit_app/features/avatar/models/chat_message.dart';
import 'avatar_chat_state.dart';

final avatarChatControllerProvider =
    StateNotifierProvider<AvatarChatController, AvatarChatState>(
  (ref) {
    final controller = AvatarChatController();
    ref.onDispose(controller.disposeController);
    return controller;
  },
);

class AvatarChatController extends StateNotifier<AvatarChatState> {
  AvatarChatController() : super(const AvatarChatState());

  final LiveKitTokenApi _tokenApi = LiveKitTokenApi();
  late AvatarRoomController _roomController;

  Room get room => _roomController.room;

  String _identity = '';
  String? _currentRoomName;
  final Map<String, int> _transcriptIndexById = <String, int>{};

  LocalAudioTrack? _micTrack;
  LocalTrackPublication<LocalAudioTrack>? _micPub;
  EventsListener<TrackEvent>? _micTrackListener;
  bool _micHasSignal = false;
  bool _micSpeaking = false;
  int _lastVoiceLogMs = 0;
  int _lastVoiceAboveMs = 0;

  LocalVideoTrack? _cameraTrack;
  LocalTrackPublication<LocalVideoTrack>? _cameraPub;

  bool _audioInputReady = false;
  bool _needsRoomReset = false;
  bool _resettingRoom = false;
  Timer? _resumeAudioTimer;
  bool _holdStartedMic = false;

  void initialize({required bool autoConnect}) {
    _initRoom();
    if (autoConnect) {
      unawaited(connect());
    }
    if (lkPlatformIs(PlatformType.android)) {
      unawaited(Hardware.instance.setSpeakerphoneOn(true));
    }
  }

  void disposeController() {
    _micTrackListener?.dispose();
    unawaited(_unpublishMic(reason: 'dispose'));
    _resumeAudioTimer?.cancel();
    unawaited(_disposeRoom());
  }

  void _initRoom() {
    _roomController = AvatarRoomController();
    _roomController.init();
    final listener = _roomController.listener;
    if (listener != null) {
      _wireRoomEvents(listener);
    }
    _registerTextHandler();
    _log('Room initialized');
  }

  Future<void> _disposeRoom() async {
    await _roomController.dispose();
  }

  // Recreate the LiveKit Room and clear all local track state after failures.
  Future<void> _resetRoom({required String reason}) async {
    _log('Resetting room ($reason)');
    _resettingRoom = true;
    try {
      await _disposeRoom();
      _micTrackListener?.dispose();
      _micTrackListener = null;
      _micTrack = null;
      _micPub = null;
      _micHasSignal = false;
      _cameraTrack = null;
      _cameraPub = null;
      _audioInputReady = false;
      _currentRoomName = null;
      _needsRoomReset = false;
      _holdStartedMic = false;
      _initRoom();
      if (!mounted) return;
      state = state.copyWith(
        status: 'Disconnected',
        connecting: false,
        connected: false,
        connectionPhase: ConnectionPhase.disconnected,
        micEnabled: false,
        holdToTalkActive: false,
        micLatched: false,
        cameraEnabled: false,
        chatStatus: state.chatMode == ChatMode.voice ? 'Mic off' : 'Ready',
        clearActiveRoom: true,
      );
    } finally {
      _resettingRoom = false;
    }
  }

  void _appendMessage(ChatMessage message) {
    state = state.copyWith(messages: <ChatMessage>[...state.messages, message]);
  }

  void _replaceMessageAt(int index, ChatMessage message) {
    final next = [...state.messages];
    next[index] = message;
    state = state.copyWith(messages: next);
  }

  void _registerTextHandler() {
    try {
      room.registerTextStreamHandler(AppConfig.liveKitChatTopic, (reader, identity) async {
        final text = await reader.readAll();
        _log('Text stream received from $identity');
        if (!mounted) return;
        _appendMessage(ChatMessage(isUser: false, text: text, label: identity));
      });
    } catch (e) {
      _log('Text handler error: $e');
    }
  }

  // Centralized wiring for all room-level events to keep init concise.
  void _wireRoomEvents(EventsListener<RoomEvent> listener) {
    listener.on<RoomConnectedEvent>(_onRoomConnected);
    listener.on<RoomDisconnectedEvent>(_onRoomDisconnected);
    listener.on<RoomReconnectingEvent>(_onRoomReconnecting);
    listener.on<RoomReconnectedEvent>(_onRoomReconnected);
    listener.on<TranscriptionEvent>(_onTranscriptionEvent);
    listener.on<LocalTrackPublishedEvent>(_onLocalTrackPublished);
    listener.on<LocalTrackUnpublishedEvent>(_onLocalTrackUnpublished);
    listener.on<TrackMutedEvent>(_onTrackMuted);
    listener.on<TrackUnmutedEvent>(_onTrackUnmuted);
    listener.on<TrackSubscribedEvent>(_onTrackSubscribed);
    listener.on<TrackUnsubscribedEvent>(_onTrackUnsubscribed);
    listener.on<TrackSubscriptionExceptionEvent>(_onTrackSubscriptionError);
    listener.on<AudioPlaybackStatusChanged>(_onAudioPlaybackStatusChanged);
    listener.on<DataReceivedEvent>(_onDataReceived);
    listener.on<ActiveSpeakersChangedEvent>(_onActiveSpeakersChanged);
    listener.on<ParticipantConnectedEvent>(_onParticipantConnected);
    listener.on<ParticipantDisconnectedEvent>(_onParticipantDisconnected);
  }

  void _log(String message) {
    debugPrint('[AvatarChat] $message');
  }

  void _showConnectFirstError(String context) {
    state = state.copyWith(
      error: 'Connect to LiveKit first',
      chatStatus: 'Not connected',
    );
    _log('$context blocked: not connected');
  }

  // Hold-to-talk enables the mic only while the press is active.
  void holdToTalkStart() {
    if (room.connectionState != ConnectionState.connected) {
      _showConnectFirstError('hold-to-talk');
      return;
    }
    if (state.micBusy) return;
    state = state.copyWith(holdToTalkActive: true);
    _holdStartedMic = false;
    if (!state.micEnabled) {
      _holdStartedMic = true;
      unawaited(
        _startMic().then((_) {
          if (!state.holdToTalkActive && _holdStartedMic && state.micEnabled) {
            unawaited(_muteMic(reason: 'hold-to-talk release'));
          }
        }),
      );
    }
  }

  // Stop hold-to-talk and restore mic to prior state.
  void holdToTalkEnd() {
    if (!state.holdToTalkActive) return;
    state = state.copyWith(holdToTalkActive: false);
    if (_holdStartedMic && state.micEnabled) {
      unawaited(_muteMic(reason: 'hold-to-talk release'));
    }
    _holdStartedMic = false;
  }

  void _logRoomState(String where) {
    final localId = room.localParticipant?.identity ?? 'null';
    final remoteIds = room.remoteParticipants.keys.toList();
    final audioPubs = room.localParticipant?.audioTrackPublications.length ?? 0;
    final videoPubs = room.localParticipant?.videoTrackPublications.length ?? 0;
    _log(
      '$where: conn=${room.connectionState} local=$localId room=${_currentRoomName ?? 'unset'} remotes=${remoteIds.length} $remoteIds '
      'pubs audio=$audioPubs video=$videoPubs',
    );
  }

  Future<void> _ensureAudioInputSelected() async {
    try {
      final devices = await Hardware.instance.enumerateDevices();
      final inputs = devices.where((d) => d.kind == 'audioinput').toList();
      if (inputs.isEmpty) {
        _log('No audio input devices found');
        return;
      }
      final labels = inputs.map((d) => d.label.isNotEmpty ? d.label : d.deviceId).join(', ');
      _log('Audio inputs: $labels');
      if (!_audioInputReady) {
        final selected = Hardware.instance.selectedAudioInput ?? inputs.first;
        await room.setAudioInputDevice(selected);
        _audioInputReady = true;
        final label = selected.label.isNotEmpty ? selected.label : selected.deviceId;
        _log('Audio input set to: $label');
      }
    } catch (e) {
      _log('Audio input selection error: $e');
    }
  }

  void _attachMicTrackListener(LocalAudioTrack track) {
    _micTrackListener?.dispose();
    _micHasSignal = false;
    _micSpeaking = false;
    _lastVoiceLogMs = 0;
    _lastVoiceAboveMs = 0;
    _micTrackListener = track.createListener();
    _micTrackListener?.on<AudioSenderStatsEvent>((event) {
      if (_micHasSignal) return;
      if (event.currentBitrate > 0) {
        _micHasSignal = true;
        _log('Mic is sending audio (bitrate=${event.currentBitrate})');
      }
    });
    _micTrackListener?.on<AudioSenderStatsEvent>((event) {
      final level = event.stats.audioSourceStats?.audioLevel;
      if (level == null) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      const double threshold = 0.02;
      if (level >= threshold) {
        _lastVoiceAboveMs = now;
        if (!_micSpeaking) {
          _micSpeaking = true;
          _log('Voice detected (level=${level.toStringAsFixed(3)})');
        } else if (now - _lastVoiceLogMs > 600) {
          _log('Voice level=${level.toStringAsFixed(3)}');
        }
        _lastVoiceLogMs = now;
      } else if (_micSpeaking && now - _lastVoiceAboveMs > 800) {
        _micSpeaking = false;
        _log('Voice stopped');
      }
    });
  }

  void _restartRemoteAudioTracks(String reason) {
    try {
      for (final participant in room.remoteParticipants.values) {
        for (final pub in participant.audioTrackPublications) {
          final track = pub.track;
          if (track != null) {
            track.start();
          }
        }
      }
      unawaited(room.startAudio());
      _log('Restarted remote audio tracks ($reason)');
    } catch (e) {
      _log('Restart remote audio error: $e');
    }
  }

  void _onRoomConnected(RoomConnectedEvent _) {
    _log('Room connected');
    if (_resettingRoom || !mounted) return;
    state = state.copyWith(
      status: 'Connected',
      connecting: false,
      connected: true,
      connectionPhase: ConnectionPhase.connected,
      clearError: true,
      chatStatus: state.chatMode == ChatMode.voice
          ? (state.micEnabled ? 'Mic on' : 'Tap mic to speak')
          : 'Ready',
      remoteParticipantCount: room.remoteParticipants.length,
    );
    _refreshVideoTracks();
    _logRoomState('after connect');
  }

  void _onRoomDisconnected(RoomDisconnectedEvent _) {
    _log('Room disconnected');
    if (_resettingRoom || !mounted) return;
    _needsRoomReset = true;
    state = state.copyWith(
      status: 'Disconnected',
      connecting: false,
      connected: false,
      connectionPhase: ConnectionPhase.disconnected,
      micEnabled: false,
      micLatched: false,
      holdToTalkActive: false,
      cameraEnabled: false,
      chatStatus: 'Disconnected',
      clearActiveRoom: true,
      remoteParticipantCount: 0,
      remoteVideoTracks: const <VideoTrack>[],
      clearLocalVideoTrack: true,
    );
    _audioInputReady = false;
    _micTrackListener?.dispose();
    _micTrackListener = null;
    _micTrack = null;
    _micPub = null;
    _micHasSignal = false;
    _logRoomState('after disconnect');
  }

  void _onRoomReconnecting(RoomReconnectingEvent _) {
    _log('Room reconnecting');
    if (_resettingRoom || !mounted) return;
    state = state.copyWith(
      status: 'Reconnecting...',
      connected: false,
      connectionPhase: ConnectionPhase.reconnecting,
    );
  }

  void _onRoomReconnected(RoomReconnectedEvent _) {
    _log('Room reconnected');
    if (_resettingRoom || !mounted) return;
    state = state.copyWith(
      status: 'Connected',
      connected: true,
      connectionPhase: ConnectionPhase.connected,
    );
  }

  void _onTranscriptionEvent(TranscriptionEvent event) {
    final segments = event.segments;
    if (segments.isEmpty || !mounted) return;
    final participant = event.participant;
    final isUser = participant is LocalParticipant || participant.identity == _identity;
    final label = isUser ? 'You' : (participant.identity.isNotEmpty ? participant.identity : 'Bot');
    for (final TranscriptionSegment segment in segments) {
      final text = segment.text.trim();
      if (text.isEmpty) continue;
      final displayText = text;
      final existingIndex = _transcriptIndexById[segment.id];
      if (existingIndex != null && existingIndex >= 0 && existingIndex < state.messages.length) {
        _replaceMessageAt(
          existingIndex,
          ChatMessage(
            isUser: isUser,
            text: displayText,
            streamId: segment.id,
            isStreaming: !segment.isFinal,
            label: label,
          ),
        );
      } else {
        _appendMessage(
          ChatMessage(
            isUser: isUser,
            text: displayText,
            streamId: segment.id,
            isStreaming: !segment.isFinal,
            label: label,
          ),
        );
        _transcriptIndexById[segment.id] = state.messages.length - 1;
      }
      if (segment.isFinal) {
        _transcriptIndexById.remove(segment.id);
        _log('Transcription final: $displayText');
      }
    }
  }

  void _onLocalTrackPublished(LocalTrackPublishedEvent event) {
    final source = event.publication.source;
    if (source == TrackSource.microphone) {
      _log('Mic published sid=${event.publication.sid}');
      if (!mounted) return;
      state = state.copyWith(
        micEnabled: true,
        chatStatus: state.chatMode == ChatMode.voice ? 'Mic on' : state.chatStatus,
      );
      return;
    }
    if (source == TrackSource.camera) {
      _log('Camera published sid=${event.publication.sid}');
      if (event.publication.track is LocalVideoTrack) {
        _cameraTrack = event.publication.track as LocalVideoTrack;
        _cameraPub = event.publication as LocalTrackPublication<LocalVideoTrack>;
      }
      if (!mounted) return;
      state = state.copyWith(cameraEnabled: true, localVideoTrack: _cameraTrack);
    }
  }

  void _onLocalTrackUnpublished(LocalTrackUnpublishedEvent event) {
    final source = event.publication.source;
    if (source == TrackSource.microphone) {
      _log('Mic unpublished sid=${event.publication.sid}');
      if (!mounted) return;
      state = state.copyWith(
        micEnabled: false,
        micLatched: false,
        chatStatus: state.chatMode == ChatMode.voice ? 'Mic off' : state.chatStatus,
      );
      return;
    }
    if (source == TrackSource.camera) {
      _log('Camera unpublished sid=${event.publication.sid}');
      _cameraTrack = null;
      _cameraPub = null;
      if (!mounted) return;
      state = state.copyWith(cameraEnabled: false, clearLocalVideoTrack: true);
    }
  }

  void _onTrackMuted(TrackMutedEvent event) {
    if (event.participant is! LocalParticipant) return;
    final source = event.publication.source;
    if (source == TrackSource.microphone) {
      _log('Mic muted');
      if (!mounted) return;
      state = state.copyWith(
        micEnabled: false,
        micLatched: false,
        chatStatus: state.chatMode == ChatMode.voice ? 'Mic off' : state.chatStatus,
      );
      return;
    }
    if (source == TrackSource.camera) {
      _log('Camera muted');
      if (event.publication.track is LocalVideoTrack) {
        _cameraTrack = event.publication.track as LocalVideoTrack;
        _cameraPub = event.publication as LocalTrackPublication<LocalVideoTrack>;
      }
      if (!mounted) return;
      state = state.copyWith(cameraEnabled: false, localVideoTrack: _cameraTrack);
    }
  }

  void _onTrackUnmuted(TrackUnmutedEvent event) {
    if (event.participant is! LocalParticipant) return;
    final source = event.publication.source;
    if (source == TrackSource.microphone) {
      _log('Mic unmuted');
      if (!mounted) return;
      state = state.copyWith(
        micEnabled: true,
        chatStatus: state.chatMode == ChatMode.voice ? 'Mic on' : state.chatStatus,
      );
      return;
    }
    if (source == TrackSource.camera) {
      _log('Camera unmuted');
      if (event.publication.track is LocalVideoTrack) {
        _cameraTrack = event.publication.track as LocalVideoTrack;
        _cameraPub = event.publication as LocalTrackPublication<LocalVideoTrack>;
      }
      if (!mounted) return;
      state = state.copyWith(cameraEnabled: true, localVideoTrack: _cameraTrack);
    }
  }

  void _onTrackSubscribed(TrackSubscribedEvent event) {
    if (event.track is RemoteAudioTrack) {
      final track = event.track as RemoteAudioTrack;
      track.start();
      _log('Remote audio track started');
    }
    _refreshVideoTracks();
  }

  void _onTrackUnsubscribed(TrackUnsubscribedEvent event) {
    _refreshVideoTracks();
  }

  void _onTrackSubscriptionError(TrackSubscriptionExceptionEvent event) {
    _log('Track subscription failed sid=${event.sid} reason=${event.reason}');
  }

  void _onActiveSpeakersChanged(ActiveSpeakersChangedEvent event) {
    final localSid = room.localParticipant?.sid;
    final speakingNow = event.speakers.any((s) => s.sid == localSid);
    if (speakingNow != state.localSpeaking) {
      state = state.copyWith(localSpeaking: speakingNow);
      _log('Active speakers updated: localSpeaking=$speakingNow, count=${event.speakers.length}');
      _handleInterruptBot(speakingNow);
    }
  }

  void _onParticipantConnected(ParticipantConnectedEvent event) {
    _refreshParticipantCounts();
  }

  void _onParticipantDisconnected(ParticipantDisconnectedEvent event) {
    _refreshParticipantCounts();
  }

  void _handleInterruptBot(bool speaking) {
    _resumeAudioTimer?.cancel();
    if (speaking) {
      unawaited(_pauseRemoteAudio());
    } else {
      _resumeAudioTimer = Timer(const Duration(milliseconds: 400), () => unawaited(_resumeRemoteAudio()));
    }
  }

  Future<void> _pauseRemoteAudio() async {
    if (state.remoteAudioPaused) return;
    for (final participant in room.remoteParticipants.values) {
      for (final pub in participant.audioTrackPublications) {
        await pub.unsubscribe();
      }
    }
    state = state.copyWith(remoteAudioPaused: true);
    _log('Remote audio paused while speaking');
  }

  Future<void> _resumeRemoteAudio() async {
    if (!state.remoteAudioPaused) return;
    for (final participant in room.remoteParticipants.values) {
      for (final pub in participant.audioTrackPublications) {
        await pub.subscribe();
      }
    }
    state = state.copyWith(remoteAudioPaused: false);
    _log('Remote audio resumed after speaking');
  }

  void _onAudioPlaybackStatusChanged(AudioPlaybackStatusChanged event) {
    if (!room.canPlaybackAudio) {
      _log('Audio playback requires user action, starting audio');
      unawaited(room.startAudio());
    }
  }

  void _onDataReceived(DataReceivedEvent event) {
    final text = String.fromCharCodes(event.data);
    final from = event.participant?.identity ?? 'remote';
    _log('Data received topic=${event.topic} from=$from len=${event.data.length}');
    _logRoomState('on data received');
    if (!mounted) return;
    _appendMessage(ChatMessage(isUser: false, text: text, label: from));
  }

  bool get _hasTokenEndpoint {
    final endpoint = AppConfig.liveKitTokenEndpoint;
    return endpoint.isNotEmpty && !endpoint.contains('YOUR_CLOUD_FUNCTION_URL');
  }

  Future<LiveKitTokenResult> _resolveCredentials() async {
    _currentRoomName ??= '${AppConfig.liveKitRoomName}_${DateTime.now().millisecondsSinceEpoch}';
    final roomName = _currentRoomName!;
    if (!_hasTokenEndpoint) {
      throw Exception('Set liveKitTokenEndpoint in AppConfig');
    }
    if (roomName.isEmpty || roomName.contains('YOUR_ROOM_NAME')) {
      throw Exception('Set liveKitRoomName in AppConfig');
    }
    _log('Requesting token: endpoint=${AppConfig.liveKitTokenEndpoint} room=$roomName identity=$_identity');
    return _tokenApi.fetchToken(
      endpoint: AppConfig.liveKitTokenEndpoint,
      room: roomName,
      identity: _identity,
    );
  }

  Future<void> connect() async {
    if (state.connecting || room.connectionState == ConnectionState.connected) {
      return;
    }
    if (_needsRoomReset) {
      await _resetRoom(reason: 'reconnect');
    }
    _identity = '${AppConfig.liveKitIdentityPrefix}_${DateTime.now().millisecondsSinceEpoch}';

    _logRoomState('pre-connect');
    state = state.copyWith(
      connecting: true,
      status: 'Connecting...',
      clearError: true,
      connectionPhase: ConnectionPhase.connecting,
    );

    try {
      _log('Connecting to LiveKit...');
      final creds = await _resolveCredentials();
      state = state.copyWith(activeRoom: creds.room);
      _log('Connecting to url=${creds.liveKitUrl} room=${creds.room}');
      await _roomController.connect(url: creds.liveKitUrl, token: creds.token);
    } catch (e) {
      _log('Connect error: $e');
      if (!mounted) return;
      state = state.copyWith(
        status: 'Connect failed',
        connecting: false,
        connected: false,
        connectionPhase: ConnectionPhase.error,
        error: e.toString(),
        clearActiveRoom: true,
      );
    }
  }

  Future<void> disconnect() async {
    if (room.connectionState == ConnectionState.disconnected) return;
    state = state.copyWith(status: 'Disconnecting...', connectionPhase: ConnectionPhase.disconnecting);
    await _unpublishMic(reason: 'disconnect');
    await _stopCamera();
    await _resetRoom(reason: 'disconnect');
  }

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _logRoomState('before send');
    if (room.connectionState != ConnectionState.connected) {
      _showConnectFirstError('send');
      return;
    }

    _appendMessage(ChatMessage(isUser: true, text: trimmed, label: 'You'));
    state = state.copyWith(chatStatus: 'Sending...', sending: true);

    try {
      _log('Sending text: "$trimmed" topic=${AppConfig.liveKitChatTopic}');
      await room.localParticipant?.sendText(trimmed, options: SendTextOptions(topic: AppConfig.liveKitChatTopic));

      if (!mounted) return;
      state = state.copyWith(chatStatus: 'Sent to room', sending: false);
      _logRoomState('after send ok');
    } catch (e) {
      _log('Send text error: $e');
      if (!mounted) return;
      state = state.copyWith(chatStatus: 'Send failed', error: e.toString(), sending: false);
      _logRoomState('after send fail');
    }
  }

  // Toggle mic with guard rails (busy flags, permissions, and room state).
  Future<void> toggleMic() async {
    if (state.micBusy) return;
    state = state.copyWith(micBusy: true, holdToTalkActive: false);
    _holdStartedMic = false;
    try {
      if (state.micEnabled) {
        _log('Toggle mic: turning off');
        state = state.copyWith(micLatched: false);
        await _muteMic(reason: 'user toggle');
      } else {
        _log('Toggle mic: turning on');
        await _startMic();
        state = state.copyWith(micLatched: state.micEnabled);
      }
    } finally {
      if (mounted) {
        state = state.copyWith(micBusy: false);
      }
    }
  }

  void handleMicTap() {
    if (room.connectionState != ConnectionState.connected) {
      _showConnectFirstError('mic');
      return;
    }
    unawaited(toggleMic());
  }

  // Start and publish the microphone track if permissions and room allow it.
  Future<void> _startMic() async {
    if (state.micEnabled) return;
    if (room.connectionState != ConnectionState.connected) {
      state = state.copyWith(error: 'Connect to LiveKit first');
      return;
    }
    if (lkPlatformIs(PlatformType.android) ||
        lkPlatformIs(PlatformType.iOS) ||
        lkPlatformIs(PlatformType.macOS)) {
      final permission = await Permission.microphone.status;
      _log('Mic permission status: $permission');
      if (!permission.isGranted) {
        final result = await Permission.microphone.request();
        _log('Mic permission request result: $result');
        if (!result.isGranted) {
          if (!mounted) return;
          state = state.copyWith(error: 'Microphone permission denied', chatStatus: 'Mic permission denied');
          _log('Microphone permission denied');
          return;
        }
      }
    }
    try {
      await _ensureAudioInputSelected();
      _log('Enabling microphone...');
      if (_micPub != null) {
        try {
          await _micPub?.unmute();
        } catch (e) {
          _log('Mic unmute failed, republishing: $e');
          _micPub = null;
        }
      }
      if (_micPub == null) {
        final deviceId = room.selectedAudioInputDeviceId ?? Hardware.instance.selectedAudioInput?.deviceId;
        final track = await LocalAudioTrack.create(AudioCaptureOptions(deviceId: deviceId));
        await track.start();
        _attachMicTrackListener(track);
        final pub = await room.localParticipant?.publishAudioTrack(track);
        if (pub == null) {
          await track.stop();
          if (!mounted) return;
          state = state.copyWith(error: 'Mic not available yet', chatStatus: 'Mic failed');
          _log('Microphone publish failed (null publication)');
          return;
        }
        _micTrack = track;
        _micPub = pub;
      }
      if (!mounted) return;
      state = state.copyWith(micEnabled: true, chatStatus: 'Mic on');
      _log('Microphone enabled');
    } catch (e) {
      _log('Microphone error: $e');
      if (!mounted) return;
      state = state.copyWith(error: e.toString(), chatStatus: 'Mic failed');
    }
  }

  Future<void> _muteMic({required String reason}) async {
    if (!state.micEnabled) return;
    try {
      _log('Muting microphone (reason: $reason)...');
      if (_micPub != null) {
        await _micPub?.mute();
      } else {
        await room.localParticipant?.setMicrophoneEnabled(false);
      }
    } catch (e) {
      _log('Mic mute error: $e');
    } finally {
      state = state.copyWith(micLatched: false);
      final nextStatus = room.connectionState != ConnectionState.connected
          ? 'Disconnected'
          : (state.chatMode == ChatMode.voice ? 'Mic off' : 'Ready');
      if (mounted) {
        state = state.copyWith(micEnabled: false, chatStatus: nextStatus);
      }
      _log('Microphone muted');
      _restartRemoteAudioTracks('mic muted');
    }
  }

  Future<void> _unpublishMic({required String reason}) async {
    if (_micPub == null) return;
    try {
      _log('Unpublishing microphone (reason: $reason)...');
      await room.localParticipant?.removePublishedTrack(_micPub!.sid);
      await _micTrack?.stop();
    } catch (e) {
      _log('Mic unpublish error: $e');
    } finally {
      _micTrackListener?.dispose();
      _micTrackListener = null;
      _micTrack = null;
      _micPub = null;
      _micHasSignal = false;
      state = state.copyWith(micLatched: false);
      if (mounted) {
        state = state.copyWith(
          micEnabled: false,
          chatStatus: state.chatMode == ChatMode.voice ? 'Mic off' : state.chatStatus,
        );
      }
    }
  }

  Future<void> toggleCamera() async {
    if (state.cameraBusy) return;
    state = state.copyWith(cameraBusy: true);
    try {
      if (state.cameraEnabled) {
        await _stopCamera();
      } else {
        await _startCamera();
      }
    } finally {
      if (mounted) {
        state = state.copyWith(cameraBusy: false);
      }
    }
  }

  Future<void> _startCamera() async {
    if (state.cameraEnabled) return;
    if (room.connectionState != ConnectionState.connected) {
      state = state.copyWith(error: 'Connect to LiveKit first');
      return;
    }
    try {
      _log('Enabling camera...');
      if (_cameraPub == null) {
        final pub = await room.localParticipant?.setCameraEnabled(true);
        if (pub == null) {
          if (!mounted) return;
          state = state.copyWith(error: 'Camera not available yet');
          _log('Camera publish failed (null publication)');
          return;
        }
        if (pub.track is LocalVideoTrack) {
          _cameraTrack = pub.track as LocalVideoTrack;
          _cameraPub = pub as LocalTrackPublication<LocalVideoTrack>;
        }
      } else {
        await _cameraPub?.unmute();
      }
      if (!mounted) return;
      state = state.copyWith(cameraEnabled: true, localVideoTrack: _cameraTrack);
      _log('Camera enabled');
    } catch (e) {
      _log('Camera error: $e');
      if (!mounted) return;
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> _stopCamera() async {
    if (!state.cameraEnabled && _cameraPub == null) return;
    try {
      _log('Disabling camera...');
      if (_cameraPub != null) {
        await room.localParticipant?.removePublishedTrack(_cameraPub!.sid);
        await _cameraTrack?.stop();
      } else {
        await room.localParticipant?.setCameraEnabled(false);
      }
    } catch (e) {
      _log('Camera stop error: $e');
    } finally {
      _cameraTrack = null;
      _cameraPub = null;
      if (mounted) {
        state = state.copyWith(cameraEnabled: false, clearLocalVideoTrack: true);
      }
      _log('Camera disabled');
    }
  }

  void _refreshVideoTracks() {
    final tracks = _remoteVideoTracks();
    final localTrack = _localVideoTrack();
    state = state.copyWith(remoteVideoTracks: tracks, localVideoTrack: localTrack);
  }

  void _refreshParticipantCounts() {
    state = state.copyWith(remoteParticipantCount: room.remoteParticipants.length);
  }

  List<VideoTrack> _remoteVideoTracks() {
    final tracks = <VideoTrack>[];
    for (final participant in room.remoteParticipants.values) {
      for (final pub in participant.videoTrackPublications) {
        final track = pub.track;
        if (track != null && pub.subscribed) {
          tracks.add(track);
        }
      }
    }
    return tracks;
  }

  VideoTrack? _localVideoTrack() {
    final local = room.localParticipant;
    if (local == null) return null;
    for (final pub in local.videoTrackPublications) {
      final track = pub.track;
      if (track != null) return track;
    }
    return null;
  }
}
