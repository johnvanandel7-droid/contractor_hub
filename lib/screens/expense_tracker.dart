import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:contractor_hub/components/app_bar.dart';
import 'package:contractor_hub/constants.dart';
import 'package:contractor_hub/services/firebase_services.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

final services = FirebaseServices.instance;
final firestore = FirebaseFirestore.instance;

class ExpenseTracker extends StatefulWidget {
  const ExpenseTracker({super.key});

  @override
  State<ExpenseTracker> createState() => _ExpenseTrackerState();
}

class _ExpenseTrackerState extends State<ExpenseTracker> {
  String? selectedJobId;
  String? selectedCostCode;
  DateTime selectedDate = DateTime.now();
  final TextEditingController amountController = TextEditingController();
  final TextEditingController noteController = TextEditingController();
  String? _companyId;
  bool isReimbursable = false;
  bool isBillable = false;
  XFile? pickedImage;
  bool _submitting = false;

  final ImagePicker _picker = ImagePicker();

  // Not const: the "+" button below lets a user add a custom code for this
  // session, which needs a growable list.
  final List<String> costCodes = [
    'Kubota 75',
    'terex',
    'mini ex',
    'jobsite',
    'time and material',
  ];

  Stream<QuerySnapshot<Map<String, dynamic>>>? _jobsStream;
  bool _loadingJobs = true;

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
    amountController.dispose();
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
    if (picked != null) {
      setState(() => selectedDate = picked);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 85);
      if (picked != null) setState(() => pickedImage = picked);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to pick image: $e')));
      }
    }
  }

  Future<void> _addCustomCostCode() async {
    final newCode = await showDialog<String>(
      context: context,
      builder: (_) => const _AddCostCodeDialog(),
    );

    if (!mounted) return;
    if (newCode != null && newCode.isNotEmpty) {
      setState(() {
        if (!costCodes.contains(newCode)) costCodes.add(newCode);
        selectedCostCode = newCode;
      });
    }
  }

  static String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) return 'jpg';
    final ext = path.substring(dot + 1).toLowerCase();
    return const {'jpg', 'jpeg', 'png', 'heic', 'webp'}.contains(ext)
        ? ext
        : 'jpg';
  }

  static String _contentTypeFor(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'heic':
        return 'image/heic';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  Future<void> _submitPOLog() async {
    if (_companyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not determine your company')),
      );
      return;
    }
    if (selectedJobId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a job')));
      return;
    }
    if (selectedCostCode == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a cost code')),
      );
      return;
    }
    final amount = double.tryParse(amountController.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
      return;
    }

    setState(() => _submitting = true);
    try {
      // Create the doc id first so the photo can live under it in Storage.
      final docRef = firestore.collection('POlogs').doc();

      String? imageUrl;
      String? storagePath;
      final image = pickedImage;
      if (image != null) {
        final ext = _extensionOf(image.path);
        storagePath = 'companies/$_companyId/poImages/${docRef.id}/'
            '${DateTime.now().millisecondsSinceEpoch}.$ext';
        final ref = FirebaseStorage.instance.ref(storagePath);
        await ref.putFile(
          File(image.path),
          SettableMetadata(contentType: _contentTypeFor(ext)),
        );
        imageUrl = await ref.getDownloadURL();
      }

      await docRef.set({
        'companyId': _companyId,
        'createdBy': services.currentUid,
        'createdAt': FieldValue.serverTimestamp(),
        'costCode': selectedCostCode,
        'jobId': selectedJobId,
        'date': Timestamp.fromDate(selectedDate),
        'amount': amount,
        'note': noteController.text.trim(),
        'isReimbursable': isReimbursable,
        'isBillable': isBillable,
        'imageUrl': imageUrl,
        'storagePath': storagePath,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('PO log added')));
      setState(() {
        selectedJobId = null;
        selectedCostCode = null;
        selectedDate = DateTime.now();
        amountController.clear();
        noteController.clear();
        isReimbursable = false;
        isBillable = false;
        pickedImage = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save PO log: $e')));
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
            labelText: 'Job',
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

  Widget _costCodeDropdown() {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Cost code',
        border: OutlineInputBorder(),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedCostCode,
          isExpanded: true,
          hint: const Text('Select a cost code'),
          items: costCodes
              .map(
                (code) =>
                    DropdownMenuItem<String>(value: code, child: Text(code)),
              )
              .toList(),
          onChanged: (value) => setState(() => selectedCostCode = value),
        ),
      ),
    );
  }

  Widget _buildCreatePOCard() {
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
              Icon(Icons.add_shopping_cart, color: Colors.blue),
              SizedBox(width: 8),
              Text(
                'New PO Log',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildJobDropdown(),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _costCodeDropdown()),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: IconButton(
                  onPressed: _addCustomCostCode,
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: 'Add cost code',
                ),
              ),
            ],
          ),
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
            controller: amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: kInputDecoration.copyWith(
              labelText: 'Amount (inc. tax)',
              hintText: '\$1000',
              prefixIcon: const Icon(Icons.attach_money),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: noteController,
            maxLines: 2,
            decoration: kInputDecoration.copyWith(
              labelText: 'Notes',
              hintText: 'bought it to fix the skidsteer',
            ),
          ),
          const SizedBox(height: 4),
          CheckboxListTile(
            value: isReimbursable,
            onChanged: (value) =>
                setState(() => isReimbursable = value ?? false),
            title: const Text('Reimbursable'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
          CheckboxListTile(
            value: isBillable,
            onChanged: (value) => setState(() => isBillable = value ?? false),
            title: const Text('Billable'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.camera_alt),
                label: const Text('Camera'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.image),
                label: const Text('Gallery'),
              ),
            ],
          ),
          if (pickedImage != null) ...[
            const SizedBox(height: 12),
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    File(pickedImage!.path),
                    height: 120,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: () => setState(() => pickedImage = null),
                    child: const CircleAvatar(
                      radius: 12,
                      backgroundColor: Colors.black54,
                      child: Icon(Icons.close, size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: _submitting ? null : _submitPOLog,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
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
                : const Text('Add PO Log'),
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
              _buildCreatePOCard(),
              const SizedBox(height: 24),
              Row(
                children: const [
                  Icon(Icons.receipt_long, size: 20, color: Colors.blueGrey),
                  SizedBox(width: 6),
                  Text(
                    'Past PO Logs',
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
                DisplayPOlogs(companyId: _companyId!, costCodes: costCodes),
            ],
          ),
        ),
      ),
    );
  }
}

enum _POLogSortBy { date, job, costCode }

class DisplayPOlogs extends StatefulWidget {
  final String companyId;
  final List<String> costCodes;
  const DisplayPOlogs({
    super.key,
    required this.companyId,
    required this.costCodes,
  });

  @override
  State<DisplayPOlogs> createState() => _DisplayPOlogsState();
}

class _DisplayPOlogsState extends State<DisplayPOlogs> {
  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';
  _POLogSortBy _sortBy = _POLogSortBy.date;
  bool _ascending = false; // newest first by default

  // Job names are resolved once up front instead of per-tile, so
  // searching/sorting doesn't need to wait on a Firestore read per row.
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
      stream: services.streamPOLogs(widget.companyId),
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
            child: Text('Error loading PO logs: ${snapshot.error}'),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        var entries = <_POLogEntry>[];

        for (final doc in docs) {
          try {
            final data = doc.data();
            final jobId = data['jobId'] as String?;
            entries.add(
              _POLogEntry(
                id: doc.id,
                jobName: jobId == null
                    ? 'No job'
                    : (_jobNames[jobId] ?? 'Unknown job'),
                costCode: data['costCode'] as String? ?? 'Uncoded',
                date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
                amount: (data['amount'] as num?)?.toDouble() ?? 0,
                note: data['note'] as String? ?? '',
                isReimbursable: data['isReimbursable'] as bool? ?? false,
                isBillable: data['isBillable'] as bool? ?? false,
                imageUrl: data['imageUrl'] as String?,
                storagePath: data['storagePath'] as String?,
                jobId: jobId,
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
                e.costCode.toLowerCase().contains(_searchText) ||
                e.note.toLowerCase().contains(_searchText);
          }).toList();
        }

        entries.sort((a, b) {
          int cmp;
          switch (_sortBy) {
            case _POLogSortBy.date:
              cmp = a.date.compareTo(b.date);
              break;
            case _POLogSortBy.job:
              cmp = a.jobName.toLowerCase().compareTo(b.jobName.toLowerCase());
              break;
            case _POLogSortBy.costCode:
              cmp = a.costCode.toLowerCase().compareTo(
                b.costCode.toLowerCase(),
              );
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
                hintText: 'Search by job, cost code, or note',
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
                DropdownButton<_POLogSortBy>(
                  value: _sortBy,
                  items: const [
                    DropdownMenuItem(
                      value: _POLogSortBy.date,
                      child: Text('Date'),
                    ),
                    DropdownMenuItem(
                      value: _POLogSortBy.job,
                      child: Text('Job'),
                    ),
                    DropdownMenuItem(
                      value: _POLogSortBy.costCode,
                      child: Text('Cost code'),
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
                        ? 'No PO logs yet'
                        : 'No PO logs match your search',
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
                itemBuilder: (context, index) => POLogTile(
                  entry: entries[index],
                  companyId: widget.companyId,
                  costCodes: widget.costCodes,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _POLogEntry {
  final String id;
  final String? jobId;
  final String jobName;
  final String costCode;
  final DateTime date;
  final double amount;
  final String note;
  final bool isReimbursable;
  final bool isBillable;
  final String? imageUrl;
  final String? storagePath;
  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;
  final String createdByUid;

  _POLogEntry({
    required this.id,
    required this.jobId,
    required this.jobName,
    required this.costCode,
    required this.date,
    required this.amount,
    required this.note,
    required this.isReimbursable,
    required this.isBillable,
    required this.imageUrl,
    required this.storagePath,
    required this.createdByUid,
  });
}

class POLogTile extends StatelessWidget {
  final _POLogEntry entry;
  final String companyId;
  final List<String> costCodes;
  const POLogTile({
    super.key,
    required this.entry,
    required this.companyId,
    required this.costCodes,
  });

  // Only the person who logged this PO can edit or delete it.
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
            'Delete this PO log?',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          content: Text(
            '${entry.costCode} · \$${entry.amount.toStringAsFixed(2)} on '
            '${entry.date.month}/${entry.date.day}/${entry.date.year} will be removed.',
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
                  await firestore.collection('POlogs').doc(entry.id).delete();
                  final path = entry.storagePath;
                  if (path != null && path.isNotEmpty) {
                    try {
                      await FirebaseStorage.instance.ref(path).delete();
                    } catch (_) {
                      // Photo already gone or not deletable - the log is deleted.
                    }
                  }
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

  void _viewPhoto(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 5,
                child: Center(
                  child: Image.network(
                    entry.imageUrl!,
                    fit: BoxFit.contain,
                    loadingBuilder: (c, child, p) => p == null
                        ? child
                        : const Center(child: CircularProgressIndicator()),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(dialogContext),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context) async {
    // Make sure this entry's existing code still shows up in the dropdown.
    final availableCodes = {...costCodes, entry.costCode}.toList();
    await showDialog(
      context: context,
      builder: (_) => _EditPOLogDialog(
        entry: entry,
        companyId: companyId,
        availableCodes: availableCodes,
      ),
    );
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
                      '\$${entry.amount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _Chip(
                      label: entry.costCode,
                      icon: Icons.build,
                      color: Colors.blueGrey,
                    ),
                    _Chip(
                      label:
                          '${entry.date.month}/${entry.date.day}/${entry.date.year}',
                      icon: Icons.event,
                      color: Colors.blueGrey,
                    ),
                    if (entry.isReimbursable)
                      const _Chip(
                        label: 'Reimbursable',
                        icon: Icons.attach_money,
                        color: Colors.green,
                      ),
                    if (entry.isBillable)
                      const _Chip(
                        label: 'Billable',
                        icon: Icons.receipt_long,
                        color: Colors.orange,
                      ),
                    if (entry.hasImage)
                      const _Chip(
                        label: 'Photo attached',
                        icon: Icons.photo,
                        color: Colors.purple,
                      ),
                  ],
                ),
                if (entry.hasImage) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _viewPhoto(context),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        entry.imageUrl!,
                        height: 110,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        loadingBuilder: (c, child, p) => p == null
                            ? child
                            : const SizedBox(
                                height: 110,
                                child: Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                        errorBuilder: (_, __, ___) => const SizedBox(
                          height: 110,
                          child: Center(child: Icon(Icons.broken_image)),
                        ),
                      ),
                    ),
                  ),
                ],
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

class _Chip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const _Chip({required this.label, required this.icon, required this.color});

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


// Dialogs own their controllers so they are disposed only when the dialog is
// really gone (disposing right after `await showDialog` crashes, because the
// closing animation is still using the controller).

class _AddCostCodeDialog extends StatefulWidget {
  const _AddCostCodeDialog();

  @override
  State<_AddCostCodeDialog> createState() => _AddCostCodeDialogState();
}

class _AddCostCodeDialogState extends State<_AddCostCodeDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Add cost code'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: kInputDecoration.copyWith(hintText: 'e.g. Bobcat rental'),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _EditPOLogDialog extends StatefulWidget {
  final _POLogEntry entry;
  final String companyId;
  final List<String> availableCodes;
  const _EditPOLogDialog({
    required this.entry,
    required this.companyId,
    required this.availableCodes,
  });

  @override
  State<_EditPOLogDialog> createState() => _EditPOLogDialogState();
}

class _EditPOLogDialogState extends State<_EditPOLogDialog> {
  late String? _jobId = widget.entry.jobId;
  late String _costCode = widget.entry.costCode;
  late DateTime _date = widget.entry.date;
  late bool _reimbursable = widget.entry.isReimbursable;
  late bool _billable = widget.entry.isBillable;
  late final TextEditingController _amount = TextEditingController(
    text: widget.entry.amount.toStringAsFixed(2),
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.entry.note,
  );
  // Created once so the dropdown doesn't re-subscribe on every setState.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _jobs =
      services.jobsForCompany(widget.companyId);
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
      return;
    }
    setState(() => _saving = true);
    try {
      await firestore.collection('POlogs').doc(widget.entry.id).update({
        'jobId': _jobId,
        'costCode': _costCode,
        'date': Timestamp.fromDate(_date),
        'amount': amount,
        'note': _note.text.trim(),
        'isReimbursable': _reimbursable,
        'isBillable': _billable,
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
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Edit PO log'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _jobs,
              builder: (context, snapshot) {
                final docs = snapshot.data?.docs ?? [];
                final validValue = docs.any((d) => d.id == _jobId)
                    ? _jobId
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
                        return DropdownMenuItem<String>(
                          value: doc.id,
                          child: Text(
                            doc.data()['name'] as String? ?? 'Unnamed job',
                          ),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() => _jobId = v),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Cost code',
                border: OutlineInputBorder(),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _costCode,
                  isExpanded: true,
                  items: widget.availableCodes
                      .map(
                        (c) => DropdownMenuItem<String>(
                          value: c,
                          child: Text(c),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _costCode = v);
                  },
                ),
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null && mounted) setState(() => _date = picked);
              },
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text('${_date.month}/${_date.day}/${_date.year}'),
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: kInputDecoration.copyWith(
                labelText: 'Amount (inc. tax)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              maxLines: 2,
              decoration: kInputDecoration.copyWith(labelText: 'Notes'),
            ),
            CheckboxListTile(
              value: _reimbursable,
              title: const Text('Reimbursable'),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
              onChanged: (v) => setState(() => _reimbursable = v ?? false),
            ),
            CheckboxListTile(
              value: _billable,
              title: const Text('Billable'),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
              onChanged: (v) => setState(() => _billable = v ?? false),
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