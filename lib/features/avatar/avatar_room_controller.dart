import 'package:livekit_client/livekit_client.dart';

class AvatarRoomController {
  late final Room room;
  EventsListener<RoomEvent>? listener;

  void init() {
    room = Room(
      roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true),
    );
    listener = room.createListener();
  }

  Future<void> connect({required String url, required String token}) async {
    await room.prepareConnection(url, token);
    await room.connect(url, token);
  }

  Future<void> disconnect() async {
    if (room.connectionState != ConnectionState.disconnected) {
      await room.disconnect();
    }
  }

  Future<void> dispose() async {
    final current = listener;
    listener = null;
    if (current != null) {
      await current.dispose();
    }
    await disconnect();
    await room.dispose();
  }
}
