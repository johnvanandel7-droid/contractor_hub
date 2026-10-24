// lib/services/background_clock.dart  (UNCOMPILED - test on a real Android phone)
//
// Automatic clock in / clock out using geofences, with notifications.
// Works with the app closed and the screen off, as long as the user has signed
// in once (Firebase Auth keeps the session on the device).
//
// pubspec.yaml additions:
//   native_geofence: ^1.0.0        # check pub.dev for the latest version
//   flutter_local_notifications: ^19.0.0
//   permission_handler: ^11.3.1
 
import 'dart:io';
 
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:native_geofence/native_geofence.dart';
import 'package:permission_handler/permission_handler.dart';
 
const int _kOngoingId = 1001; // the "you are clocked in" notification
const int _kResultId = 1002; // the "you clocked out" notification
const String _kChannelId = 'clock_status';
 
final FlutterLocalNotificationsPlugin _notifications =
    FlutterLocalNotificationsPlugin();
 
Future<void> _initNotifications() async {
  const init = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    ),
  );
  // Newer flutter_local_notifications (v20+) uses a named `settings:` argument.
  await _notifications.initialize(settings: init);
}
 
/// "3h 25m" / "42m" / "0m"
String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  return h > 0 ? '${h}h ${m}m' : '${m}m';
}
 
// ---------------------------------------------------------------------------
// Notifications
// ---------------------------------------------------------------------------
 
/// Persistent notification. On Android the system itself ticks the timer
/// (chronometer) so it keeps counting with the app closed or the screen off.
/// iOS cannot update a notification live; it just shows the clock-in time.
Future<void> showClockedInNotification({
  required String jobName,
  required DateTime clockInTime,
}) async {
  final android = AndroidNotificationDetails(
    _kChannelId,
    'Clock status',
    channelDescription: 'Shows while you are clocked in',
    importance: Importance.low, // no sound each time
    priority: Priority.low,
    ongoing: true,
    autoCancel: false,
    onlyAlertOnce: true,
    showWhen: true,
    usesChronometer: true,
    when: clockInTime.millisecondsSinceEpoch,
    category: AndroidNotificationCategory.status,
  );
  await _notifications.show(
    id: _kOngoingId,
    title: 'Clocked in - $jobName',
    body: 'Since ${_hm(clockInTime)}',
    notificationDetails: NotificationDetails(
      android: android,
      iOS: const DarwinNotificationDetails(),
    ),
  );
}
 
Future<void> showClockedOutNotification({
  required String jobName,
  required Duration worked,
}) async {
  await _notifications.cancel(id: _kOngoingId);
  const android = AndroidNotificationDetails(
    'clock_result',
    'Clock out',
    channelDescription: 'Sent when you clock out',
    importance: Importance.high,
    priority: Priority.high,
  );
  await _notifications.show(
    id: _kResultId,
    title: 'Clocked out - $jobName',
    body: 'You were clocked in for ${formatDuration(worked)}.',
    notificationDetails: const NotificationDetails(
      android: android,
      iOS: DarwinNotificationDetails(),
    ),
  );
}
 
String _hm(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m ${t.hour >= 12 ? 'PM' : 'AM'}';
}
 
// ---------------------------------------------------------------------------
// Geofence callback - runs in a background isolate, app may be closed.
// ---------------------------------------------------------------------------
 
@pragma('vm:entry-point')
Future<void> geofenceTriggered(GeofenceCallbackParams params) async {
  try {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    await _initNotifications();
 
    // Firebase Auth restores the saved session by itself in this isolate.
    final user = FirebaseAuth.instance.currentUser ??
        await FirebaseAuth.instance.authStateChanges().first;
    if (user == null) return; // never signed in on this phone
 
    final db = FirebaseFirestore.instance;
    final geofence = params.geofences.first;
    final jobId = geofence.id;
 
    final jobSnap = await db.collection('jobsites').doc(jobId).get();
    final jobName = (jobSnap.data()?['name'] ?? 'Job site').toString();
 
    // Is there already an open record for this user?
    final open = await db
        .collection('clockRecords')
        .where('uid', isEqualTo: user.uid)
        .where('clockOutTime', isNull: true)
        .limit(1)
        .get();
 
    final entering = params.event == GeofenceEvent.enter ||
        params.event == GeofenceEvent.dwell;
 
    if (entering) {
      if (open.docs.isNotEmpty) {
        // Already clocked in (maybe from the app) - just make sure the
        // notification is showing.
        final t = (open.docs.first.data()['clockInTime'] as Timestamp?)
                ?.toDate() ??
            DateTime.now();
        await showClockedInNotification(jobName: jobName, clockInTime: t);
        return;
      }
      final userDoc = await db.collection('users').doc(user.uid).get();
      final now = DateTime.now();
      await db.collection('clockRecords').add({
        'uid': user.uid,
        'companyName': userDoc.data()?['companyName'],
        'jobSiteId': jobId,
        'jobSiteName': jobName,
        'clockInTime': Timestamp.fromDate(now),
        'clockOutTime': null,
        'method': 'auto',
      });
      await showClockedInNotification(jobName: jobName, clockInTime: now);
    } else if (params.event == GeofenceEvent.exit) {
      if (open.docs.isEmpty) return;
      final doc = open.docs.first;
      final inTime = (doc.data()['clockInTime'] as Timestamp).toDate();
      final now = DateTime.now();
      await doc.reference.update({'clockOutTime': Timestamp.fromDate(now)});
      await showClockedOutNotification(
        jobName: (doc.data()['jobSiteName'] ?? jobName).toString(),
        worked: now.difference(inTime),
      );
    }
  } catch (e, st) {
    debugPrint('geofenceTriggered error: $e\n$st');
  }
}
 
// ---------------------------------------------------------------------------
// Setup - call from the app (foreground)
// ---------------------------------------------------------------------------
 
class BackgroundClock {
  /// Call once in main() after Firebase.initializeApp().
  static Future<void> init() async {
    await _initNotifications();
    await NativeGeofenceManager.instance.initialize();
  }
 
  /// Ask for notification + "Allow all the time" location. Android requires
  /// the second prompt to be separate from the first. Returns true if the
  /// background location permission was granted.
  static Future<bool> requestPermissions() async {
    await Permission.notification.request();
    final whenInUse = await Permission.locationWhenInUse.request();
    if (!whenInUse.isGranted) return false;
    final always = await Permission.locationAlways.request();
    return always.isGranted;
  }
 
  /// Re-register geofences for every job in the company. Call after login and
  /// whenever jobs change. Android allows ~100 geofences per app.
  static Future<void> syncGeofences(String companyId) async {
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    final manager = NativeGeofenceManager.instance;
 
    // Remove old ones first so deleted / moved jobs don't linger.
    await manager.removeAllGeofences();
 
    final jobs = await FirebaseFirestore.instance
        .collection('jobsites')
        .where('companyId', isEqualTo: companyId)
        .get();
 
    for (final d in jobs.docs.take(95)) {
      final data = d.data();
      final lat = (data['latitude'] ?? data['lat']) as num?;
      final lng = (data['longitude'] ?? data['lng']) as num?;
      if (lat == null || lng == null) continue;
      final radius =
          ((data['radiusMeters'] ?? data['radius'] ?? 150) as num).toDouble();
 
      await manager.createGeofence(
        Geofence(
          id: d.id,
          location: Location(
              latitude: lat.toDouble(), longitude: lng.toDouble()),
          radiusMeters: radius < 100 ? 100 : radius, // <100m is unreliable
          triggers: {GeofenceEvent.enter, GeofenceEvent.exit},
          iosSettings: IosGeofenceSettings(initialTrigger: true),
          androidSettings: AndroidGeofenceSettings(
            initialTriggers: {GeofenceEvent.enter},
            expiration: const Duration(days: 365),
            notificationResponsiveness: const Duration(seconds: 30),
          ),
        ),
        geofenceTriggered,
      );
    }
  }
 
  /// Call this after a MANUAL clock-in inside the app so the same notification
  /// appears.
  static Future<void> onManualClockIn(String jobName, DateTime t) =>
      showClockedInNotification(jobName: jobName, clockInTime: t);
 
  /// Call this after a MANUAL clock-out inside the app.
  static Future<void> onManualClockOut(String jobName, Duration worked) =>
      showClockedOutNotification(jobName: jobName, worked: worked);
 
  /// If the phone rebooted or the app was updated, re-show the ongoing
  /// notification for an open record. Call at app start.
  static Future<void> restoreOngoingNotification() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final open = await FirebaseFirestore.instance
        .collection('clockRecords')
        .where('uid', isEqualTo: user.uid)
        .where('clockOutTime', isNull: true)
        .limit(1)
        .get();
    if (open.docs.isEmpty) {
      await _notifications.cancel(id: _kOngoingId);
      return;
    }
    final d = open.docs.first.data();
    await showClockedInNotification(
      jobName: (d['jobSiteName'] ?? 'Job site').toString(),
      clockInTime: (d['clockInTime'] as Timestamp).toDate(),
    );
  }
}