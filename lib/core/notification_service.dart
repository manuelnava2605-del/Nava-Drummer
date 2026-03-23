// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — NotificationService
//
// Handles:
//   1. FCM (Firebase Cloud Messaging) — remote push from server
//   2. flutter_local_notifications   — scheduled local reminders (streak, practice)
//
// Usage:
//   await NotificationService.instance.init();
//   NotificationService.instance.setEnabled(true);
//   NotificationService.instance.schedulePracticeReminder(hour: 19, minute: 0);
//   NotificationService.instance.cancelAll();
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzData;

// ── Notification IDs ──────────────────────────────────────────────────────────

abstract class _NotifId {
  static const int practiceReminder = 1;
  static const int streakWarning    = 2;
  static const int achievement      = 3;
}

// ── NotificationService ───────────────────────────────────────────────────────

class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _enabled     = true;

  bool get isEnabled => _enabled;

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Load user preference
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool('notifications_enabled') ?? true;

    // Init timezone data (needed for scheduled notifications)
    tzData.initializeTimeZones();

    // ── Local notifications setup ────────────────────────────────────────────
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit     = DarwinInitializationSettings(
      requestAlertPermission:  false, // we request manually below
      requestBadgePermission:  false,
      requestSoundPermission:  false,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS:     iosInit,
    );

    await _local.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onLocalNotification,
    );

    // ── FCM setup ────────────────────────────────────────────────────────────
    try {
      await _setupFcm();
    } catch (e) {
      debugPrint('[NotificationService] FCM setup failed: $e');
    }

    // Schedule default daily practice reminder (7 PM)
    if (_enabled) {
      await _scheduleDefaultReminders();
    }
  }

  // ── Enable / Disable ─────────────────────────────────────────────────────

  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', enabled);

    if (enabled) {
      await requestPermissions();
      await _scheduleDefaultReminders();
    } else {
      await cancelAll();
    }
  }

  // ── Permissions ───────────────────────────────────────────────────────────

  Future<bool> requestPermissions() async {
    if (Platform.isIOS) {
      final granted = await _local
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      return granted ?? false;
    }

    if (Platform.isAndroid) {
      final granted = await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      return granted ?? false;
    }

    return false;
  }

  // ── FCM ───────────────────────────────────────────────────────────────────

  Future<void> _setupFcm() async {
    final messaging = FirebaseMessaging.instance;

    // Request FCM permission (iOS)
    await messaging.requestPermission(
      alert:       true,
      badge:       true,
      sound:       true,
      provisional: false,
    );

    // Get and log FCM token (send to your server to target this device)
    final token = await messaging.getToken();
    debugPrint('[NotificationService] FCM token: $token');

    // Foreground messages — show as local notification
    FirebaseMessaging.onMessage.listen(_handleFcmForeground);

    // Background / terminated — handled by OS, no action needed here
  }

  void _handleFcmForeground(RemoteMessage message) {
    if (!_enabled) return;
    final notification = message.notification;
    if (notification == null) return;

    _local.show(
      notification.hashCode,
      notification.title ?? 'NavaDrummer',
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'nava_push', 'Push Notifications',
          channelDescription: 'Remote push notifications from NavaDrummer',
          importance: Importance.high,
          priority:   Priority.high,
          icon:       '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  // ── Scheduled local notifications ─────────────────────────────────────────

  Future<void> _scheduleDefaultReminders() async {
    await schedulePracticeReminder(hour: 19, minute: 0);
  }

  /// Schedule a daily practice reminder at [hour]:[minute] local time.
  Future<void> schedulePracticeReminder({
    required int hour,
    required int minute,
  }) async {
    if (!_enabled) return;

    await _local.zonedSchedule(
      _NotifId.practiceReminder,
      '🥁 ¡Hora de practicar!',
      'Mantén tu racha. ¡Toca aunque sea 5 minutos!',
      _nextInstanceOf(hour, minute),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'nava_reminders', 'Recordatorios de práctica',
          channelDescription: 'Recordatorios diarios para mantener tu racha',
          importance:         Importance.defaultImportance,
          priority:           Priority.defaultPriority,
          icon:               '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time, // repeat daily
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Show an immediate streak warning (call when user misses a day).
  Future<void> showStreakWarning(int currentStreak) async {
    if (!_enabled) return;

    await _local.show(
      _NotifId.streakWarning,
      '⚡ ¡Tu racha está en riesgo!',
      currentStreak > 0
          ? '¡Tienes $currentStreak días de racha! No la pierdas hoy.'
          : 'Vuelve a practicar y empieza una nueva racha.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'nava_streak', 'Alertas de racha',
          channelDescription: 'Alertas cuando tu racha está en riesgo',
          importance:         Importance.high,
          priority:           Priority.high,
          icon:               '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
      ),
    );
  }

  /// Show an achievement unlock notification.
  Future<void> showAchievementUnlocked(String name, String emoji) async {
    if (!_enabled) return;

    await _local.show(
      _NotifId.achievement,
      '$emoji ¡Logro desbloqueado!',
      name,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'nava_achievements', 'Logros',
          channelDescription: 'Notificaciones de logros desbloqueados',
          importance:         Importance.defaultImportance,
          priority:           Priority.defaultPriority,
          icon:               '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: false,
        ),
      ),
    );
  }

  /// Cancel all scheduled and displayed notifications.
  Future<void> cancelAll() => _local.cancelAll();

  // ── Helpers ───────────────────────────────────────────────────────────────

  tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now  = tz.TZDateTime.now(tz.local);
    var   next = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (next.isBefore(now) || next.isAtSameMomentAs(now)) {
      next = next.add(const Duration(days: 1));
    }
    return next;
  }

  void _onLocalNotification(NotificationResponse response) {
    // Deep link handling — navigate to practice screen if needed
    debugPrint('[NotificationService] Tapped: ${response.payload}');
  }
}
