import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

final firebase = FirebaseFirestore.instance;
final auth = FirebaseAuth.instance;

/// Central place for all Firestore/Auth reads & writes.
/// Keeping this in one class makes it easy to swap the backend later
/// and keeps UI widgets from talking to Firestore directly.
class FirebaseServices {
  FirebaseServices._();
  static final FirebaseServices instance = FirebaseServices._();

  // ─── Convenience ──────────────────────────────────────────────────────────

  String? get currentUid => auth.currentUser?.uid;
  String? get currentEmail => auth.currentUser?.email?.trim().toLowerCase();

  // ═══════════════════════════════════════════════════════════════════════════
  // AUTH — sign out (used by app_bar.dart)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Signs the current user out of Firebase Auth.
  Future<void> signOut() => auth.signOut();

  // ---------------- USERS ----------------

  /// Returns the user document, or null if it doesn't exist.
  /// This is async — callers MUST await it or use a FutureBuilder/StreamBuilder.
  Future<Map<String, dynamic>?> getUser(String uid) async {
    final doc = await firebase.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return {'id': doc.id, ...doc.data()!};
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> userStream(String uid) {
    return firebase.collection('users').doc(uid).snapshots();
  }

  Future<String?> getUsersCompanyId(String userId) async {
    try {
      final userDoc = await firebase.collection('users').doc(userId).get();
      final fetchedCompanyId = userDoc.data()?['companyId'] as String?;
      return fetchedCompanyId;
    } catch (e) {
      return null;
    }
  }

  Future<String?> getUserEmail() async {
    try {
      final currentEmail = auth.currentUser?.email?.toLowerCase();

      if (currentEmail == null) {
        return null;
      }

      return currentEmail;
    } catch (e) {
      return null;
    }
  }

  Future<String?> getUserId() async {
    try {
      final currentUserId = auth.currentUser?.uid;

      if (currentUserId == null) {
        return null;
      }

      return currentUserId;
    } catch (e) {
      return null;
    }
  }

  // ---------------- JOB SITES ----------------
  // A jobsite is a lat/lng + radius (in meters) that defines the geofence
  // employees must be inside to be considered "at work".

  Stream<QuerySnapshot<Map<String, dynamic>>> jobSitesForCompany(
    String companyName,
  ) {
    return firebase
        .collection('jobsites')
        .where('companyName', isEqualTo: companyName)
        .snapshots();
  }

  Future<void> addJobSite({
    required String companyName,
    required String name,
    required double latitude,
    required double longitude,
    required double radiusMeters,
    required String createdBy,
  }) async {
    await firebase.collection('jobsites').add({
      'companyName': companyName,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'radiusMeters': radiusMeters,
      'createdBy': createdBy,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ---------------- CLOCK RECORDS ----------------
  // A clockRecords doc represents one shift: clockInTime is set when the
  // employee enters the geofence, clockOutTime is set (by the geofence
  // watcher OR manually) when they leave / a manager adjusts it.

  /// The employee's currently open (not clocked out) record, if any.
  Stream<QuerySnapshot<Map<String, dynamic>>> activeClockRecord(String uid) {
    return firebase
        .collection('clockRecords')
        .where('uid', isEqualTo: uid)
        .where('clockOutTime', isNull: true)
        .limit(1)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> clockHistory(
    String uid, {
    int limit = 50,
  }) {
    return firebase
        .collection('clockRecords')
        .where('uid', isEqualTo: uid)
        .orderBy('clockInTime', descending: true)
        .limit(limit)
        .snapshots();
  }

  Future<DocumentReference<Map<String, dynamic>>> clockIn({
    required String uid,
    required String companyName,
    required String jobSiteId,
    required String jobSiteName,
  }) {
    return firebase.collection('clockRecords').add({
      'uid': uid,
      'companyName': companyName,
      'jobSiteId': jobSiteId,
      'jobSiteName': jobSiteName,
      'clockInTime': FieldValue.serverTimestamp(),
      'clockOutTime': null,
      'method': 'auto',
    });
  }

  Future<void> clockOut(String recordId) {
    return firebase.collection('clockRecords').doc(recordId).update({
      'clockOutTime': FieldValue.serverTimestamp(),
    });
  }

  /// Manager/employee manually logs hours that weren't auto-tracked
  /// (e.g. forgot phone, GPS was off, worked off-site paperwork, etc).
  Future<void> addManualTime({
    required String uid,
    required String companyName,
    required double hours,
    required DateTime date,
    String? note,
  }) {
    return firebase.collection('clockRecords').add({
      'uid': uid,
      'companyName': companyName,
      'jobSiteId': null,
      'jobSiteName': note ?? 'Manual entry',
      'clockInTime': Timestamp.fromDate(date),
      'clockOutTime': Timestamp.fromDate(
        date.add(Duration(minutes: (hours * 60).round())),
      ),
      'hours': hours,
      'method': 'manual',
      'note': note ?? '',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ================= construction images ===================
  Stream<QuerySnapshot>? streamJobImages(String companyId) {
    try {
      return firebase
          .collection('jobImages')
          .where('companyId', isEqualTo: companyId)
          .orderBy('createdAt', descending: true)
          .snapshots();
    } catch (e) {
      return null;
    }
  }

  // =============== jobs ==============================
  Future<Stream<QuerySnapshot<Map<String, dynamic>>>?> getCompanyJobs() async {
    try {
      final userId = await getUserId();
      if (userId == null) return null;

      final companyId = await getUsersCompanyId(userId);
      if (companyId == null) return null;

      return firebase
          .collection('jobs')
          .where('companyId', isEqualTo: companyId)
          .orderBy('createdAt', descending: true)
          .snapshots();
    } catch (e) {
      return null;
    }
  }

  // =============== employees ===================

  Stream<QuerySnapshot<Map<String, dynamic>>> streamYourEmployees() async* {
    if (currentUid == null) return;
    String? companyId = await getUsersCompanyId(currentUid!);
    if (companyId == null) return;

    yield* firebase
        .collection('users')
        .where('companyId', isEqualTo: companyId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }
}
