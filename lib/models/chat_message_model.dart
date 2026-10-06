import 'package:cloud_firestore/cloud_firestore.dart';

/// A chat message. Lives at `chats/{transactionId}/messages/{id}`.
/// Firestore document id is an auto id.
class ChatMessageModel {
  const ChatMessageModel({
    this.messageId = '',
    required this.senderId,
    required this.text,
    this.imageUrl = '',
    this.timestamp,
  });

  final String messageId;
  final String senderId;
  final String text;

  /// Cloudinary secure_url of a photo sent in the chat ('' = text only).
  final String imageUrl;
  final DateTime? timestamp;

  bool get hasImage => imageUrl.isNotEmpty;

  /// One-line preview for thread lists and notifications.
  String get preview => text.isNotEmpty ? text : (hasImage ? 'Photo' : '');

  factory ChatMessageModel.fromMap(
    String messageId,
    Map<String, dynamic> map,
  ) {
    return ChatMessageModel(
      messageId: messageId,
      senderId: map['senderId'] as String? ?? '',
      text: map['text'] as String? ?? '',
      imageUrl: map['imageUrl'] as String? ?? '',
      timestamp: (map['timestamp'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'senderId': senderId,
        'text': text,
        'imageUrl': imageUrl,
        'timestamp': timestamp != null ? Timestamp.fromDate(timestamp!) : null,
      };

  ChatMessageModel copyWith({
    String? messageId,
    String? senderId,
    String? text,
    String? imageUrl,
    DateTime? timestamp,
  }) =>
      ChatMessageModel(
        messageId: messageId ?? this.messageId,
        senderId: senderId ?? this.senderId,
        text: text ?? this.text,
        imageUrl: imageUrl ?? this.imageUrl,
        timestamp: timestamp ?? this.timestamp,
      );
}
