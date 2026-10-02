import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:contractor_hub/components/app_bar.dart';
import 'package:contractor_hub/constants.dart';
import 'package:contractor_hub/services/firebase_services.dart';
import 'package:flutter/material.dart';

final services = FirebaseServices.instance;
final firestore = FirebaseFirestore.instance;

class MileageTracker extends StatefulWidget {
  const MileageTracker({super.key});

  @override
  State<MileageTracker> createState() => _MileageTrackerState();
}

class _MileageTrackerState extends State<MileageTracker> {
  Stream<QuerySnapshot<Map<String, dynamic>>>? _jobsStream;
  bool _loadingJobs = true;
  String? _companyId;

  String? selectedJobId;
  DateTime selectedDate = DateTime.now();
  final TextEditingController startOdometerController = TextEditingController();
  final TextEditingController endOdometerController = TextEditingController();
  final TextEditingController noteController = TextEditingController();

  bool isPersonal = false;
  bool isReimbursable = false;
  bool isBillable = false;
  bool _submitting = false;

  int? get _startOdometer => int.tryParse(startOdometerController.text.trim());
  int? get _endOdometer => int.tryParse(endOdometerController.text.trim());
  int get _totalKms {
    final start = _startOdometer;
    final end = _endOdometer;
    if (start == null || end == null || end < start) return 0;
    return end - start;
  }

  @override
  void initState() {
    super.initState();
    _loadJobsStream();
  }

  Future<void> _loadJobsStream() async {
    final userId = services.currentUid;
    if (userId == null) {
      setState(() => _loadingJobs = false);
      return;
    }

    final companyId = await services.getUsersCompanyId(userId);
    if (!mounted) return;

    setState(() {
      _companyId = companyId;
      _jobsStream = companyId == null
          ? null
          : services.jobsForCompany(companyId);
      _loadingJobs = false;
    });
  }

  @override
  void dispose() {
    startOdometerController.dispose();
    endOdometerController.dispose();
    noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      initialDate: selectedDate,
    );
    if (picked != null) setState(() => selectedDate = picked);
  }

  Future<void> _submitTravelLog() async {
    if (_companyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not determine your company')),
      );
      return;
    }
    final start = _startOdometer;
    final end = _endOdometer;
    if (start == null || end == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter both a start and end odometer reading'),
        ),
      );
      return;
    }
    if (end <= start) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('End odometer must be greater than start odometer'),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await firestore.collection('TravelLogs').add({
        'companyId': _companyId,
        'createdBy': services.currentUid,
        'createdAt': FieldValue.serverTimestamp(),
        'jobId': selectedJobId,
        'date': Timestamp.fromDate(selectedDate),
        'startOdometer': start,
        'endOdometer': end,
        'totalKms': end - start,
        'note': noteController.text.trim(),
        'isPersonal': isPersonal,
        'isReimbursable': isReimbursable,
        'isBillable': isBillable,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Travel log added')));
      setState(() {
        selectedJobId = null;
        selectedDate = DateTime.now();
        startOdometerController.clear();
        endOdometerController.clear();
        noteController.clear();
        isPersonal = false;
        isReimbursable = false;
        isBillable = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save travel log: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _buildJobDropdown() {
    if (_loadingJobs) {
      return const SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    final jobsStream = _jobsStream;
    if (jobsStream == null) {
      return const Text('Could not load jobs');
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: jobsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        }
        if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Text('No jobs found');
        }

        return InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Job (optional)',
            border: OutlineInputBorder(),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selectedJobId,
              isExpanded: true,
              hint: const Text('Select a job'),
              items: docs.map((doc) {
                final jobName = doc.data()['name'] as String? ?? 'Unnamed job';
                return DropdownMenuItem<String>(
                  value: doc.id,
                  child: Text(jobName),
                );
              }).toList(),
              onChanged: (value) => setState(() => selectedJobId = value),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTripTypeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Trip type', style: TextStyle(fontWeight: FontWeight.w600)),
        // Reimbursable and Personal are mutually exclusive — checking one
        // clears the other. Billable is independent and can coexist with
        // either.
        CheckboxListTile(
          value: isReimbursable,
          title: const Text('Reimbursable'),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
          onChanged: (value) {
            setState(() {
              isReimbursable = value ?? false;
              if (isReimbursable) isPersonal = false;
            });
          },
        ),
        CheckboxListTile(
          value: isPersonal,
          title: const Text('Personal'),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
          onChanged: (value) {
            setState(() {
              isPersonal = value ?? false;
              if (isPersonal) isReimbursable = false;
            });
          },
        ),
        CheckboxListTile(
          value: isBillable,
          title: const Text('Billable'),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
          onChanged: (value) => setState(() => isBillable = value ?? false),
        ),
      ],
    );
  }

  Widget _buildCreateCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: const [
              Icon(Icons.directions_car, color: Colors.green),
              SizedBox(width: 8),
              Text(
                'New Travel Log',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildJobDropdown(),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today, size: 18),
            label: Text(
              '${selectedDate.month}/${selectedDate.day}/${selectedDate.year}',
            ),
            style: OutlinedButton.styleFrom(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: startOdometerController,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: kInputDecoration.copyWith(
              labelText: 'Start odometer',
              hintText: 'e.g. 48213',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: endOdometerController,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: kInputDecoration.copyWith(
              labelText: 'End odometer',
              hintText: 'e.g. 48260',
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Total: $_totalKms km',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: noteController,
            maxLines: 2,
            decoration: kInputDecoration.copyWith(
              labelText: 'Notes',
              hintText: 'e.g. supply run to the hardware store',
            ),
          ),
          const SizedBox(height: 10),
          _buildTripTypeSection(),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: _submitting ? null : _submitTravelLog,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: _submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBarWidget(),
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildCreateCard(),
              const SizedBox(height: 24),
              Row(
                children: const [
                  Icon(Icons.history, size: 20, color: Colors.blueGrey),
                  SizedBox(width: 6),
                  Text(
                    'Past Travel Logs',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_companyId == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    _loadingJobs
                        ? 'Loading…'
                        : 'Could not determine your company',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                )
              else
                DisplayTravelLogs(companyId: _companyId!),
            ],
          ),
        ),
      ),
    );
  }
}

enum _TravelLogSortBy { date, job, totalKms }

class DisplayTravelLogs extends StatefulWidget {
  final String companyId;
  const DisplayTravelLogs({super.key, required this.companyId});

  @override
  State<DisplayTravelLogs> createState() => _DisplayTravelLogsState();
}

class _DisplayTravelLogsState extends State<DisplayTravelLogs> {
  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';
  _TravelLogSortBy _sortBy = _TravelLogSortBy.date;
  bool _ascending = false; // newest first by default

  // Job names resolved once up front instead of per-tile.
  Map<String, String> _jobNames = {};
  bool _loadingJobNames = true;

  @override
  void initState() {
    super.initState();
    _loadJobNames();
    _searchController.addListener(() {
      setState(() => _searchText = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadJobNames() async {
    try {
      final snapshot = await services.jobsForCompany(widget.companyId).first;
      if (!mounted) return;
      setState(() {
        _jobNames = {
          for (final doc in snapshot.docs)
            doc.id: (doc.data()['name'] as String? ?? 'Unnamed job'),
        };
        _loadingJobNames = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loadingJobNames = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: firestore
          .collection('TravelLogs')
          .where('companyId', isEqualTo: widget.companyId)
          .orderBy('date', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting ||
            _loadingJobNames) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Error loading travel logs: ${snapshot.error}'),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        var entries = <_TravelLogEntry>[];

        for (final doc in docs) {
          try {
            final data = doc.data();
            final jobId = data['jobId'] as String?;
            entries.add(
              _TravelLogEntry(
                id: doc.id,
                jobId: jobId,
                jobName: jobId == null
                    ? 'No job'
                    : (_jobNames[jobId] ?? 'Unknown job'),
                date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
                startOdometer: (data['startOdometer'] as num?)?.toInt() ?? 0,
                endOdometer: (data['endOdometer'] as num?)?.toInt() ?? 0,
                totalKms: (data['totalKms'] as num?)?.toInt() ?? 0,
                note: data['note'] as String? ?? '',
                isPersonal: data['isPersonal'] as bool? ?? false,
                isReimbursable: data['isReimbursable'] as bool? ?? false,
                isBillable: data['isBillable'] as bool? ?? false,
                createdByUid: data['createdBy'] as String? ?? '',
              ),
            );
          } catch (e) {
            continue;
          }
        }

        if (_searchText.isNotEmpty) {
          entries = entries.where((e) {
            return e.jobName.toLowerCase().contains(_searchText) ||
                e.note.toLowerCase().contains(_searchText);
          }).toList();
        }

        entries.sort((a, b) {
          int cmp;
          switch (_sortBy) {
            case _TravelLogSortBy.date:
              cmp = a.date.compareTo(b.date);
              break;
            case _TravelLogSortBy.job:
              cmp = a.jobName.toLowerCase().compareTo(b.jobName.toLowerCase());
              break;
            case _TravelLogSortBy.totalKms:
              cmp = a.totalKms.compareTo(b.totalKms);
              break;
          }
          return _ascending ? cmp : -cmp;
        });

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _searchController,
              decoration: kInputDecoration.copyWith(
                hintText: 'Search by job or note',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchText.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchController.clear(),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('Sort by:'),
                const SizedBox(width: 8),
                DropdownButton<_TravelLogSortBy>(
                  value: _sortBy,
                  items: const [
                    DropdownMenuItem(
                      value: _TravelLogSortBy.date,
                      child: Text('Date'),
                    ),
                    DropdownMenuItem(
                      value: _TravelLogSortBy.job,
                      child: Text('Job'),
                    ),
                    DropdownMenuItem(
                      value: _TravelLogSortBy.totalKms,
                      child: Text('Distance'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _sortBy = value);
                  },
                ),
                const Spacer(),
                IconButton(
                  tooltip: _ascending ? 'Ascending' : 'Descending',
                  icon: Icon(
                    _ascending ? Icons.arrow_upward : Icons.arrow_downward,
                  ),
                  onPressed: () => setState(() => _ascending = !_ascending),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    docs.isEmpty
                        ? 'No travel logs yet'
                        : 'No travel logs match your search',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: entries.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) => TravelLogTile(
                  entry: entries[index],
                  companyId: widget.companyId,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TravelLogEntry {
  final String id;
  final String? jobId;
  final String jobName;
  final DateTime date;
  final int startOdometer;
  final int endOdometer;
  final int totalKms;
  final String note;
  final bool isPersonal;
  final bool isReimbursable;
  final bool isBillable;
  final String createdByUid;

  _TravelLogEntry({
    required this.id,
    required this.jobId,
    required this.jobName,
    required this.date,
    required this.startOdometer,
    required this.endOdometer,
    required this.totalKms,
    required this.note,
    required this.isPersonal,
    required this.isReimbursable,
    required this.isBillable,
    required this.createdByUid,
  });
}

class TravelLogTile extends StatelessWidget {
  final _TravelLogEntry entry;
  final String companyId;
  const TravelLogTile({
    super.key,
    required this.entry,
    required this.companyId,
  });

  // Only the person who logged the trip can edit or delete it.
  bool get _isOwner =>
      entry.createdByUid.isNotEmpty &&
      entry.createdByUid == services.currentUid;

  Future<void> _delete(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Delete this travel log?',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          content: Text(
            '${entry.totalKms} km on ${entry.date.month}/${entry.date.day}/${entry.date.year} will be removed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                try {
                  await firestore
                      .collection('TravelLogs')
                      .doc(entry.id)
                      .delete();
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                } catch (e) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text('Could not delete: $e')),
                    );
                  }
                }
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _edit(BuildContext context) async {
    String? editedJobId = entry.jobId;
    DateTime editedDate = entry.date;
    final startController = TextEditingController(
      text: entry.startOdometer.toString(),
    );
    final endController = TextEditingController(
      text: entry.endOdometer.toString(),
    );
    final noteController = TextEditingController(text: entry.note);
    bool editedPersonal = entry.isPersonal;
    bool editedReimbursable = entry.isReimbursable;
    bool editedBillable = entry.isBillable;

    try {
      await showDialog(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              return AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: const Text('Edit travel log'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: services.jobsForCompany(companyId),
                        builder: (context, snapshot) {
                          final docs = snapshot.data?.docs ?? [];
                          final validValue =
                              docs.any((d) => d.id == editedJobId)
                              ? editedJobId
                              : null;
                          return InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Job (optional)',
                              border: OutlineInputBorder(),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: validValue,
                                isExpanded: true,
                                hint: const Text('Select a job'),
                                items: docs.map((doc) {
                                  final jobName =
                                      doc.data()['name'] as String? ??
                                      'Unnamed job';
                                  return DropdownMenuItem<String>(
                                    value: doc.id,
                                    child: Text(jobName),
                                  );
                                }).toList(),
                                onChanged: (value) =>
                                    setDialogState(() => editedJobId = value),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: dialogContext,
                            initialDate: editedDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null)
                            setDialogState(() => editedDate = picked);
                        },
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: Text(
                          '${editedDate.month}/${editedDate.day}/${editedDate.year}',
                        ),
                        style: OutlinedButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: startController,
                        keyboardType: TextInputType.number,
                        decoration: kInputDecoration.copyWith(
                          labelText: 'Start odometer',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: endController,
                        keyboardType: TextInputType.number,
                        decoration: kInputDecoration.copyWith(
                          labelText: 'End odometer',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: noteController,
                        maxLines: 2,
                        decoration: kInputDecoration.copyWith(
                          labelText: 'Notes',
                        ),
                      ),
                      CheckboxListTile(
                        value: editedReimbursable,
                        title: const Text('Reimbursable'),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        onChanged: (value) {
                          setDialogState(() {
                            editedReimbursable = value ?? false;
                            if (editedReimbursable) editedPersonal = false;
                          });
                        },
                      ),
                      CheckboxListTile(
                        value: editedPersonal,
                        title: const Text('Personal'),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        onChanged: (value) {
                          setDialogState(() {
                            editedPersonal = value ?? false;
                            if (editedPersonal) editedReimbursable = false;
                          });
                        },
                      ),
                      CheckboxListTile(
                        value: editedBillable,
                        title: const Text('Billable'),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        onChanged: (value) => setDialogState(
                          () => editedBillable = value ?? false,
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      final start = int.tryParse(startController.text.trim());
                      final end = int.tryParse(endController.text.trim());
                      if (start == null || end == null || end <= start) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          const SnackBar(
                            content: Text('Enter a valid start/end odometer'),
                          ),
                        );
                        return;
                      }
                      try {
                        await firestore
                            .collection('TravelLogs')
                            .doc(entry.id)
                            .update({
                              'jobId': editedJobId,
                              'date': Timestamp.fromDate(editedDate),
                              'startOdometer': start,
                              'endOdometer': end,
                              'totalKms': end - start,
                              'note': noteController.text.trim(),
                              'isPersonal': editedPersonal,
                              'isReimbursable': editedReimbursable,
                              'isBillable': editedBillable,
                            });
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      } catch (e) {
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(content: Text('Could not save: $e')),
                          );
                        }
                      }
                    },
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      startController.dispose();
      endController.dispose();
      noteController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.jobName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      '${entry.totalKms} km',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _TravelChip(
                      label:
                          '${entry.date.month}/${entry.date.day}/${entry.date.year}',
                      icon: Icons.event,
                      color: Colors.blueGrey,
                    ),
                    _TravelChip(
                      label: '${entry.startOdometer} → ${entry.endOdometer}',
                      icon: Icons.speed,
                      color: Colors.blueGrey,
                    ),
                    if (entry.isReimbursable)
                      const _TravelChip(
                        label: 'Reimbursable',
                        icon: Icons.attach_money,
                        color: Colors.green,
                      ),
                    if (entry.isPersonal)
                      const _TravelChip(
                        label: 'Personal',
                        icon: Icons.person,
                        color: Colors.purple,
                      ),
                    if (entry.isBillable)
                      const _TravelChip(
                        label: 'Billable',
                        icon: Icons.receipt_long,
                        color: Colors.orange,
                      ),
                  ],
                ),
                if (entry.note.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    entry.note,
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  ),
                ],
              ],
            ),
          ),
          if (_isOwner)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit, size: 20),
                  color: Colors.grey[600],
                  onPressed: () => _edit(context),
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete, size: 20),
                  color: Colors.red,
                  onPressed: () => _delete(context),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TravelChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const _TravelChip({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
