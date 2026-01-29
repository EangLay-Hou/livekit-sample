/// Central place for configuration.
///
/// Replace these values for your environment.
class AppConfig {
  /// Local/remote backend base URL for token + speak endpoints.
  /// Use localhost for iOS sim, 10.0.2.2 for Android emu, or LAN IP for device.
  static const String liveKitBackendBaseUrl = 'http://10.0.2.2:3001';

  /// Token endpoint response JSON can be:
  /// - {"server_url":"wss://...","participant_token":"...","room_name":"..."}
  /// - {"liveKitUrl":"wss://...","token":"...","room":"..."}
  static const String liveKitTokenEndpoint = '$liveKitBackendBaseUrl/create-room-token';
  static final String liveKitRoomName = 'demo';
  static const String liveKitIdentityPrefix = 'flutter';
  static const String liveKitChatTopic = 'lk.chat';
}
