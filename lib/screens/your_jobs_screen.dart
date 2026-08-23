import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:contractor_hub/components/go_home.dart';
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
  String? _companyName;

  @override
  void initState() {
    super.initState();
    _loadCompany();
  }

  Future<void> _loadCompany() async {
    final user = await services.getUser(auth.currentUser!.uid);
    if (mounted) setState(() => _companyName = user?['companyName'] as String?);
  }

  Future<void> _openAddJobSiteDialog() async {
    if (_companyName == null) return;

    final nameController = TextEditingController();
    final radiusController = TextEditingController(text: '150');
    bool loadingLocation = false;
    String? errorText;

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
                            setDialogState(
                              () => errorText = 'Enter a valid name and radius',
                            );
                            return;
                          }

                          setDialogState(() {
                            loadingLocation = true;
                            errorText = null;
                          });

                          try {
                            if (!await Geolocator.isLocationServiceEnabled()) {
                              throw Exception('Location services are off');
                            }
                            LocationPermission permission =
                                await Geolocator.checkPermission();
                            if (permission == LocationPermission.denied) {
                              permission = await Geolocator.requestPermission();
                            }
                            if (permission == LocationPermission.denied ||
                                permission ==
                                    LocationPermission.deniedForever) {
                              throw Exception('Location permission denied');
                            }

                            final position =
                                await Geolocator.getCurrentPosition(
                                  locationSettings: const LocationSettings(
                                    accuracy: LocationAccuracy.high,
                                  ),
                                );

                            await services.addJobSite(
                              companyName: _companyName!,
                              name: name,
                              latitude: position.latitude,
                              longitude: position.longitude,
                              radiusMeters: radius,
                              createdBy: auth.currentUser!.uid,
                            );

                            if (context.mounted) Navigator.pop(context);
                          } catch (e) {
                            setDialogState(() {
                              loadingLocation = false;
                              errorText = 'Could not get location: $e';
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
      appBar: AppBar(
        title: Text('Your Jobs', style: kLargeTextSize.copyWith(fontSize: 22)),
        actions: [GoHomeButton()],
      ),
      body: _companyName == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: services.jobSitesForCompany(_companyName!),
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
                        title: Text(data['name'] as String? ?? 'Unnamed site'),
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
