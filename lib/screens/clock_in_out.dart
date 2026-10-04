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
 
  String? _companyId;
  String? _companyName;
  String? _activeRecordId;
  bool _isInsideGeofence = false;
  String _statusMessage = 'Checking location permissions...';
  List<Map<String, dynamic>> _jobSites = [];
  Map<String, dynamic>? _currentJobSite;
  Position? _lastPosition;
  String _uid = '';
 
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }
 
  @override
  void dispose() {
    _positionSub?.cancel();
    _activeRecordSub?.cancel();
    super.dispose();
  }
 
  Future<void> _bootstrap() async {
    final uid = auth.currentUser?.uid;
    if (uid == null || !mounted) return; // or navigate to sign-in
    _uid = uid;
 
    final user = await services.getUser(uid);
    if (user == null || !mounted) return;
 
    _companyId = user['companyId'] as String?;
    _companyName = user['companyName'] as String?;
 
    // Watch whether this employee already has an open shift (e.g. they
    // reopened the app while still clocked in).
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
            if (!mounted) {
              setState(() => _statusMessage = 'Could not load clock status');
            }
          },
        );
 
    if (_companyId != null) {
      services
          .jobsForCompany(_companyId!)
          .listen(
            (snapshot) {
              if (!mounted) return;
              setState(() {
                _jobSites = snapshot.docs
                    .map((d) => {'id': d.id, ...d.data()})
                    .toList();
              });
            },
            onError: (e) {
              debugPrint('error getting jobsites: $e');
              if (!mounted) {
                setState(() {
                  _statusMessage = 'could not load companies';
                });
              }
            },
          );
    }
 
    await _startLocationWatch();
  }
 
  Future<void> _startLocationWatch() async {
    final hasPermission = await _ensureLocationPermission();
    if (!hasPermission) {
      setState(
        () => _statusMessage =
            'Location permission is required to auto clock-in/out.',
      );
      return;
    }
 
    setState(() => _statusMessage = 'Watching your location...');
 
    // NOTE: this only tracks location while this screen is open and the
    // app is in the foreground. To auto clock-out someone who leaves the
    // jobsite and closes the app, you need a background location plugin
    // (see notes below the file).
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15, // meters of movement before a new update fires
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
    if (_jobSites.isEmpty) {
      setState(() {
        _lastPosition = position;
        _statusMessage = 'No jobsite set up for your company yet.';
      });
      return;
    }
 
    // Find the nearest jobsite and check if we're within its radius.
    Map<String, dynamic>? nearestSite;
    double nearestDistance = double.infinity;
 
    for (final site in _jobSites) {
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        site['latitude'] as double,
        site['longitude'] as double,
      );
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestSite = site;
      }
    }
 
    final radius = (nearestSite?['radiusMeters'] as num?)?.toDouble() ?? 150;
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
 
    _handleGeofenceTransition(isInside);
  }
 
  Future<void> _handleGeofenceTransition(bool isInside) async {
    // Entered the geofence and not currently clocked in -> auto clock in.
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
 
    // Left the geofence and currently clocked in -> auto clock out.
    if (!isInside && _activeRecordId != null) {
      final recordId = _activeRecordId!;
      await services.clockOut(recordId);
      if (mounted) setState(() => _activeRecordId = null);
    }
  }
 
  Future<void> _openAddTimeDialog() async {
    final hoursController = TextEditingController();
    final noteController = TextEditingController();
    DateTime selectedDate = DateTime.now();
 
    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Add time manually'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: hoursController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: kInputDecoration.copyWith(
                      hintText: 'Hours worked, e.g. 4.5',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    decoration: kInputDecoration.copyWith(
                      hintText: 'Note (optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        'Date: ${selectedDate.month}/${selectedDate.day}/${selectedDate.year}',
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setDialogState(() => selectedDate = picked);
                          }
                        },
                        child: const Text('Change'),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final hours = double.tryParse(hoursController.text.trim());
                    if (hours == null || hours <= 0) return;
 
                    await services.addManualTime(
                      uid: _uid,
                      companyName: _companyName ?? '',
                      hours: hours,
                      date: selectedDate,
                      note: noteController.text.trim().isEmpty
                          ? null
                          : noteController.text.trim(),
                    );
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }
 
  void _showJobSiteInfo(Map<String, dynamic> site) {
    final name = site['name'] as String? ?? 'Unnamed site';
    final lat = site['latitude'] as double?;
    final lng = site['longitude'] as double?;
    final pos = _lastPosition;
 
    String message = name;
    if (pos != null && lat != null && lng != null) {
      final distance = Geolocator.distanceBetween(pos.latitude, pos.longitude, lat, lng);
      message = '$name — ${distance.toStringAsFixed(0)}m away';
    }
 
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
 
  Widget _buildJobsMap() {
    final sitesWithLocation = _jobSites.where(
      (site) => site['latitude'] != null && site['longitude'] != null,
    ).toList();
 
    final points = <LatLng>[
      for (final site in sitesWithLocation)
        LatLng(site['latitude'] as double, site['longitude'] as double),
    ];
    final currentPos = _lastPosition;
    if (currentPos != null) {
      points.add(LatLng(currentPos.latitude, currentPos.longitude));
    }
 
    if (points.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
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
          point: LatLng(site['latitude'] as double, site['longitude'] as double),
          width: 36,
          height: 36,
          child: GestureDetector(
            onTap: () => _showJobSiteInfo(site),
            child: Icon(
              Icons.location_on,
              size: 34,
              color: _currentJobSite != null && _currentJobSite!['id'] == site['id']
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
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4)],
            ),
          ),
        ),
      );
    }
 
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: FlutterMap(
        options: MapOptions(
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
                  point: LatLng(site['latitude'] as double, site['longitude'] as double),
                  radius: (site['radiusMeters'] as num?)?.toDouble() ?? 150,
                  useRadiusInMeter: true,
                  color: Colors.blue.withOpacity(0.15),
                  borderColor: Colors.blue,
                  borderStrokeWidth: 1,
                ),
            ],
          ),
          MarkerLayer(markers: markers),
        ],
      ),
    );
  }
 
  @override
  Widget build(BuildContext context) {
    final isClockedIn = _activeRecordId != null;
 
    return Scaffold(
      appBar: AppBarWidget(),
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: Padding(
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
                    BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2)),
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
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
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
              OutlinedButton.icon(
                onPressed: _openAddTimeDialog,
                icon: const Icon(Icons.add),
                label: const Text('Add time manually'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Recent shifts', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 8),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = snapshot.data!.docs;
                    if (docs.isEmpty) {
                      return Center(
                        child: Text('No shifts yet', style: TextStyle(color: Colors.grey[600])),
                      );
                    }
                    return ListView.separated(
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final data = docs[index].data();
                        final clockIn = data['clockInTime'] as Timestamp?;
                        final clockOut = data['clockOutTime'] as Timestamp?;
                        final method = data['method'] as String? ?? 'auto';
                        final siteName = data['jobSiteName'] as String? ?? 'Unknown site';
 
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 1)),
                            ],
                          ),
                          child: Row(
                            children: [
                              Icon(
                                method == 'manual' ? Icons.edit_note : Icons.location_on,
                                color: Colors.blueGrey,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(siteName, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    Text(
                                      clockIn == null
                                          ? 'No start time'
                                          : clockOut == null
                                              ? 'Started ${formatTimeAgo(clockIn)} — still clocked in'
                                              : 'Started ${formatTimeAgo(clockIn)}, ended ${formatTimeAgo(clockOut)}',
                                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              const Text('Job sites', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 8),
              SizedBox(height: 220, child: _buildJobsMap()),
            ],
          ),
        ),
      ),
    );
  }
}