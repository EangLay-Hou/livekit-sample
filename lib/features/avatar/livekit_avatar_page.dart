import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/app_config.dart';
import '../../core/livekit_token_api.dart';

class AvatarChatPage extends StatefulWidget {
  const AvatarChatPage({super.key, this.autoConnect = true});

  final bool autoConnect;

  @override
  State<AvatarChatPage> createState() => _AvatarChatPageState();
}

class _ChatMessage {
  final bool isUser;
  final String text;
  final String? streamId;
  final bool isStreaming;
  final String? label;

  _ChatMessage({required this.isUser, required this.text, this.streamId, this.isStreaming = false, this.label});
}

enum _ChatMode { text, voice }

class _AvatarChatPageState extends State<AvatarChatPage> {
  late Room _room;
  final LiveKitTokenApi _tokenApi = LiveKitTokenApi();
  EventsListener<RoomEvent>? _listener;
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  final List<_ChatMessage> _messages = <_ChatMessage>[];
  final Map<String, int> _transcriptIndexById = <String, int>{};
  String _identity = '';
  _ChatMode _chatMode = _ChatMode.text;
  LocalAudioTrack? _micTrack;
  LocalTrackPublication<LocalAudioTrack>? _micPub;
  EventsListener<TrackEvent>? _micTrackListener;
  bool _micHasSignal = false;
  bool _micSpeaking = false;
  int _lastVoiceLogMs = 0;
  int _lastVoiceAboveMs = 0;
  LocalVideoTrack? _cameraTrack;
  LocalTrackPublication<LocalVideoTrack>? _cameraPub;
  bool _localSpeaking = false;
  bool _remoteAudioPaused = false;
  Timer? _resumeAudioTimer;
  bool _micEnabled = false;
  bool _cameraEnabled = false;
  bool _micBusy = false;
  bool _cameraBusy = false;
  bool _audioInputReady = false;
  bool _needsRoomReset = false;
  bool _resettingRoom = false;
  String? _currentRoomName;

  String _status = 'Disconnected';
  String _chatStatus = 'Ready';
  String? _error;
  bool _connecting = false;
  bool _sending = false;
  String? _activeRoom;

  @override
  void initState() {
    super.initState();
    _initRoom();
    if (widget.autoConnect) {
      _connect();
    }
    if (lkPlatformIs(PlatformType.android)) {
      unawaited(Hardware.instance.setSpeakerphoneOn(true));
    }
  }

  @override
  void dispose() {
    _listener?.dispose();
    _micTrackListener?.dispose();
    unawaited(_unpublishMic(reason: 'dispose'));
    _resumeAudioTimer?.cancel();
    unawaited(_disposeRoom());
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _initRoom() {
    _room = Room(roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true));
    _listener = _room.createListener();
    _wireRoomEvents();
    _registerTextHandler();
    _log('Room initialized');
  }

  Future<void> _disposeRoom() async {
    final listener = _listener;
    _listener = null;
    if (listener != null) {
      await listener.dispose();
    }
    if (_room.connectionState != ConnectionState.disconnected) {
      await _room.disconnect();
    }
    await _room.dispose();
  }

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
      _activeRoom = null;
      _currentRoomName = null;
      _needsRoomReset = false;
      _initRoom();
      if (!mounted) return;
      setState(() {
        _status = 'Disconnected';
        _connecting = false;
        _micEnabled = false;
        _cameraEnabled = false;
        _chatStatus = _chatMode == _ChatMode.voice ? 'Mic off' : 'Ready';
      });
    } finally {
      _resettingRoom = false;
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _appendMessage(_ChatMessage message) {
    final index = _messages.length;
    _messages.add(message);
    _listKey.currentState?.insertItem(index, duration: const Duration(milliseconds: 180));
  }

  void _shiftTranscriptIndicesDownFrom(int removedIndex) {
    if (_transcriptIndexById.isEmpty) return;
    for (final key in _transcriptIndexById.keys.toList()) {
      final current = _transcriptIndexById[key];
      if (current == null) continue;
      if (current == removedIndex) {
        _transcriptIndexById.remove(key);
      } else if (current > removedIndex) {
        _transcriptIndexById[key] = current - 1;
      }
    }
  }

  void _removeMessageAt(int index) {
    if (index < 0 || index >= _messages.length) return;
    final removed = _messages.removeAt(index);
    _listKey.currentState?.removeItem(
      index,
      (context, animation) => _buildMessageItem(removed, animation),
      duration: const Duration(milliseconds: 180),
    );
    _shiftTranscriptIndicesDownFrom(index);
  }

  void _onChatModeChanged(Set<_ChatMode> selection) {
    final nextMode = selection.first;
    if (nextMode == _chatMode) return;

    if (nextMode == _ChatMode.text) {
      _log('Switching to text mode');
      unawaited(_muteMic(reason: 'chat mode change'));
    } else if (_room.connectionState != ConnectionState.connected) {
      setState(() {
        _error = 'Connect to LiveKit first';
        _chatStatus = 'Not connected';
      });
      _log('Voice mode blocked: not connected');
      return;
    }

    setState(() {
      _chatMode = nextMode;
      _chatStatus = nextMode == _ChatMode.voice ? (_micEnabled ? 'Mic on' : 'Tap mic to speak') : 'Ready';
    });
    _log('Chat mode set to ${nextMode == _ChatMode.voice ? 'voice' : 'text'}');
    if (nextMode == _ChatMode.text) {
      _restartRemoteAudioTracks('chat mode text');
    }
  }

  void _registerTextHandler() {
    try {
      _room.registerTextStreamHandler(AppConfig.liveKitChatTopic, (reader, identity) async {
        final text = await reader.readAll();
        _log('Text stream received from $identity');
        if (!mounted) return;
        setState(() {
          _appendMessage(_ChatMessage(isUser: false, text: text, label: identity));
        });
        _scrollToBottom();
      });
    } catch (e) {
      _log('Text handler error: $e');
    }
  }

  void _wireRoomEvents() {
    final listener = _listener;
    if (listener == null) return;
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
  }

  void _log(String message) {
    debugPrint('[AvatarChat] $message');
  }

  void _logRoomState(String where) {
    final localId = _room.localParticipant?.identity ?? 'null';
    final remoteIds = _room.remoteParticipants.keys.toList();
    final audioPubs = _room.localParticipant?.audioTrackPublications.length ?? 0;
    final videoPubs = _room.localParticipant?.videoTrackPublications.length ?? 0;
    _log(
      '$where: conn=${_room.connectionState} local=$localId room=${_currentRoomName ?? 'unset'} remotes=${remoteIds.length} $remoteIds '
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
        await _room.setAudioInputDevice(selected);
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
      for (final participant in _room.remoteParticipants.values) {
        for (final pub in participant.audioTrackPublications) {
          final track = pub.track;
          if (track != null) {
            track.start();
          }
        }
      }
      unawaited(_room.startAudio());
      _log('Restarted remote audio tracks ($reason)');
    } catch (e) {
      _log('Restart remote audio error: $e');
    }
  }

  void _onRoomConnected(RoomConnectedEvent _) {
    _log('Room connected');
    if (_resettingRoom) return;
    if (!mounted) return;
    setState(() {
      _status = 'Connected';
      _connecting = false;
      _error = null;
      _chatStatus = _chatMode == _ChatMode.voice ? (_micEnabled ? 'Mic on' : 'Tap mic to speak') : 'Ready';
    });
    _logRoomState('after connect');
  }

  void _onRoomDisconnected(RoomDisconnectedEvent _) {
    _log('Room disconnected');
    if (_resettingRoom) return;
    _needsRoomReset = true;
    if (!mounted) return;
    setState(() {
      _status = 'Disconnected';
      _connecting = false;
      _micEnabled = false;
      _cameraEnabled = false;
      _activeRoom = null;
      _audioInputReady = false;
      _chatStatus = 'Disconnected';
    });
    _micTrackListener?.dispose();
    _micTrackListener = null;
    _micTrack = null;
    _micPub = null;
    _micHasSignal = false;
    _logRoomState('after disconnect');
  }

  void _onRoomReconnecting(RoomReconnectingEvent _) {
    _log('Room reconnecting');
    if (_resettingRoom) return;
    if (!mounted) return;
    setState(() {
      _status = 'Reconnecting...';
    });
  }

  void _onRoomReconnected(RoomReconnectedEvent _) {
    _log('Room reconnected');
    if (_resettingRoom) return;
    if (!mounted) return;
    setState(() {
      _status = 'Connected';
    });
  }

  void _onTranscriptionEvent(TranscriptionEvent event) {
    final segments = event.segments;
    if (segments.isEmpty) return;
    if (!mounted) return;
    final participant = event.participant;
    final isUser = participant is LocalParticipant || participant.identity == _identity;
    final label = isUser ? 'You' : (participant.identity.isNotEmpty ? participant.identity : 'Bot');
    setState(() {
      for (final TranscriptionSegment segment in segments) {
        final text = segment.text.trim();
        if (text.isEmpty) continue;
        final displayText = text;

        final existingIndex = _transcriptIndexById[segment.id];
        if (existingIndex != null && existingIndex >= 0 && existingIndex < _messages.length) {
          _messages[existingIndex] = _ChatMessage(
            isUser: isUser,
            text: displayText,
            streamId: segment.id,
            isStreaming: !segment.isFinal,
            label: label,
          );
        } else {
          _appendMessage(
            _ChatMessage(
              isUser: isUser,
              text: displayText,
              streamId: segment.id,
              isStreaming: !segment.isFinal,
              label: label,
            ),
          );
          _transcriptIndexById[segment.id] = _messages.length - 1;
        }

        if (segment.isFinal) {
          _transcriptIndexById.remove(segment.id);
          _log('Transcription final: $displayText');
        }
      }
    });
    _scrollToBottom();
  }

  void _onLocalTrackPublished(LocalTrackPublishedEvent event) {
    final source = event.publication.source;
    if (source == TrackSource.microphone) {
      _log('Mic published sid=${event.publication.sid}');
      if (!mounted) return;
      setState(() {
        _micEnabled = true;
        if (_chatMode == _ChatMode.voice) {
          _chatStatus = 'Mic on';
        }
      });
      return;
    }
    if (source == TrackSource.camera) {
      _log('Camera published sid=${event.publication.sid}');
      if (event.publication.track is LocalVideoTrack) {
        _cameraTrack = event.publication.track as LocalVideoTrack;
        _cameraPub = event.publication as LocalTrackPublication<LocalVideoTrack>;
      }
      if (!mounted) return;
      setState(() {
        _cameraEnabled = true;
      });
    }
  }

  void _onLocalTrackUnpublished(LocalTrackUnpublishedEvent event) {
    final source = event.publication.source;
    if (source == TrackSource.microphone) {
      _log('Mic unpublished sid=${event.publication.sid}');
      if (!mounted) return;
      setState(() {
        _micEnabled = false;
        if (_chatMode == _ChatMode.voice) {
          _chatStatus = 'Mic off';
        }
      });
      return;
    }
    if (source == TrackSource.camera) {
      _log('Camera unpublished sid=${event.publication.sid}');
      _cameraTrack = null;
      _cameraPub = null;
      if (!mounted) return;
      setState(() {
        _cameraEnabled = false;
      });
    }
  }

  void _onTrackMuted(TrackMutedEvent event) {
    if (event.participant is! LocalParticipant) return;
    final source = event.publication.source;
    if (source == TrackSource.microphone) {
      _log('Mic muted');
      if (!mounted) return;
      setState(() {
        _micEnabled = false;
        if (_chatMode == _ChatMode.voice) {
          _chatStatus = 'Mic off';
        }
      });
      return;
    }
    if (source == TrackSource.camera) {
      _log('Camera muted');
      if (event.publication.track is LocalVideoTrack) {
        _cameraTrack = event.publication.track as LocalVideoTrack;
        _cameraPub = event.publication as LocalTrackPublication<LocalVideoTrack>;
      }
      if (!mounted) return;
      setState(() {
        _cameraEnabled = false;
      });
    }
  }

  void _onTrackUnmuted(TrackUnmutedEvent event) {
    if (event.participant is! LocalParticipant) return;
    final source = event.publication.source;
    if (source == TrackSource.microphone) {
      _log('Mic unmuted');
      if (!mounted) return;
      setState(() {
        _micEnabled = true;
        if (_chatMode == _ChatMode.voice) {
          _chatStatus = 'Mic on';
        }
      });
      return;
    }
    if (source == TrackSource.camera) {
      _log('Camera unmuted');
      if (event.publication.track is LocalVideoTrack) {
        _cameraTrack = event.publication.track as LocalVideoTrack;
        _cameraPub = event.publication as LocalTrackPublication<LocalVideoTrack>;
      }
      if (!mounted) return;
      setState(() {
        _cameraEnabled = true;
      });
    }
  }

  void _onTrackSubscribed(TrackSubscribedEvent event) {
    if (event.track is RemoteAudioTrack) {
      final track = event.track as RemoteAudioTrack;
      track.start();
      _log('Remote audio track started');
    }
    if (!mounted) return;
    setState(() {});
  }

  void _onTrackUnsubscribed(TrackUnsubscribedEvent event) {
    if (!mounted) return;
    setState(() {});
  }

  void _onTrackSubscriptionError(TrackSubscriptionExceptionEvent event) {
    _log('Track subscription failed sid=${event.sid} reason=${event.reason}');
  }

  void _onActiveSpeakersChanged(ActiveSpeakersChangedEvent event) {
    final localSid = _room.localParticipant?.sid;
    final speakingNow = event.speakers.any((s) => s.sid == localSid);
    if (speakingNow != _localSpeaking) {
      _localSpeaking = speakingNow;
      _log('Active speakers updated: localSpeaking=$_localSpeaking, count=${event.speakers.length}');
      _handleInterruptBot(_localSpeaking);
    }
  }

  void _handleInterruptBot(bool speaking) {
    _resumeAudioTimer?.cancel();
    if (speaking) {
      unawaited(_pauseRemoteAudio());
    } else {
      // resume after brief delay to avoid rapid flip
      _resumeAudioTimer = Timer(const Duration(milliseconds: 400), () => unawaited(_resumeRemoteAudio()));
    }
  }

  Future<void> _pauseRemoteAudio() async {
    if (_remoteAudioPaused) return;
    for (final participant in _room.remoteParticipants.values) {
      for (final pub in participant.audioTrackPublications) {
        await pub.unsubscribe();
      }
    }
    _remoteAudioPaused = true;
    _log('Remote audio paused while speaking');
  }

  Future<void> _resumeRemoteAudio() async {
    if (!_remoteAudioPaused) return;
    for (final participant in _room.remoteParticipants.values) {
      for (final pub in participant.audioTrackPublications) {
        await pub.subscribe();
      }
    }
    _remoteAudioPaused = false;
    _log('Remote audio resumed after speaking');
  }

  void _onAudioPlaybackStatusChanged(AudioPlaybackStatusChanged event) {
    if (!_room.canPlaybackAudio) {
      _log('Audio playback requires user action, starting audio');
      unawaited(_room.startAudio());
    }
  }

  void _onDataReceived(DataReceivedEvent event) {
    final text = String.fromCharCodes(event.data);
    final from = event.participant?.identity ?? 'remote';
    _log('Data received topic=${event.topic} from=$from len=${event.data.length}');
    _logRoomState('on data received');
    if (!mounted) return;
    setState(() {
      _appendMessage(_ChatMessage(isUser: false, text: text, label: from));
    });
    _scrollToBottom();
  }

  bool get _hasTokenEndpoint {
    final endpoint = AppConfig.liveKitTokenEndpoint;
    return endpoint.isNotEmpty && !endpoint.contains('YOUR_CLOUD_FUNCTION_URL');
  }

  Future<LiveKitTokenResult> _resolveCredentials() async {
    _currentRoomName ??= '${AppConfig.liveKitRoomName}_${DateTime.now().millisecondsSinceEpoch}';
    final room = _currentRoomName!;
    if (!_hasTokenEndpoint) {
      throw Exception('Set liveKitTokenEndpoint in AppConfig');
    }
    if (room.isEmpty || room.contains('YOUR_ROOM_NAME')) {
      throw Exception('Set liveKitRoomName in AppConfig');
    }
    _log('Requesting token: endpoint=${AppConfig.liveKitTokenEndpoint} room=$room identity=$_identity');
    return _tokenApi.fetchToken(endpoint: AppConfig.liveKitTokenEndpoint, room: room, identity: _identity);
  }

  Future<void> _connect() async {
    if (_connecting || _room.connectionState == ConnectionState.connected) return;
    if (_needsRoomReset) {
      await _resetRoom(reason: 'reconnect');
    }
    _identity = '${AppConfig.liveKitIdentityPrefix}_${DateTime.now().millisecondsSinceEpoch}';

    _logRoomState('pre-connect');
    setState(() {
      _connecting = true;
      _status = 'Connecting...';
      _error = null;
    });

    try {
      _log('Connecting to LiveKit...');
      final creds = await _resolveCredentials();
      _activeRoom = creds.room;
      _log('Connecting to url=${creds.liveKitUrl} room=${creds.room}');
      await _room.prepareConnection(creds.liveKitUrl, creds.token);
      await _room.connect(creds.liveKitUrl, creds.token);
    } catch (e) {
      _log('Connect error: $e');
      _activeRoom = null;
      if (!mounted) return;
      setState(() {
        _status = 'Connect failed';
        _connecting = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _disconnect() async {
    if (_room.connectionState == ConnectionState.disconnected) return;
    setState(() {
      _status = 'Disconnecting...';
    });
    await _unpublishMic(reason: 'disconnect');
    await _stopCamera();
    await _resetRoom(reason: 'disconnect');
  }

  Future<void> _sendMessage() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _logRoomState('before send');
    if (_room.connectionState != ConnectionState.connected) {
      setState(() {
        _error = 'Connect to LiveKit first';
        _chatStatus = 'Not connected';
      });
      _log('Send blocked: not connected');
      return;
    }

    setState(() {
      _appendMessage(_ChatMessage(isUser: true, text: text, label: 'You'));
      _input.clear();
      _chatStatus = 'Sending...';
      _sending = true;
    });
    _scrollToBottom();

    try {
      _log('Sending text: "$text" topic=${AppConfig.liveKitChatTopic}');
      await _room.localParticipant?.sendText(text, options: SendTextOptions(topic: AppConfig.liveKitChatTopic));

      if (!mounted) return;
      setState(() {
        _chatStatus = 'Sent to room';
        _sending = false;
      });
      _scrollToBottom();
      _logRoomState('after send ok');
    } catch (e) {
      _log('Send text error: $e');
      if (!mounted) return;
      setState(() {
        _chatStatus = 'Send failed';
        _error = e.toString();
        _sending = false;
      });
      _scrollToBottom();
      _logRoomState('after send fail');
    }
  }

  Future<void> _toggleMic() async {
    if (_micBusy) return;
    _micBusy = true;
    try {
      if (_micEnabled) {
        _log('Toggle mic: turning off');
        await _muteMic(reason: 'user toggle');
      } else {
        _log('Toggle mic: turning on');
        await _startMic();
      }
    } finally {
      _micBusy = false;
    }
  }

  Future<void> _startMic() async {
    if (_micEnabled) return;
    if (_room.connectionState != ConnectionState.connected) {
      setState(() {
        _error = 'Connect to LiveKit first';
      });
      return;
    }
    if (lkPlatformIs(PlatformType.android) || lkPlatformIs(PlatformType.iOS) || lkPlatformIs(PlatformType.macOS)) {
      final permission = await Permission.microphone.status;
      _log('Mic permission status: $permission');
      if (!permission.isGranted) {
        final result = await Permission.microphone.request();
        _log('Mic permission request result: $result');
        if (!result.isGranted) {
          if (!mounted) return;
          setState(() {
            _error = 'Microphone permission denied';
            _chatStatus = 'Mic permission denied';
          });
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
        final deviceId = _room.selectedAudioInputDeviceId ?? Hardware.instance.selectedAudioInput?.deviceId;
        final track = await LocalAudioTrack.create(AudioCaptureOptions(deviceId: deviceId));
        await track.start();
        _attachMicTrackListener(track);
        final pub = await _room.localParticipant?.publishAudioTrack(track);
        if (pub == null) {
          await track.stop();
          if (!mounted) return;
          setState(() {
            _error = 'Mic not available yet';
            _chatStatus = 'Mic failed';
          });
          _log('Microphone publish failed (null publication)');
          return;
        }
        _micTrack = track;
        _micPub = pub;
      }
      if (!mounted) return;
      setState(() {
        _micEnabled = true;
        _chatStatus = 'Mic on';
      });
      _log('Microphone enabled');
    } catch (e) {
      _log('Microphone error: $e');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _chatStatus = 'Mic failed';
      });
    }
  }

  Future<void> _muteMic({required String reason}) async {
    if (!_micEnabled) return;
    try {
      _log('Muting microphone (reason: $reason)...');
      if (_micPub != null) {
        await _micPub?.mute();
      } else {
        await _room.localParticipant?.setMicrophoneEnabled(false);
      }
    } catch (e) {
      _log('Mic mute error: $e');
    } finally {
      final nextStatus = _room.connectionState != ConnectionState.connected
          ? 'Disconnected'
          : (_chatMode == _ChatMode.voice ? 'Mic off' : 'Ready');
      if (!mounted) return;
      setState(() {
        _micEnabled = false;
        _chatStatus = nextStatus;
      });
      _log('Microphone muted');
      _restartRemoteAudioTracks('mic muted');
    }
  }

  Future<void> _unpublishMic({required String reason}) async {
    if (_micPub == null) return;
    try {
      _log('Unpublishing microphone (reason: $reason)...');
      await _room.localParticipant?.removePublishedTrack(_micPub!.sid);
      await _micTrack?.stop();
    } catch (e) {
      _log('Mic unpublish error: $e');
    } finally {
      _micTrackListener?.dispose();
      _micTrackListener = null;
      _micTrack = null;
      _micPub = null;
      _micHasSignal = false;
      if (!mounted) return;
      setState(() {
        _micEnabled = false;
        if (_chatMode == _ChatMode.voice) {
          _chatStatus = 'Mic off';
        }
      });
    }
  }

  Future<void> _toggleCamera() async {
    if (_cameraBusy) return;
    _cameraBusy = true;
    try {
      if (_cameraEnabled) {
        await _stopCamera();
      } else {
        await _startCamera();
      }
    } finally {
      _cameraBusy = false;
    }
  }

  Future<void> _startCamera() async {
    if (_cameraEnabled) return;
    if (_room.connectionState != ConnectionState.connected) {
      setState(() {
        _error = 'Connect to LiveKit first';
      });
      return;
    }
    try {
      _log('Enabling camera...');
      if (_cameraPub == null) {
        final pub = await _room.localParticipant?.setCameraEnabled(true);
        if (pub == null) {
          if (!mounted) return;
          setState(() {
            _error = 'Camera not available yet';
          });
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
      setState(() {
        _cameraEnabled = true;
      });
      _log('Camera enabled');
    } catch (e) {
      _log('Camera error: $e');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    }
  }

  Future<void> _stopCamera() async {
    if (!_cameraEnabled && _cameraPub == null) return;
    try {
      _log('Disabling camera...');
      if (_cameraPub != null) {
        await _room.localParticipant?.removePublishedTrack(_cameraPub!.sid);
        await _cameraTrack?.stop();
      } else {
        await _room.localParticipant?.setCameraEnabled(false);
      }
    } catch (e) {
      _log('Camera stop error: $e');
    } finally {
      if (!mounted) return;
      _cameraTrack = null;
      _cameraPub = null;
      setState(() {
        _cameraEnabled = false;
      });
      _log('Camera disabled');
    }
  }

  List<VideoTrack> _remoteVideoTracks() {
    final tracks = <VideoTrack>[];
    for (final participant in _room.remoteParticipants.values) {
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
    final local = _room.localParticipant;
    if (local == null) return null;
    for (final pub in local.videoTrackPublications) {
      final track = pub.track;
      if (track != null) return track;
    }
    return null;
  }

  Widget _buildMessageItem(_ChatMessage msg, Animation<double> animation) {
    return SizeTransition(
      sizeFactor: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: Align(
        alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          key: ValueKey('${msg.isUser}-${msg.text}-${msg.streamId ?? ''}'),
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: msg.isUser ? Colors.blue.withValues(alpha: 0.12) : Colors.green.withValues(alpha: 0.12),
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
                    style: TextStyle(
                      fontSize: 12,
                      color: msg.isUser ? Colors.blueGrey : Colors.green[800],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              AnimatedSize(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                alignment: Alignment.centerLeft,
                child: msg.isStreaming && !msg.isUser
                    ? StreamBuilder<int>(
                        stream: _StreamingDots.ticks,
                        initialData: 0,
                        builder: (context, snapshot) {
                          final dots = _StreamingDots.paddedDots(snapshot.data ?? 0);
                          final text = '${msg.text}$dots';
                          return Text(text, style: const TextStyle(fontSize: 16), softWrap: true);
                        },
                      )
                    : Text(msg.text, style: const TextStyle(fontSize: 16), softWrap: true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tracks = _remoteVideoTracks();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Avatar Chat (LiveKit)'),
        actions: [
          TextButton(
            onPressed: _connecting || _room.connectionState == ConnectionState.connected ? null : _connect,
            child: const Text('Connect'),
          ),
          IconButton(
            onPressed: _room.connectionState == ConnectionState.connected ? _toggleCamera : null,
            icon: Icon(_cameraEnabled ? Icons.videocam : Icons.videocam_off),
            tooltip: _cameraEnabled ? 'Stop camera' : 'Start camera',
          ),
          TextButton(
            onPressed: _room.connectionState == ConnectionState.connected ? _disconnect : null,
            child: const Text('Disconnect'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _activeRoom == null ? 'Status: $_status' : 'Status: $_status (room: $_activeRoom)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Remote: ${_room.remoteParticipants.length}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 8),
          SizedBox(
            height: 220,
            child: Stack(
              children: [
                Positioned.fill(
                  child: tracks.isEmpty
                      ? const Center(child: Text('Waiting for avatar video...'))
                      : VideoTrackRenderer(tracks.first),
                ),
                if (_localVideoTrack() != null)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 96,
                        height: 72,
                        child: IgnorePointer(
                          // Prevent tap-to-focus on devices that don't support it.
                          ignoring: true,
                          child: VideoTrackRenderer(_localVideoTrack()!),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: AnimatedList(
              key: _listKey,
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              initialItemCount: _messages.length,
              itemBuilder: (context, index, animation) => _buildMessageItem(_messages[index], animation),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                const SizedBox(width: 12),
                Expanded(child: Text('Chat: $_chatStatus', maxLines: 1, overflow: TextOverflow.ellipsis)),
                SegmentedButton<_ChatMode>(
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: const [
                    ButtonSegment<_ChatMode>(value: _ChatMode.text, label: Text('Text')),
                    ButtonSegment<_ChatMode>(value: _ChatMode.voice, label: Text('Voice')),
                  ],
                  selected: <_ChatMode>{_chatMode},
                  onSelectionChanged: _onChatModeChanged,
                ),
              ],
            ),
          ),
          if (_chatMode == _ChatMode.text)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 30),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: InputDecoration(
                        hintText: 'Type your message...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(60)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(onPressed: _sending ? null : _sendMessage, child: const Text('Send')),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ListeningBadge(enabled: _micEnabled),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _room.connectionState == ConnectionState.connected && !_micBusy ? _toggleMic : null,
                    icon: Icon(_micEnabled ? Icons.mic : Icons.mic_off),
                    label: Text(_micEnabled ? 'Stop Mic' : 'Start Mic'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ListeningBadge extends StatelessWidget {
  const _ListeningBadge({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? Colors.green : Colors.grey;
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

class _StreamingDots extends StatelessWidget {
  const _StreamingDots();

  static const int maxDots = 3;
  static final Stream<int> ticks = Stream<int>.periodic(
    const Duration(milliseconds: 320),
    (i) => (i % (maxDots + 1)),
  ).asBroadcastStream();

  static String paddedDots(int count) {
    final clamped = count.clamp(0, maxDots);
    final dots = '.' * clamped;
    return dots.padRight(maxDots, ' ');
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: ticks,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        final dots = paddedDots(count);
        return Text(dots, style: const TextStyle(fontSize: 16));
      },
    );
  }
}
