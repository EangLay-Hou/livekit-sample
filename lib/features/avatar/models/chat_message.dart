class ChatMessage {
  final bool isUser;
  final String text;
  final String? streamId;
  final bool isStreaming;
  final String? label;

  const ChatMessage({
    required this.isUser,
    required this.text,
    this.streamId,
    this.isStreaming = false,
    this.label,
  });
}
