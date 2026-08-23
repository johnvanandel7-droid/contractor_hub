import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:contractor_hub/components/go_home.dart';
import 'package:contractor_hub/components/time_ago.dart';
import 'package:contractor_hub/constants.dart';
import 'package:contractor_hub/services/firebase_services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

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

  String? _companyName;
  String? _activeRecordId;
  bool _isInsideGeofence = false;
  String _statusMessage = 'Checking location permissions...';
  List<Map<String, dynamic>> _jobSites = [];
  Map<String, dynamic>? _currentJobSite;

  String get _uid => auth.currentUser!.uid;

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
    final user = await services.getUser(_uid);
    if (user == null || !mounted) return;

    _companyName = user['companyName'] as String?;

    // Watch whether this employee already has an open shift (e.g. they
    // reopened the app while still clocked in).
    _activeRecordSub = services.activeClockRecord(_uid).listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _activeRecordId = snapshot.docs.isEmpty ? null : snapshot.docs.first.id;
      });
    });

    if (_companyName != null) {
      services.jobSitesForCompany(_companyName!).listen((snapshot) {
        if (!mounted) return;
        setState(() {
          _jobSites = snapshot.docs
              .map((d) => {'id': d.id, ...d.data()})
              .toList();
        });
      });
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
      setState(
        () => _statusMessage = 'No jobsite set up for your company yet.',
      );
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

  @override
  Widget build(BuildContext context) {
    final isClockedIn = _activeRecordId != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Clock In / Out',
          style: kLargeTextSize.copyWith(fontSize: 22),
        ),
        actions: [GoHomeButton()],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isClockedIn ? Colors.green[50] : Colors.grey[100],
                  border: Border.all(
                    color: isClockedIn ? Colors.green : Colors.grey[400]!,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(
                      isClockedIn ? Icons.check_circle : Icons.schedule,
                      size: 48,
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
                    const SizedBox(height: 8),
                    Text(
                      _statusMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _isInsideGeofence
                    ? 'Auto clock-in/out is active based on your GPS location.'
                    : 'Walk within range of a jobsite to auto clock-in.',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _openAddTimeDialog,
                icon: const Icon(Icons.add),
                label: const Text('Add time manually'),
              ),
              const SizedBox(height: 20),
              const Divider(),
              const Text(
                'Recent shifts',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: services.clockHistory(_uid),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = snapshot.data!.docs;
                    if (docs.isEmpty) {
                      return const Center(child: Text('No shifts yet'));
                    }
                    return ListView.builder(
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final data = docs[index].data();
                        final clockIn = data['clockInTime'] as Timestamp?;
                        final clockOut = data['clockOutTime'] as Timestamp?;
                        final method = data['method'] as String? ?? 'auto';
                        final siteName =
                            data['jobSiteName'] as String? ?? 'Unknown site';

                        return ListTile(
                          leading: Icon(
                            method == 'manual'
                                ? Icons.edit_note
                                : Icons.location_on,
                          ),
                          title: Text(siteName),
                          subtitle: Text(
                            clockIn == null
                                ? 'No start time'
                                : clockOut == null
                                ? 'Started ${formatTimeAgo(clockIn)} — still clocked in'
                                : 'Started ${formatTimeAgo(clockIn)}, ended ${formatTimeAgo(clockOut)}',
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
