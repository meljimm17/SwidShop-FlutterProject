import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Top-level background message handler for Firebase Messaging.
///
/// Must be a top-level (or static) function annotated with
/// `@pragma('vm:entry-point')`.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Runs in a separate isolate; keep it lightweight.
  debugPrint('SwidShop background message: ${message.messageId}');
}

/// Wraps Firebase Cloud Messaging (used for outbid/notification alerts).
class NotificationService {
  NotificationService({FirebaseMessaging? messaging})
      : _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;

  /// Requests permission and returns the device FCM token (may be null on
  /// web/desktop or if permission is denied).
  Future<String?> init() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return null;
    }
    try {
      return await _messaging.getToken();
    } catch (e) {
      debugPrint('FCM getToken failed: $e');
      return null;
    }
  }

  /// Stream of messages received while the app is in the foreground.
  Stream<RemoteMessage> get onForegroundMessage =>
      FirebaseMessaging.onMessage;

  /// Stream of notifications that opened the app from the background.
  Stream<RemoteMessage> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp;

  /// The notification that launched the app from a terminated state, if any.
  Future<RemoteMessage?> getInitialMessage() =>
      _messaging.getInitialMessage();

  /// Topic subscription helpers (e.g. outage/announcement broadcast).
  Future<void> subscribeToTopic(String topic) =>
      _messaging.subscribeToTopic(topic);

  Future<void> unsubscribeFromTopic(String topic) =>
      _messaging.unsubscribeFromTopic(topic);
}
