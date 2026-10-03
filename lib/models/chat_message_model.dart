import 'package:cloud_firestore/cloud_firestore.dart';

/// A chat message. Lives at `chats/{transactionId}/messages/{id}`.
/// Firestore document id is an auto id.
class ChatMessageModel {
  const ChatMessageModel({
    this.messageId = '',
    required this.senderId,
    required this.text,
    this.timestamp,
  });

  final String messageId;
  final String senderId;
  final String text;
  final DateTime? timestamp;

  factory ChatMessageModel.fromMap(
    String messageId,
    Map<String, dynamic> map,
  ) {
    return ChatMessageModel(
      messageId: messageId,
      senderId: map['senderId'] as String? ?? '',
      text: map['text'] as String? ?? '',
      timestamp: (map['timestamp'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'senderId': senderId,
        'text': text,
        'timestamp': timestamp != null ? Timestamp.fromDate(timestamp!) : null,
      };

  ChatMessageModel copyWith({
    String? messageId,
    String? senderId,
    String? text,
    DateTime? timestamp,
  }) =>
      ChatMessageModel(
        messageId: messageId ?? this.messageId,
        senderId: senderId ?? this.senderId,
        text: text ?? this.text,
        timestamp: timestamp ?? this.timestamp,
      );
}
