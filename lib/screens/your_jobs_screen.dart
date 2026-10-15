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
  bool _isBoss = false;
 
  @override
  void initState() {
    super.initState();
    _loadCompany();
  }
 
  Future<void> _loadCompany() async {
    final user = await services.getUser(auth.currentUser!.uid);
    if (!mounted) return;
    setState(() {
      _companyId = user?['companyId'] as String?;
      _isBoss = user?['isEmployee'] == false;
    });
  }
 
  // ───────────────────────── add ─────────────────────────
 
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
              content: SingleChildScrollView(
                child: Column(
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
                            final position = await _getPrecisePosition();
 
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
                              errorText = 'Could not save jobsite: $e';
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
    nameController.dispose();
    radiusController.dispose();
  }
 
  // ───────────────────────── edit / delete ─────────────────────────
 
  Future<void> _editJob(String jobId, Map<String, dynamic> data) async {
    final messenger = ScaffoldMessenger.of(context);
 
    // Supervisor choices: everyone in the company except pending requests.
    List<Map<String, dynamic>> members = [];
    try {
      members = await services.companyMembers(_companyId!);
    } catch (e) {
      debugPrint('Could not load members for supervisor picker: $e');
    }
    if (!mounted) return;
 
    final changes = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _EditJobDialog(data: data, members: members),
    );
    if (changes == null || changes.isEmpty) return;
 
    try {
      await services.updateJobSite(jobId, changes);
      messenger.showSnackBar(const SnackBar(content: Text('Job updated')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not update job: $e')));
    }
  }
 
  Future<void> _deleteJob(String jobId, String name) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "$name"?'),
        content: const Text(
          'Employees will no longer be able to clock in here. Past clock '
          'records and uploaded images are kept but will no longer be linked '
          'to a job. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
 
    try {
      await services.deleteJobSite(jobId);
      messenger.showSnackBar(SnackBar(content: Text('"$name" deleted')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not delete job: $e')));
    }
  }
 
  // ───────────────────────── build ─────────────────────────
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppBarWidget(title: 'Jobs'),
      body: _companyId == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: services.jobsForCompany(_companyId!),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: Text(
                        'Error loading jobs: ${snapshot.error}',
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
                  return const Center(
                    child: Text('No jobsites yet. Tap + to add one.'),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data();
                    final name = data['name'] as String? ?? 'Unnamed site';
                    final lat = data['latitude'] as num?;
                    final lng = data['longitude'] as num?;
                    final radius = data['radiusMeters'] as num?;
                    final supervisor = data['supervisorName'] as String?;
 
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.location_on),
                        title: Text(name),
                        subtitle: Text(
                          [
                            'Radius: ${radius?.toStringAsFixed(0) ?? '?'} m',
                            if (supervisor != null) 'Supervisor: $supervisor',
                            if (lat != null && lng != null)
                              '(${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})',
                          ].join('\n'),
                        ),
                        isThreeLine: supervisor != null,
                        // Plain IconButtons (not a PopupMenuButton) so opening
                        // a dialog can't trigger the dependents assertion.
                        trailing: _isBoss
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Edit',
                                    icon: const Icon(Icons.edit,
                                        color: Colors.green),
                                    onPressed: () => _editJob(doc.id, data),
                                  ),
                                  IconButton(
                                    tooltip: 'Delete',
                                    icon: const Icon(Icons.delete,
                                        color: Colors.red),
                                    onPressed: () => _deleteJob(doc.id, name),
                                  ),
                                ],
                              )
                            : null,
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
 
// ───────────────────────── edit dialog ─────────────────────────
 
class _EditJobDialog extends StatefulWidget {
  final Map<String, dynamic> data;
  final List<Map<String, dynamic>> members; // each: {id, name}
  const _EditJobDialog({required this.data, required this.members});
 
  @override
  State<_EditJobDialog> createState() => _EditJobDialogState();
}
 
class _EditJobDialogState extends State<_EditJobDialog> {
  late final _name = TextEditingController(
    text: widget.data['name'] as String? ?? '',
  );
  late final _radius = TextEditingController(
    text: ((widget.data['radiusMeters'] as num?) ?? 150).toStringAsFixed(0),
  );
  String? _supervisorId;
  bool _moveToMyLocation = false;
  bool _saving = false;
  String? _error;
  bool _showOpenSettings = false;
 
  @override
  void initState() {
    super.initState();
    final stored = widget.data['supervisorId'] as String?;
    // A dropdown asserts if its value isn't among the items (e.g. the
    // supervisor was deleted), so only keep it if it still exists.
    if (stored != null && widget.members.any((m) => m['id'] == stored)) {
      _supervisorId = stored;
    }
  }
 
  @override
  void dispose() {
    _name.dispose();
    _radius.dispose();
    super.dispose();
  }
 
  Future<void> _save() async {
    final name = _name.text.trim();
    final radius = double.tryParse(_radius.text.trim());
    if (name.isEmpty) {
      setState(() => _error = 'Enter a job name');
      return;
    }
    if (radius == null || radius < 10 || radius > 5000) {
      setState(() => _error = 'Radius must be between 10 and 5000 meters');
      return;
    }
 
    setState(() {
      _saving = true;
      _error = null;
      _showOpenSettings = false;
    });
 
    final changes = <String, dynamic>{};
    if (name != widget.data['name']) changes['name'] = name;
    if (radius != (widget.data['radiusMeters'] as num?)?.toDouble()) {
      changes['radiusMeters'] = radius;
    }
    if (_supervisorId != widget.data['supervisorId']) {
      changes['supervisorId'] = _supervisorId;
      changes['supervisorName'] = _supervisorId == null
          ? null
          : widget.members.firstWhere((m) => m['id'] == _supervisorId)['name'];
    }
 
    try {
      if (_moveToMyLocation) {
        final pos = await _getPrecisePosition();
        changes['latitude'] = pos.latitude;
        changes['longitude'] = pos.longitude;
      }
      if (mounted) Navigator.pop(context, changes);
    } on _LocationSetupException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
        _showOpenSettings = e.canOpenAppSettings;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not get location: $e';
      });
    }
  }
 
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit job'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Job name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _radius,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Geofence radius (meters)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _supervisorId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Supervisor',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('None'),
                ),
                for (final m in widget.members)
                  DropdownMenuItem<String?>(
                    value: m['id'] as String,
                    child: Text(m['name'] as String,
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _supervisorId = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Move center to my current location'),
              subtitle: const Text('Stand at the site first'),
              value: _moveToMyLocation,
              onChanged: (v) => setState(() => _moveToMyLocation = v),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            if (_showOpenSettings)
              TextButton.icon(
                onPressed: () => Geolocator.openAppSettings(),
                icon: const Icon(Icons.settings, size: 18),
                label: const Text('Open location settings'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
 
// ───────────────────────── location helpers ─────────────────────────
 
class _LocationSetupException implements Exception {
  final String message;
  final bool canOpenAppSettings;
  const _LocationSetupException(
    this.message, {
    required this.canOpenAppSettings,
  });
}
 
/// Confirms location services are on, permission is granted, AND precise
/// (not just approximate), then returns a high-accuracy fix.
Future<Position> _getPrecisePosition() async {
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
      throw const _LocationSetupException(
        'Precise location is turned off for this app. Enable "Use precise '
        'location" in Settings, then try again.',
        canOpenAppSettings: true,
      );
    }
  }
 
  return Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
  );
}