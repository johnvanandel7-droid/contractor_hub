import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:contractor_hub/components/app_bar.dart';
import 'package:contractor_hub/components/time_ago.dart';
import 'package:contractor_hub/constants.dart';
import 'package:contractor_hub/services/firebase_services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

double? _d(dynamic v) => v is num ? v.toDouble() : null;

String _fmtDur(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  return h > 0 ? '${h}h ${m}m' : '${m}m';
}

class ClockInOut extends StatefulWidget {
  const ClockInOut({super.key});

  @override
  State<ClockInOut> createState() => _ClockInOutState();
}

class _ClockInOutState extends State<ClockInOut> {
  final services = FirebaseServices.instance;
  final auth = FirebaseAuth.instance;

  StreamSubscription<Position>? _positionSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _activeRecordSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _jobsSub;

  String? _companyId;
  String? _companyName;
  String? _activeRecordId;
  bool _isInsideGeofence = false;
  String _statusMessage = 'Checking location permissions...';
  List<Map<String, dynamic>> _jobSites = [];
  Map<String, dynamic>? _currentJobSite;
  Position? _lastPosition;
  String _uid = '';

  bool _transitionBusy = false; // stops duplicate clock-ins from rapid GPS updates
  bool _askingEndOfDay = false; // only one "end of day?" popup at a time

  // Bumped whenever map data changes so the full-screen map redraws too.
  final ValueNotifier<int> _mapTick = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _activeRecordSub?.cancel();
    _jobsSub?.cancel();
    _mapTick.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final uid = auth.currentUser?.uid;
    if (uid == null || !mounted) return;
    _uid = uid;

    final user = await services.getUser(uid);
    if (user == null || !mounted) return;

    _companyId = user['companyId'] as String?;
    _companyName = user['companyName'] as String?;

    _activeRecordSub = services
        .activeClockRecord(uid)
        .listen(
          (snapshot) {
            if (!mounted) return;
            setState(() {
              _activeRecordId = snapshot.docs.isEmpty
                  ? null
                  : snapshot.docs.first.id;
            });
          },
          onError: (e) {
            debugPrint('activeClockRecord error: $e');
            if (mounted) {
              setState(() => _statusMessage = 'Could not load clock status');
            }
          },
        );

    if (_companyId != null) {
      _jobsSub = services
          .jobsForCompany(_companyId!)
          .listen(
            (snapshot) {
              if (!mounted) return;
              setState(() {
                _jobSites = snapshot.docs
                    .map((d) => {'id': d.id, ...d.data()})
                    .toList();
              });
              _mapTick.value++;
            },
            onError: (e) {
              debugPrint('error getting jobsites: $e');
              if (mounted) {
                setState(() => _statusMessage = 'Could not load job sites');
              }
            },
          );
    }

    await _startLocationWatch();
  }

  Future<void> _startLocationWatch() async {
    final hasPermission = await _ensureLocationPermission();
    if (!mounted) return;
    if (!hasPermission) {
      setState(
        () => _statusMessage =
            'Location permission is required to auto clock-in/out.',
      );
      return;
    }

    setState(() => _statusMessage = 'Watching your location...');

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
      ),
    ).listen(_onPositionUpdate);
  }

  Future<bool> _ensureLocationPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  void _onPositionUpdate(Position position) {
    if (!mounted) return;
    if (_jobSites.isEmpty) {
      setState(() {
        _lastPosition = position;
        _statusMessage = 'No jobsite set up for your company yet.';
      });
      _mapTick.value++;
      return;
    }

    Map<String, dynamic>? nearestSite;
    double nearestDistance = double.infinity;

    for (final site in _jobSites) {
      final lat = _d(site['latitude']);
      final lng = _d(site['longitude']);
      if (lat == null || lng == null) continue;
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        lat,
        lng,
      );
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestSite = site;
      }
    }

    final radius = _d(nearestSite?['radiusMeters']) ?? 150;
    final isInside = nearestSite != null && nearestDistance <= radius;

    setState(() {
      _lastPosition = position;
      _currentJobSite = nearestSite;
      _isInsideGeofence = isInside;
      _statusMessage = isInside
          ? 'Inside ${nearestSite!['name']} (${nearestDistance.toStringAsFixed(0)}m from center)'
          : nearestSite == null
          ? 'No jobsite nearby'
          : '${nearestDistance.toStringAsFixed(0)}m from ${nearestSite['name']}';
    });
    _mapTick.value++;

    _handleGeofenceTransition(isInside);
  }

  Future<void> _handleGeofenceTransition(bool isInside) async {
    if (_transitionBusy) return;
    _transitionBusy = true;
    try {
      // Entered a job site and not clocked in -> auto clock in.
      if (isInside && _activeRecordId == null && _currentJobSite != null) {
        final ref = await services.clockIn(
          uid: _uid,
          companyName: _companyName ?? '',
          jobSiteId: _currentJobSite!['id'] as String,
          jobSiteName: _currentJobSite!['name'] as String,
        );
        if (mounted) setState(() => _activeRecordId = ref.id);
        return;
      }

      // Left the job site while clocked in -> auto clock out, then ask
      // whether that's the end of the day.
      if (!isInside && _activeRecordId != null) {
        final recordId = _activeRecordId!;
        await services.clockOut(recordId);
        if (mounted) {
          setState(() => _activeRecordId = null);
          _askEndOfDay();
        }
      }
    } catch (e) {
      debugPrint('geofence transition failed: $e');
    } finally {
      _transitionBusy = false;
    }
  }

  // ---------------------------------------------------------------------
  // End of day
  // ---------------------------------------------------------------------

  Future<void> _askEndOfDay({bool skipQuestion = false}) async {
    if (_askingEndOfDay || !mounted) return;
    _askingEndOfDay = true;
    try {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _EndOfDaySheet(
          uid: _uid,
          jobSites: _jobSites,
          skipQuestion: skipQuestion,
        ),
      );
    } finally {
      _askingEndOfDay = false;
    }
  }

  // ---------------------------------------------------------------------
  // Edit / delete a shift
  // ---------------------------------------------------------------------

  Future<void> _editShift(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    await showDialog(
      context: context,
      builder: (_) => _EditShiftDialog(
        docRef: doc.reference,
        data: doc.data(),
        jobSites: _jobSites,
      ),
    );
  }

  Future<void> _deleteShift(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    final site = data['jobSiteName'] as String? ?? 'this shift';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete this shift?'),
        content: Text('The time recorded at $site will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await doc.reference.delete();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not delete: $e')));
    }
  }

  // ---------------------------------------------------------------------
  // Manual time
  // ---------------------------------------------------------------------

  Future<void> _openManualTime() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ManualTimePage(
          uid: _uid,
          companyName: _companyName ?? '',
          jobSites: _jobSites,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Map
  // ---------------------------------------------------------------------

  void _showJobSiteInfo(Map<String, dynamic> site) {
    final name = site['name'] as String? ?? 'Unnamed site';
    final lat = _d(site['latitude']);
    final lng = _d(site['longitude']);
    final pos = _lastPosition;

    String message = name;
    if (pos != null && lat != null && lng != null) {
      final distance = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        lat,
        lng,
      );
      message = '$name — ${distance.toStringAsFixed(0)}m away';
    }

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openFullScreenMap() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (routeContext) => Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: ValueListenableBuilder<int>(
                  valueListenable: _mapTick,
                  builder: (_, __, ___) => _buildJobsMap(fullScreen: true),
                ),
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: _mapButton(
                    icon: Icons.fullscreen_exit,
                    tooltip: 'Close full screen',
                    onPressed: () => Navigator.of(routeContext).pop(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mapButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Material(
        color: Colors.white,
        elevation: 3,
        shape: const CircleBorder(),
        child: IconButton(
          icon: Icon(icon),
          tooltip: tooltip,
          onPressed: onPressed,
        ),
      ),
    );
  }

  Widget _buildJobsMap({bool fullScreen = false}) {
    final sitesWithLocation = _jobSites
        .where((s) => _d(s['latitude']) != null && _d(s['longitude']) != null)
        .toList();

    final points = <LatLng>[
      for (final site in sitesWithLocation)
        LatLng(_d(site['latitude'])!, _d(site['longitude'])!),
    ];
    final currentPos = _lastPosition;
    if (currentPos != null) {
      points.add(LatLng(currentPos.latitude, currentPos.longitude));
    }

    if (points.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(fullScreen ? 0 : 12),
        ),
        child: Center(
          child: Text(
            'No jobsite locations to show yet',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ),
      );
    }

    final markers = <Marker>[
      for (final site in sitesWithLocation)
        Marker(
          point: LatLng(_d(site['latitude'])!, _d(site['longitude'])!),
          width: 36,
          height: 36,
          child: GestureDetector(
            onTap: () => _showJobSiteInfo(site),
            child: Icon(
              Icons.location_on,
              size: 34,
              color:
                  _currentJobSite != null && _currentJobSite!['id'] == site['id']
                  ? (_isInsideGeofence ? Colors.green : Colors.orange)
                  : Colors.blue,
            ),
          ),
        ),
    ];

    if (currentPos != null) {
      markers.add(
        Marker(
          point: LatLng(currentPos.latitude, currentPos.longitude),
          width: 20,
          height: 20,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.blue,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4),
              ],
            ),
          ),
        ),
      );
    }

    final map = FlutterMap(
      options: MapOptions(
        interactionOptions: InteractionOptions(
          flags: fullScreen ? InteractiveFlag.all : InteractiveFlag.none,
        ),
        initialCenter: points.first,
        initialZoom: points.length > 1 ? 13 : 15,
        initialCameraFit: points.length > 1
            ? CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(points),
                padding: const EdgeInsets.all(40),
              )
            : null,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.contractorhub.app',
        ),
        CircleLayer(
          circles: [
            for (final site in sitesWithLocation)
              CircleMarker(
                point: LatLng(_d(site['latitude'])!, _d(site['longitude'])!),
                radius: _d(site['radiusMeters']) ?? 150,
                useRadiusInMeter: true,
                color: Colors.blue.withOpacity(0.15),
                borderColor: Colors.blue,
                borderStrokeWidth: 1,
              ),
          ],
        ),
        MarkerLayer(markers: markers),
      ],
    );

    return fullScreen
        ? map
        : ClipRRect(borderRadius: BorderRadius.circular(12), child: map);
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isClockedIn = _activeRecordId != null;

    return Scaffold(
      appBar: AppBarWidget(),
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isClockedIn ? Colors.green[50] : Colors.white,
                  border: Border.all(
                    color: isClockedIn ? Colors.green : Colors.grey[300]!,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Icon(
                      isClockedIn ? Icons.check_circle : Icons.schedule,
                      size: 44,
                      color: isClockedIn ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isClockedIn ? 'Clocked In' : 'Clocked Out',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _statusMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _isInsideGeofence
                    ? 'Auto clock-in/out is active based on your GPS location.'
                    : 'Walk within range of a jobsite to auto clock-in.',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _openManualTime,
                      icon: const Icon(Icons.add),
                      label: const Text('Add time'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _askEndOfDay(skipQuestion: true),
                      icon: const Icon(Icons.summarize),
                      label: const Text('Day summary'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Recent shifts',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              const SizedBox(height: 8),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: services.clockHistory(_uid),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Error loading shifts: ${snapshot.error}',
                            style: const TextStyle(color: Colors.red),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final docs = snapshot.data!.docs;
                    if (docs.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            'No shifts yet',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final doc = docs[index];
                        final data = doc.data();
                        final clockIn = data['clockInTime'] as Timestamp?;
                        final clockOut = data['clockOutTime'] as Timestamp?;
                        final method = data['method'] as String? ?? 'auto';
                        final siteName =
                            data['jobSiteName'] as String? ?? 'Unknown site';
                        final note = (data['note'] as String?)?.trim() ?? '';

                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Icon(
                                method == 'manual'
                                    ? Icons.edit_note
                                    : Icons.location_on,
                                color: Colors.blueGrey,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      siteName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      clockIn == null
                                          ? 'No start time'
                                          : clockOut == null
                                          ? 'Started ${formatTimeAgo(clockIn)} — still clocked in'
                                          : 'Started ${formatTimeAgo(clockIn)}, ended ${formatTimeAgo(clockOut)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    if (note.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          note,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[800],
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Edit',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.edit, size: 20),
                                color: Colors.grey[600],
                                onPressed: () => _editShift(doc),
                              ),
                              IconButton(
                                tooltip: 'Delete',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.delete, size: 20),
                                color: Colors.red,
                                onPressed: () => _deleteShift(doc),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              const SizedBox(height: 14),
              const Text(
                'Job sites',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 200,
                child: Stack(
                  children: [
                    Positioned.fill(child: _buildJobsMap()),
                    Align(
                      alignment: Alignment.topRight,
                      child: _mapButton(
                        icon: Icons.fullscreen,
                        tooltip: 'Expand map',
                        onPressed: _openFullScreenMap,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =========================================================================
// End-of-day sheet
// =========================================================================

class _Visit {
  final String id;
  final String? siteId;
  final String siteName;
  final DateTime start;
  final DateTime? end; // null = still clocked in
  final String note;
  _Visit({
    required this.id,
    required this.siteId,
    required this.siteName,
    required this.start,
    required this.end,
    required this.note,
  });

  Duration get duration => (end ?? DateTime.now()).difference(start);
}

enum _EodPage { question, summary, notes }

class _EndOfDaySheet extends StatefulWidget {
  final String uid;
  final List<Map<String, dynamic>> jobSites;
  final bool skipQuestion;
  const _EndOfDaySheet({
    required this.uid,
    required this.jobSites,
    required this.skipQuestion,
  });

  @override
  State<_EndOfDaySheet> createState() => _EndOfDaySheetState();
}

class _EndOfDaySheetState extends State<_EndOfDaySheet> {
  late _EodPage _page = widget.skipQuestion
      ? _EodPage.summary
      : _EodPage.question;

  List<_Visit>? _visits;
  String? _error;
  bool _saving = false;

  // One note field per distinct job, keyed by site key.
  final Map<String, TextEditingController> _noteControllers = {};
  final Map<String, String> _siteNames = {};
  final Map<String, _Visit> _lastVisitBySite = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _noteControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _key(_Visit v) => v.siteId ?? v.siteName;

  Future<void> _load() async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final snap = await FirebaseFirestore.instance
          .collection('clockRecords')
          .where('uid', isEqualTo: widget.uid)
          .where(
            'clockInTime',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
          )
          .orderBy('clockInTime')
          .get();

      final visits = <_Visit>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        final start = (data['clockInTime'] as Timestamp?)?.toDate();
        if (start == null) continue;
        visits.add(
          _Visit(
            id: doc.id,
            siteId: data['jobSiteId'] as String?,
            siteName: (data['jobSiteName'] as String?) ?? 'Unknown site',
            start: start,
            end: (data['clockOutTime'] as Timestamp?)?.toDate(),
            note: (data['note'] as String?) ?? '',
          ),
        );
      }

      for (final v in visits) {
        _siteNames[_key(v)] = v.siteName;
        _lastVisitBySite[_key(v)] = v; // chronological, so last one wins
      }
      for (final entry in _lastVisitBySite.entries) {
        _noteControllers[entry.key] = TextEditingController(
          text: entry.value.note,
        );
      }

      if (!mounted) return;
      setState(() => _visits = visits);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load today: $e');
    }
  }

  /// Rough driving estimate: straight-line distance between consecutive
  /// different job sites, +25% to approximate roads. Returns km.
  double _estimatedDrivingKm(List<_Visit> visits) {
    final coords = <String, LatLng>{};
    for (final s in widget.jobSites) {
      final lat = _d(s['latitude']);
      final lng = _d(s['longitude']);
      if (lat != null && lng != null) coords[s['id'] as String] = LatLng(lat, lng);
    }

    double meters = 0;
    _Visit? prev;
    for (final v in visits) {
      if (prev != null &&
          prev.siteId != null &&
          v.siteId != null &&
          prev.siteId != v.siteId) {
        final a = coords[prev.siteId];
        final b = coords[v.siteId];
        if (a != null && b != null) {
          meters += Geolocator.distanceBetween(
            a.latitude,
            a.longitude,
            b.latitude,
            b.longitude,
          );
        }
      }
      prev = v;
    }
    return meters * 1.25 / 1000;
  }

  String _time(DateTime t) => TimeOfDay.fromDateTime(t).format(context);

  Future<void> _saveNotes() async {
    setState(() => _saving = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final entry in _noteControllers.entries) {
        final visit = _lastVisitBySite[entry.key];
        if (visit == null) continue;
        final text = entry.value.text.trim();
        if (text == visit.note.trim()) continue;
        batch.update(
          FirebaseFirestore.instance.collection('clockRecords').doc(visit.id),
          {'note': text.isEmpty ? null : text},
        );
      }
      await batch.commit();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('Notes saved')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save notes: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: switch (_page) {
          _EodPage.question => _buildQuestion(),
          _EodPage.summary => _buildSummary(),
          _EodPage.notes => _buildNotes(),
        },
      ),
    );
  }

  Widget _buildQuestion() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.logout, size: 40, color: Colors.blue),
        const SizedBox(height: 12),
        const Text(
          'You left the job site',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          'Is that the end of your day?',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: () => setState(() => _page = _EodPage.summary),
          child: const Text('Yes, end of day'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: () => Navigator.pop(context),
          child: const Text('No, heading to another job'),
        ),
      ],
    );
  }

  Widget _buildSummary() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(_error!, style: const TextStyle(color: Colors.red)),
      );
    }
    final visits = _visits;
    if (visits == null) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (visits.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No time recorded today yet.'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    }

    final total = visits.fold<Duration>(Duration.zero, (a, v) => a + v.duration);
    final km = _estimatedDrivingKm(visits);
    final jobCount = _lastVisitBySite.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Your day',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          '$jobCount job${jobCount == 1 ? '' : 's'} · ${_fmtDur(total)} worked',
          style: TextStyle(color: Colors.grey[700]),
        ),
        const SizedBox(height: 12),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: visits.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final v = visits[i];
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.location_on, color: Colors.blueGrey),
                title: Text(
                  v.siteName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${_time(v.start)} – ${v.end == null ? 'now' : _time(v.end!)}',
                ),
                trailing: Text(
                  _fmtDur(v.duration),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(Icons.directions_car, color: Colors.blue),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      km > 0
                          ? 'Driving between jobs: about ${km.toStringAsFixed(1)} km'
                          : 'No driving between jobs today',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'Estimate from the distance between job sites. Log exact '
                      'odometer readings in the Mileage Tracker.',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Want to add a note for any of these jobs?',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(46),
          ),
          onPressed: () => setState(() => _page = _EodPage.notes),
          child: const Text('Add notes'),
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('No thanks, done'),
        ),
      ],
    );
  }

  Widget _buildNotes() {
    final keys = _noteControllers.keys.toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Notes for today',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Leave a job blank to skip it.',
          style: TextStyle(color: Colors.grey[700]),
        ),
        const SizedBox(height: 10),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: keys.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              final k = keys[i];
              return TextField(
                controller: _noteControllers[k],
                maxLines: 3,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: kInputDecoration.copyWith(
                  labelText: _siteNames[k] ?? 'Job',
                  hintText: 'What happened at this job?',
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _saving
                    ? null
                    : () => setState(() => _page = _EodPage.summary),
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                onPressed: _saving ? null : _saveNotes,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save notes'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// =========================================================================
// Manual time entry (multiple job segments in one day)
// =========================================================================

class _Segment {
  String? siteId; // null until chosen; '_other' = no specific job
  TimeOfDay start;
  TimeOfDay end;
  final TextEditingController note = TextEditingController();
  _Segment({this.siteId, required this.start, required this.end});

  void dispose() => note.dispose();
}

class _ManualTimePage extends StatefulWidget {
  final String uid;
  final String companyName;
  final List<Map<String, dynamic>> jobSites;
  const _ManualTimePage({
    required this.uid,
    required this.companyName,
    required this.jobSites,
  });

  @override
  State<_ManualTimePage> createState() => _ManualTimePageState();
}

class _ManualTimePageState extends State<_ManualTimePage> {
  static const _other = '_other';

  DateTime _date = DateTime.now();
  final List<_Segment> _segments = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _segments.add(
      _Segment(
        start: const TimeOfDay(hour: 7, minute: 0),
        end: const TimeOfDay(hour: 9, minute: 0),
      ),
    );
  }

  @override
  void dispose() {
    for (final s in _segments) {
      s.dispose();
    }
    super.dispose();
  }

  int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;

  Duration _segDuration(_Segment s) {
    final diff = _minutes(s.end) - _minutes(s.start);
    return Duration(minutes: diff > 0 ? diff : 0);
  }

  Duration get _total =>
      _segments.fold(Duration.zero, (a, s) => a + _segDuration(s));

  void _addSegment() {
    final last = _segments.isEmpty ? null : _segments.last;
    final start = last?.end ?? const TimeOfDay(hour: 7, minute: 0);
    final endMin = (_minutes(start) + 60).clamp(0, 23 * 60 + 59);
    setState(
      () => _segments.add(
        _Segment(
          start: start,
          end: TimeOfDay(hour: endMin ~/ 60, minute: endMin % 60),
        ),
      ),
    );
  }

  Future<void> _pickTime(_Segment s, {required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? s.start : s.end,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        s.start = picked;
      } else {
        s.end = picked;
      }
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  String _siteName(String id) {
    if (id == _other) return 'Other / no specific job';
    final site = widget.jobSites.firstWhere(
      (s) => s['id'] == id,
      orElse: () => {'name': 'Unknown site'},
    );
    return (site['name'] as String?) ?? 'Unnamed job';
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _save() async {
    for (var i = 0; i < _segments.length; i++) {
      final s = _segments[i];
      if (s.siteId == null) {
        _toast('Choose a job for segment ${i + 1}');
        return;
      }
      if (_minutes(s.end) <= _minutes(s.start)) {
        _toast('Segment ${i + 1}: end time must be after start time');
        return;
      }
    }
    // No overlapping segments.
    final sorted = [..._segments]
      ..sort((a, b) => _minutes(a.start).compareTo(_minutes(b.start)));
    for (var i = 1; i < sorted.length; i++) {
      if (_minutes(sorted[i].start) < _minutes(sorted[i - 1].end)) {
        _toast('Two segments overlap - adjust the times');
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      for (final s in _segments) {
        final start = DateTime(
          _date.year,
          _date.month,
          _date.day,
          s.start.hour,
          s.start.minute,
        );
        final end = DateTime(
          _date.year,
          _date.month,
          _date.day,
          s.end.hour,
          s.end.minute,
        );
        final note = s.note.text.trim();
        batch.set(db.collection('clockRecords').doc(), {
          'uid': widget.uid,
          'companyName': widget.companyName,
          'jobSiteId': s.siteId == _other ? null : s.siteId,
          'jobSiteName': _siteName(s.siteId!),
          'clockInTime': Timestamp.fromDate(start),
          'clockOutTime': Timestamp.fromDate(end),
          'method': 'manual',
          'note': note.isEmpty ? null : note,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final summary =
          'Added ${_fmtDur(_total)} across ${_segments.length} '
          'segment${_segments.length == 1 ? '' : 's'}';
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text(summary)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Could not save: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add time manually')),
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(
                      'Date: ${_date.month}/${_date.day}/${_date.year}',
                    ),
                    style: OutlinedButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (var i = 0; i < _segments.length; i++)
                    _segmentCard(i, _segments[i]),
                  OutlinedButton.icon(
                    onPressed: _addSegment,
                    icon: const Icon(Icons.add),
                    label: const Text('Add another job'),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Total: ${_fmtDur(_total)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(120, 46),
                    ),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _segmentCard(int index, _Segment s) {
    return Container(
      key: ObjectKey(s),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Job ${index + 1}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              Text(
                _fmtDur(_segDuration(s)),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.blue,
                ),
              ),
              if (_segments.length > 1)
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () {
                    // Remove from the list now, dispose after the frame so the
                    // outgoing TextField isn't still listening to the controller.
                    final removed = _segments.removeAt(index);
                    setState(() {});
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => removed.dispose(),
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Job',
              border: OutlineInputBorder(),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: s.siteId,
                isExpanded: true,
                hint: const Text('Select a job'),
                items: [
                  for (final site in widget.jobSites)
                    DropdownMenuItem<String>(
                      value: site['id'] as String,
                      child: Text((site['name'] as String?) ?? 'Unnamed job'),
                    ),
                  const DropdownMenuItem<String>(
                    value: _other,
                    child: Text('Other / no specific job'),
                  ),
                ],
                onChanged: (v) => setState(() => s.siteId = v),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickTime(s, isStart: true),
                  icon: const Icon(Icons.login, size: 18),
                  label: Text('Start ${s.start.format(context)}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickTime(s, isStart: false),
                  icon: const Icon(Icons.logout, size: 18),
                  label: Text('End ${s.end.format(context)}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: s.note,
            maxLines: 2,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: kInputDecoration.copyWith(
              labelText: 'Note (optional)',
              hintText: 'What did you do here?',
            ),
          ),
        ],
      ),
    );
  }
}


// =========================================================================
// Edit a recorded shift
// =========================================================================

class _EditShiftDialog extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> docRef;
  final Map<String, dynamic> data;
  final List<Map<String, dynamic>> jobSites;
  const _EditShiftDialog({
    required this.docRef,
    required this.data,
    required this.jobSites,
  });

  @override
  State<_EditShiftDialog> createState() => _EditShiftDialogState();
}

class _EditShiftDialogState extends State<_EditShiftDialog> {
  static const _other = '_other';

  late String _siteValue;
  late DateTime _start;
  DateTime? _end;
  late final TextEditingController _note;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final id = widget.data['jobSiteId'] as String?;
    final known = id != null && widget.jobSites.any((s) => s['id'] == id);
    _siteValue = known ? id : _other;
    _start =
        (widget.data['clockInTime'] as Timestamp?)?.toDate() ?? DateTime.now();
    _end = (widget.data['clockOutTime'] as Timestamp?)?.toDate();
    _note = TextEditingController(text: (widget.data['note'] as String?) ?? '');
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String _fmt(DateTime t) =>
      '${t.month}/${t.day}/${t.year}  ${TimeOfDay.fromDateTime(t).format(context)}';

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  String get _siteName {
    if (_siteValue == _other) {
      return (widget.data['jobSiteName'] as String?) ?? 'Other / no specific job';
    }
    final site = widget.jobSites.firstWhere((s) => s['id'] == _siteValue);
    return (site['name'] as String?) ?? 'Unnamed job';
  }

  Future<void> _save() async {
    if (_end != null && !_end!.isAfter(_start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be after start time')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final note = _note.text.trim();
      await widget.docRef.update({
        'jobSiteId': _siteValue == _other ? null : _siteValue,
        'jobSiteName': _siteName,
        'clockInTime': Timestamp.fromDate(_start),
        'clockOutTime': _end == null ? null : Timestamp.fromDate(_end!),
        'note': note.isEmpty ? null : note,
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final storedName = (widget.data['jobSiteName'] as String?) ?? 'Other';
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Edit shift'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Job',
                border: OutlineInputBorder(),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _siteValue,
                  isExpanded: true,
                  items: [
                    for (final site in widget.jobSites)
                      DropdownMenuItem<String>(
                        value: site['id'] as String,
                        child: Text((site['name'] as String?) ?? 'Unnamed job'),
                      ),
                    DropdownMenuItem<String>(
                      value: _other,
                      child: Text(
                        widget.data['jobSiteId'] == null ||
                                widget.jobSites.any(
                                  (s) => s['id'] == widget.data['jobSiteId'],
                                )
                            ? 'Other / no specific job'
                            : storedName,
                      ),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _siteValue = v);
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.login, size: 18),
              label: Text('Start: ${_fmt(_start)}'),
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
              ),
              onPressed: () async {
                final picked = await _pickDateTime(_start);
                if (picked != null && mounted) setState(() => _start = picked);
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.logout, size: 18),
              label: Text(
                _end == null ? 'End: still clocked in (tap to set)' : 'End: ${_fmt(_end!)}',
              ),
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
              ),
              onPressed: () async {
                final picked = await _pickDateTime(_end ?? DateTime.now());
                if (picked != null && mounted) setState(() => _end = picked);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLines: 3,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: kInputDecoration.copyWith(labelText: 'Note'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}