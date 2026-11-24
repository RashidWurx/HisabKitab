import 'dart:io' show Platform;

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../domain/notification_models.dart';

/// Called when the user taps a notification (or one of its buttons).
/// [action] is `receive` / `extend` for the due buttons, otherwise null.
typedef NotificationTapHandler = void Function(String payload, String? action);

const _channelId = 'hisaab_reminders';
const _channelName = 'Reminders';

/// Talks to the phone. Schedules the planned reminders: cancel all, then
/// schedule the nearest 60 (iOS keeps only 64 pending; Android uses the same
/// logic). Android uses inexact scheduling so no exact-alarm permission is
/// needed; the plugin re-creates scheduled alarms after a reboot.
class ReminderScheduler {
  ReminderScheduler({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;
  String _zoneName = 'UTC';

  bool get isReady => _ready;
  String get zoneName => _zoneName;

  static bool get _supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> init({required NotificationTapHandler onTap}) async {
    if (!_supported || _ready) return;
    tz_data.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      _zoneName = info.identifier;
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      // Fall back to UTC offsets from the device clock.
      tz.setLocalLocation(tz.UTC);
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null) onTap(payload, response.actionId);
      },
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: 'Paydays, dues, subscriptions and your own reminders',
            importance: Importance.high,
          ),
        );
    _ready = true;
  }

  /// The notification that launched the app (cold start), if any.
  Future<({String payload, String? action})?> launchedBy() async {
    if (!_supported) return null;
    final details = await _plugin.getNotificationAppLaunchDetails();
    final response = details?.notificationResponse;
    if (details?.didNotificationLaunchApp == true &&
        response?.payload != null) {
      return (payload: response!.payload!, action: response.actionId);
    }
    return null;
  }

  Future<bool> areNotificationsEnabled() async {
    if (!_supported) return false;
    if (Platform.isAndroid) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.areNotificationsEnabled() ??
          false;
    }
    return true; // iOS: asked when requesting permission
  }

  /// Asks for permission (Android 13+ dialog, iOS prompt). Returns whether
  /// notifications are allowed.
  Future<bool> requestPermission() async {
    if (!_supported) return false;
    if (Platform.isAndroid) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          false;
    }
    return await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true) ??
        false;
  }

  NotificationDetails _details(PlannedReminder r) => NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Paydays, dues, subscriptions and your own reminders',
      importance: Importance.high,
      priority: Priority.high,
      actions: r.dueActions
          ? const [
              AndroidNotificationAction(
                'receive',
                'Received',
                showsUserInterface: true,
              ),
              AndroidNotificationAction(
                'extend',
                'Extend',
                showsUserInterface: true,
              ),
            ]
          : null,
    ),
    iOS: const DarwinNotificationDetails(),
  );

  /// Cancels everything and schedules [plan] (already limited to 60).
  /// Returns how many notifications were scheduled.
  Future<int> schedule(List<PlannedReminder> plan) async {
    if (!_ready) return 0;
    // Only pending ones: reminders already shown stay in the shade.
    await _plugin.cancelAllPendingNotifications();
    var id = 1;
    for (final r in plan) {
      await _plugin.zonedSchedule(
        id: id++,
        scheduledDate: tz.TZDateTime.from(r.at, tz.local),
        notificationDetails: _details(r),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: r.title,
        body: r.body,
        payload: r.payload,
      );
    }
    return plan.length;
  }

  Future<int> pendingCount() async =>
      _ready ? (await _plugin.pendingNotificationRequests()).length : 0;

  /// Shows a notification right now (the "Send a test" button).
  Future<void> showTest() async {
    if (!_ready) return;
    await _plugin.show(
      id: 0,
      title: 'Hisaab',
      body: 'Reminders are working. This is a test.',
      notificationDetails: _details(
        PlannedReminder(
          at: DateTime.now(),
          type: NotificationType.custom,
          title: 'Hisaab',
          body: '',
          payload: 'test',
        ),
      ),
      payload: 'test',
    );
  }

  /// Schedules a test notification [after] from now, through the same path
  /// real reminders use (so it proves scheduled delivery works on this phone).
  Future<void> scheduleTest({Duration after = const Duration(minutes: 1)}) async {
    if (!_ready) return;
    final at = DateTime.now().add(after);
    await _plugin.zonedSchedule(
      id: 9999,
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      notificationDetails: _details(
        PlannedReminder(
          at: at,
          type: NotificationType.custom,
          title: 'Hisaab',
          body: '',
          payload: 'test',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: 'Hisaab',
      body: 'Scheduled reminders work on this phone.',
      payload: 'test',
    );
  }

  /// Opens this app's system settings page (battery, notifications...).
  /// Some phones (TECNO, Xiaomi, Oppo...) stop background reminders unless the
  /// app is set to run without restrictions there.
  Future<void> openAppSettings() async {
    if (kIsWeb || !Platform.isAndroid) return;
    await const AndroidIntent(
      action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
      data: 'package:com.hisaab.hisaab',
    ).launch();
  }

  /// Opens the system "Battery optimisation" list.
  Future<void> openBatterySettings() async {
    if (kIsWeb || !Platform.isAndroid) return;
    await const AndroidIntent(
      action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS',
    ).launch();
  }
}