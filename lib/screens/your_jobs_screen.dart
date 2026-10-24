import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:contractor_hub/components/app_bar.dart';
import 'package:contractor_hub/services/firebase_services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

String? _clean(String text) {
  final t = text.trim();
  return t.isEmpty ? null : t;
}

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
    await showDialog(
      context: context,
      builder: (_) =>
          _AddJobDialog(companyId: _companyId!, uid: auth.currentUser!.uid),
    );
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

  Future<void> _openDirections(String address) async {
    final uri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': address,
    });
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not open maps: $e')));
    }
  }

  // ───────────────────────── build ─────────────────────────

  Widget _detailRow(IconData icon, String label, String? value, {Widget? trailing}) {
    final hasValue = value != null && value.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.blueGrey),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                Text(
                  hasValue ? value : 'Not set',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: hasValue ? FontWeight.w500 : FontWeight.normal,
                    color: hasValue ? null : Colors.grey[500],
                    fontStyle: hasValue ? null : FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _jobCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final name = data['name'] as String? ?? 'Unnamed site';
    final address = data['streetAddress'] as String?;
    final customer = data['customerName'] as String?;
    final permit = data['permitNumber'] as String?;
    final lat = data['latitude'] as num?;
    final lng = data['longitude'] as num?;
    final radius = data['radiusMeters'] as num?;
    final supervisor = data['supervisorName'] as String?;

    // Collapsed one-line summary.
    final summary = [
      if (customer != null && customer.isNotEmpty) customer,
      if (address != null && address.isNotEmpty) address,
    ].join(' · ');

    return Card(
      key: ValueKey(doc.id),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey<String>('job_${doc.id}'),
        leading: const Icon(Icons.location_on),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: summary.isEmpty
            ? null
            : Text(summary, maxLines: 1, overflow: TextOverflow.ellipsis),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 6),
          _detailRow(Icons.person, 'Customer', customer),
          _detailRow(
            Icons.home_work,
            'Street address',
            address,
            trailing: (address != null && address.isNotEmpty)
                ? IconButton(
                    tooltip: 'Directions',
                    icon: const Icon(Icons.directions, color: Colors.blue),
                    onPressed: () => _openDirections(address),
                  )
                : null,
          ),
          _detailRow(Icons.assignment, 'Permit number', permit),
          _detailRow(Icons.supervisor_account, 'Supervisor', supervisor),
          _detailRow(
            Icons.radar,
            'Clock-in radius',
            radius == null ? null : '${radius.toStringAsFixed(0)} m',
          ),
          if (lat != null && lng != null)
            _detailRow(
              Icons.my_location,
              'GPS center',
              '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
            ),
          if (_isBoss) ...[
            const SizedBox(height: 6),
            // Plain buttons (not a PopupMenuButton) so opening a dialog can't
            // trigger the dependents assertion.
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _editJob(doc.id, data),
                  icon: const Icon(Icons.edit, color: Colors.green),
                  label: const Text('Edit'),
                ),
                TextButton.icon(
                  onPressed: () => _deleteJob(doc.id, name),
                  icon: const Icon(Icons.delete, color: Colors.red),
                  label: const Text(
                    'Delete',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

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
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                  itemCount: docs.length,
                  itemBuilder: (context, index) => _jobCard(docs[index]),
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

// ───────────────────────── add dialog ─────────────────────────

class _AddJobDialog extends StatefulWidget {
  final String companyId;
  final String uid;
  const _AddJobDialog({required this.companyId, required this.uid});

  @override
  State<_AddJobDialog> createState() => _AddJobDialogState();
}

class _AddJobDialogState extends State<_AddJobDialog> {
  final _name = TextEditingController();
  final _customer = TextEditingController();
  final _address = TextEditingController();
  final _permit = TextEditingController();
  final _radius = TextEditingController(text: '150');
  bool _loading = false;
  String? _error;
  bool _showOpenSettings = false;

  @override
  void dispose() {
    _name.dispose();
    _customer.dispose();
    _address.dispose();
    _permit.dispose();
    _radius.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final radius = double.tryParse(_radius.text.trim());
    if (name.isEmpty || radius == null || radius <= 0) {
      setState(() {
        _error = 'Enter a valid name and radius';
        _showOpenSettings = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _showOpenSettings = false;
    });

    try {
      final position = await _getPrecisePosition();

      await FirebaseFirestore.instance.collection('jobsites').add({
        'companyId': widget.companyId,
        'name': name,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'radiusMeters': radius,
        'createdBy': widget.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'customerName': _clean(_customer.text),
        'streetAddress': _clean(_address.text),
        'permitNumber': _clean(_permit.text),
      });

      if (mounted) Navigator.pop(context);
    } on _LocationSetupException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
        _showOpenSettings = e.canOpenAppSettings;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not save jobsite: $e';
        _showOpenSettings = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add jobsite'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Jobsite name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _customer,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Customer name (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _address,
              textCapitalization: TextCapitalization.words,
              keyboardType: TextInputType.streetAddress,
              decoration: const InputDecoration(
                labelText: 'Street address (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _permit,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Permit number (optional)',
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
            const SizedBox(height: 8),
            Text(
              'This uses your current GPS location as the center of the '
              'jobsite. Stand at the site before adding it.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            if (_showOpenSettings)
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
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _save,
          child: _loading
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
  late final _customer = TextEditingController(
    text: widget.data['customerName'] as String? ?? '',
  );
  late final _address = TextEditingController(
    text: widget.data['streetAddress'] as String? ?? '',
  );
  late final _permit = TextEditingController(
    text: widget.data['permitNumber'] as String? ?? '',
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
    _customer.dispose();
    _address.dispose();
    _permit.dispose();
    _radius.dispose();
    super.dispose();
  }

  void _diffText(
    Map<String, dynamic> changes,
    String key,
    TextEditingController c,
  ) {
    final newValue = _clean(c.text);
    final oldValue = _clean((widget.data[key] as String?) ?? '');
    if (newValue != oldValue) changes[key] = newValue;
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
    _diffText(changes, 'customerName', _customer);
    _diffText(changes, 'streetAddress', _address);
    _diffText(changes, 'permitNumber', _permit);
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
              controller: _customer,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Customer name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _address,
              textCapitalization: TextCapitalization.words,
              keyboardType: TextInputType.streetAddress,
              decoration: const InputDecoration(
                labelText: 'Street address',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _permit,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Permit number',
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
                    child: Text(
                      m['name'] as String,
                      overflow: TextOverflow.ellipsis,
                    ),
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