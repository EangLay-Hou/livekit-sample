import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class LiveKitTokenResult {
  final String liveKitUrl;
  final String token;
  final String room;

  LiveKitTokenResult({
    required this.liveKitUrl,
    required this.token,
    required this.room,
  });
}

class LiveKitTokenApi {
  String _normalizeEndpoint(String endpoint) {
    final uri = Uri.parse(endpoint);
    final isLocalhost = uri.host == 'localhost' || uri.host == '127.0.0.1';
    if (isLocalhost &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      return uri.replace(host: '10.0.2.2').toString();
    }
    return endpoint;
  }

  Future<LiveKitTokenResult> fetchToken({
    required String endpoint,
    required String room,
    required String identity,
  }) async {
    final uri = Uri.parse(_normalizeEndpoint(endpoint));
    final resp = await http.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'room_name': room, 'participant_identity': identity}),
    );

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Token endpoint failed: ${resp.statusCode}');
    }

    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    final liveKitUrl =
        (map['server_url'] ??
                map['liveKitUrl'] ??
                map['livekit_url'] ??
                map['url'] ??
                '')
            .toString();
    final token =
        (map['participant_token'] ?? map['token'] ?? map['access_token'] ?? '')
            .toString();
    final roomName = (map['room_name'] ?? map['room'] ?? room).toString();

    if (liveKitUrl.isEmpty || token.isEmpty) {
      throw Exception(
        'Token endpoint returned empty server_url or participant_token',
      );
    }

    return LiveKitTokenResult(
      liveKitUrl: liveKitUrl,
      token: token,
      room: roomName,
    );
  }
}
