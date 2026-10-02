import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:contractor_hub/components/app_bar.dart';
import 'package:contractor_hub/constants.dart';
import 'package:contractor_hub/services/firebase_services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class YourJobsScreen extends StatefulWidget {
  const YourJobsScreen({super.key});

  @override
  State<YourJobsScreen> createState() => _YourJobsScreenState();
}

class _YourJobsScreenState extends State<YourJobsScreen> {
  final services = FirebaseServices.instance;
  final auth = FirebaseAuth.instance;
  String? _companyId;

  @override
  void initState() {
    super.initState();
    _loadCompany();
  }

  Future<void> _loadCompany() async {
    final user = await services.getUser(auth.currentUser!.uid);
    if (mounted) setState(() => _companyId = user?['companyId'] as String?);
  }

  /// Confirms location services are on, permission is granted, AND that
  /// permission is precise (not just approximate). Android 12+ / iOS 14+
  /// let someone grant "Location" access but restrict it to approximate
  /// accuracy, which checkPermission()/requestPermission() don't surface —
  /// they only report granted vs denied, not the accuracy tier. An
  /// approximate reading can be off by a kilometer or more, which makes a
  /// geofence radius meaningless, so this is treated as a hard requirement
  /// rather than silently falling back to a low-accuracy reading.
  Future<void> _ensurePreciseLocationAccess() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const _LocationSetupException(
        'Location services are off. Turn on location for your device and try again.',
        canOpenAppSettings: false,
      );
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const _LocationSetupException(
        'Location permission was denied.',
        canOpenAppSettings: true,
      );
    }

    final accuracyStatus = await Geolocator.getLocationAccuracy();
    if (accuracyStatus == LocationAccuracyStatus.reduced) {
      if (Platform.isIOS) {
        // iOS lets an app ask, once per session, for a temporary upgrade to
        // precise location without sending the person to Settings. Requires
        // NSLocationTemporaryUsageDescriptionDictionary with this purposeKey
        // configured in Info.plist.
        final upgraded = await Geolocator.requestTemporaryFullAccuracy(
          purposeKey: 'JobSiteGeofencing',
        );
        if (upgraded != LocationAccuracyStatus.precise) {
          throw const _LocationSetupException(
            'Precise location is required to set an accurate jobsite radius.',
            canOpenAppSettings: true,
          );
        }
      } else {
        // Android has no in-app re-prompt for approximate → precise; the
        // person has to flip "Use precise location" in system settings.
        throw const _LocationSetupException(
          'Precise location is turned off for this app. Enable "Use precise '
          'location" in Settings, then try again.',
          canOpenAppSettings: true,
        );
      }
    }
  }

  Future<void> _openAddJobSiteDialog() async {
    if (_companyId == null) return;

    final nameController = TextEditingController();
    final radiusController = TextEditingController(text: '150');
    bool loadingLocation = false;
    String? errorText;
    bool showOpenSettings = false;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add jobsite'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: kInputDecoration.copyWith(
                      hintText: 'Jobsite name',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: radiusController,
                    keyboardType: TextInputType.number,
                    decoration: kInputDecoration.copyWith(
                      hintText: 'Geofence radius in meters',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This uses your current GPS location as the center of the '
                    'jobsite. Stand at the site before adding it.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  if (errorText != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        errorText!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  if (showOpenSettings)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextButton.icon(
                        onPressed: () => Geolocator.openAppSettings(),
                        icon: const Icon(Icons.settings, size: 18),
                        label: const Text('Open location settings'),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: loadingLocation
                      ? null
                      : () async {
                          final name = nameController.text.trim();
                          final radius = double.tryParse(
                            radiusController.text.trim(),
                          );
                          if (name.isEmpty || radius == null || radius <= 0) {
                            setDialogState(() {
                              errorText = 'Enter a valid name and radius';
                              showOpenSettings = false;
                            });
                            return;
                          }

                          setDialogState(() {
                            loadingLocation = true;
                            errorText = null;
                            showOpenSettings = false;
                          });

                          try {
                            await _ensurePreciseLocationAccess();

                            final position =
                                await Geolocator.getCurrentPosition(
                                  locationSettings: const LocationSettings(
                                    accuracy: LocationAccuracy.high,
                                  ),
                                );

                            await services.addJobSite(
                              companyId: _companyId!,
                              name: name,
                              latitude: position.latitude,
                              longitude: position.longitude,
                              radiusMeters: radius,
                              createdBy: auth.currentUser!.uid,
                            );

                            if (context.mounted) Navigator.pop(context);
                          } on _LocationSetupException catch (e) {
                            setDialogState(() {
                              loadingLocation = false;
                              errorText = e.message;
                              showOpenSettings = e.canOpenAppSettings;
                            });
                          } catch (e) {
                            setDialogState(() {
                              loadingLocation = false;
                              errorText = 'Could not get location: $e';
                              showOpenSettings = false;
                            });
                          }
                        },
                  child: loadingLocation
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
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
    return Scaffold(
      appBar: AppBarWidget(),
      body: _companyId == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: services.jobsForCompany(_companyId!),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return const Center(
                    child: Text('No jobsites yet. Tap + to add one.'),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.location_on),
                        title: Row(
                          children: [
                            Text(data['name'] as String? ?? 'Unnamed site'),
                            Spacer(),
                            IconButton(
                              onPressed: () {},
                              icon: Icon(Icons.delete, color: Colors.red),
                            ),
                            SizedBox(width: 3),
                            IconButton(
                              onPressed: () {
                                _editJob(
                                  context,
                                  data['name'],
                                  data['companyId'],
                                );
                              },
                              icon: Icon(Icons.edit, color: Colors.green),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          'Radius: ${data['radiusMeters']}m — '
                          '(${(data['latitude'] as num).toStringAsFixed(4)}, '
                          '${(data['longitude'] as num).toStringAsFixed(4)})',
                        ),
                      ),
                    );
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddJobSiteDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _LocationSetupException implements Exception {
  final String message;
  final bool canOpenAppSettings;
  const _LocationSetupException(
    this.message, {
    required this.canOpenAppSettings,
  });
}

void _editJob(context, String jobName, String jobId) async {
  await showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('edit $jobName job'),
      content: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Text('name'),
            SizedBox(height: 3),
            TextField(
              decoration: kInputDecoration.copyWith(
                hintText: 'John doe plumbing service',
              ),
            ),
            SizedBox(height: 15),
            Text('change job supervisor'),
          ],
        ),
      ),
    ),
  );
}
