import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:contractor_hub/components/app_bar.dart';
import 'package:contractor_hub/components/time_ago.dart';
import 'package:contractor_hub/services/firebase_services.dart';
import 'package:flutter/material.dart';

final _services = FirebaseServices.instance;

// ───────────────────────────── helpers ─────────────────────────────

/// Length of one clock record. Open shifts (no clockOutTime) count up to now.
Duration _shiftDuration(Map<String, dynamic> d, DateTime now) {
  final start = (d['clockInTime'] as Timestamp?)?.toDate();
  if (start == null) return Duration.zero; // server timestamp not resolved yet
  final end = (d['clockOutTime'] as Timestamp?)?.toDate() ?? now;
  final dur = end.difference(start);
  return dur.isNegative ? Duration.zero : dur;
}

String _fmt(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

class _Totals {
  Duration d7 = Duration.zero;
  Duration d14 = Duration.zero;
  Duration d90 = Duration.zero;
  Duration all = Duration.zero;
  bool onClock = false;
}

/// One pass over the records fills every bucket.
_Totals _totals(List<Map<String, dynamic>> records, DateTime now) {
  final t = _Totals();
  final c7 = now.subtract(const Duration(days: 7));
  final c14 = now.subtract(const Duration(days: 14));
  final c90 = now.subtract(const Duration(days: 90));
  for (final r in records) {
    final start = (r['clockInTime'] as Timestamp?)?.toDate();
    if (start == null) continue;
    if (r['clockOutTime'] == null) t.onClock = true;
    final dur = _shiftDuration(r, now);
    t.all += dur;
    if (start.isAfter(c90)) t.d90 += dur;
    if (start.isAfter(c14)) t.d14 += dur;
    if (start.isAfter(c7)) t.d7 += dur;
  }
  return t;
}

// ───────────────────────────── screen ─────────────────────────────

class YourEmployeesScreen extends StatelessWidget {
  const YourEmployeesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppBarWidget(title: 'Your Employees'),
      backgroundColor: Colors.grey[100],
      body: const DisplayEmployeeList(),
    );
  }
}

class DisplayEmployeeList extends StatefulWidget {
  const DisplayEmployeeList({super.key});

  @override
  State<DisplayEmployeeList> createState() => _DisplayEmployeeListState();
}

class _DisplayEmployeeListState extends State<DisplayEmployeeList> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  /// null = All positions, '__same_as_me__' = same as current user
  String? _positionFilter;
  String? _myPosition;

  @override
  void initState() {
    super.initState();
    _loadMyPosition();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMyPosition() async {
    final uid = _services.currentUid;
    if (uid == null) return;
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!mounted) return;
      setState(() {
        _myPosition = (doc.data()?['position'] as String?)?.trim();
      });
    } catch (e) {
      debugPrint('Could not load my position: $e');
    }
  }

  /// Search + position filter, then A→Z by name.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterAndSort(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final q = _searchQuery.trim().toLowerCase();

    final filtered = docs.where((doc) {
      final data = doc.data();
      final name = (data['name'] as String? ?? '').toLowerCase();
      final position = (data['position'] as String?)?.trim() ?? '';

      // Name search
      if (q.isNotEmpty && !name.contains(q)) return false;

      // Position filter
      if (_positionFilter == null) return true;
      if (_positionFilter == '__same_as_me__') {
        if (_myPosition == null || _myPosition!.isEmpty) return false;
        return position.toLowerCase() == _myPosition!.toLowerCase();
      }
      return position.toLowerCase() == _positionFilter!.toLowerCase();
    }).toList();

    // Alphabetical by name (case-insensitive)
    filtered.sort((a, b) {
      final nameA = (a.data()['name'] as String? ?? '').toLowerCase();
      final nameB = (b.data()['name'] as String? ?? '').toLowerCase();
      return nameA.compareTo(nameB);
    });

    return filtered;
  }

  List<String> _uniquePositions(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final set = <String>{};
    for (final doc in docs) {
      final p = (doc.data()['position'] as String?)?.trim() ?? '';
      if (p.isNotEmpty) set.add(p);
    }
    final list = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _services.streamYourEmployees(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('employees stream error: ${snapshot.error}');
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Error: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final allDocs = snapshot.data!.docs;
        final positions = _uniquePositions(allDocs);
        final filtered = _filterAndSort(allDocs);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Search bar ──
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search employees by name…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.blue, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
            ),

            // ── Position filter chips ──
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: const Text('All'),
                      selected: _positionFilter == null,
                      onSelected: (_) =>
                          setState(() => _positionFilter = null),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(
                        _myPosition != null && _myPosition!.isNotEmpty
                            ? 'Same as me ($_myPosition)'
                            : 'Same as me',
                      ),
                      selected: _positionFilter == '__same_as_me__',
                      onSelected: (_) =>
                          setState(() => _positionFilter = '__same_as_me__'),
                    ),
                  ),
                  ...positions.map((p) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(p),
                        selected: _positionFilter == p,
                        onSelected: (_) =>
                            setState(() => _positionFilter = p),
                      ),
                    );
                  }),
                ],
              ),
            ),

            // Result count
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(
                filtered.isEmpty
                    ? 'No matches'
                    : '${filtered.length} employee${filtered.length == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ),

            // ── Alphabetical list ──
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        allDocs.isEmpty
                            ? 'No employees yet'
                            : 'No employees match your search',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final doc = filtered[i];
                        final data = doc.data();
                        return EmployeeCard(
                          key: ValueKey(doc.id),
                          uid: doc.id,
                          name: data['name'] as String? ?? 'Unknown',
                          position: data['position'] as String? ?? '',
                          hiredAt: data['createdAt'] as Timestamp?,
                          isBoss: data['isEmployee'] == false,
                          isPending: data['status'] == 'pending',
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class EmployeeCard extends StatefulWidget {
  final String uid;
  final String name;
  final Timestamp? hiredAt;
  final bool isBoss;
  final bool isPending;
  final String position;

  const EmployeeCard({
    super.key,
    required this.uid,
    required this.name,
    required this.hiredAt,
    required this.isBoss,
    required this.isPending,
    required this.position,
  });

  @override
  State<EmployeeCard> createState() => _EmployeeCardState();
}

class _EmployeeCardState extends State<EmployeeCard> {
  bool _expanded = false;

  Future<void> _edit() async {
    final messenger = ScaffoldMessenger.of(context);
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => _EditNameDialog(current: widget.name),
    );
    if (newName == null || newName == widget.name) return;
    try {
      await _services.updateEmployeeName(widget.uid, newName);
      messenger.showSnackBar(SnackBar(content: Text('Renamed to $newName')));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to update name: $e')),
      );
    }
  }

  /// Returns after the delete finishes (or fails). Used by both the button
  /// and the swipe gesture.
  Future<void> _delete() async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${widget.name}?'),
        content: const Text(
          'This removes their account and login and frees up a seat. '
          'Their past clock records are kept. This cannot be undone.',
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
      await _services.deleteEmployee(widget.uid);
      messenger.showSnackBar(SnackBar(content: Text('${widget.name} deleted')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?';

    final card = Card(
      margin: EdgeInsets.zero,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.blueGrey[100],
                    child: Text(initial),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (widget.position.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.position,
                            style: TextStyle(fontSize: 13, color: Colors.blueGrey[700]),
                          ),
                        ],
                        const SizedBox(height: 2),
                        Text(
                          widget.hiredAt == null
                              ? 'Joined: unknown'
                              : 'Joined ${formatTimeAgo(widget.hiredAt)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.isBoss)
                    const Chip(
                      label: Text('Boss'),
                      visualDensity: VisualDensity.compact,
                    ),
                  if (widget.isPending)
                    const Chip(
                      label: Text('Pending'),
                      visualDensity: VisualDensity.compact,
                    ),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _edit,
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text('Edit name'),
                      ),
                      const SizedBox(width: 8),
                      if (!widget.isBoss)
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                          onPressed: _delete,
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('Delete'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _HoursPanel(uid: widget.uid),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: widget.isBoss
          ? card
          : Dismissible(
              key: ValueKey('dismiss-${widget.uid}'),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              // Run the delete ourselves and always return false: the
              // Firestore stream removes the row when the doc is gone, so a
              // failed delete never leaves the list out of sync.
              confirmDismiss: (_) async {
                await _delete();
                return false;
              },
              child: card,
            ),
    );
  }
}

class _EditNameDialog extends StatefulWidget {
  final String current;
  const _EditNameDialog({required this.current});

  @override
  State<_EditNameDialog> createState() => _EditNameDialogState();
}

class _EditNameDialogState extends State<_EditNameDialog> {
  late final _controller = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit name'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: 'Name',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

// ───────────────────────────── hours ─────────────────────────────

/// Loads lazily (only once the card is expanded). One query covers 7, 14 and
/// 90 days; "All time" is a second query that runs only if tapped, because
/// it can be large.
class _HoursPanel extends StatefulWidget {
  final String uid;
  const _HoursPanel({required this.uid});

  @override
  State<_HoursPanel> createState() => _HoursPanelState();
}

class _HoursPanelState extends State<_HoursPanel> {
  late Future<List<Map<String, dynamic>>> _recent;
  Future<List<Map<String, dynamic>>>? _all;

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  void _loadRecent() {
    _recent = _services.employeeClockRecords(
      widget.uid,
      since: DateTime.now().subtract(const Duration(days: 90)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _recent,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(8),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        if (snap.hasError) {
          debugPrint('hours load failed: ${snap.error}');
          return Text(
            'Could not load hours: ${snap.error}\n'
            '(If this mentions an index, open the link in the message to create it.)',
            style: const TextStyle(color: Colors.red, fontSize: 12),
          );
        }

        final now = DateTime.now();
        final t = _totals(snap.data!, now);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Hours worked',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                if (t.onClock) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.circle, size: 10, color: Colors.green),
                  const SizedBox(width: 4),
                  const Text(
                    'on the clock now',
                    style: TextStyle(fontSize: 12, color: Colors.green),
                  ),
                ],
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: () => setState(() {
                    _all = null;
                    _loadRecent();
                  }),
                ),
              ],
            ),
            Row(
              children: [
                _tile('7 days', _fmt(t.d7)),
                _tile('14 days', _fmt(t.d14)),
                _tile('90 days', _fmt(t.d90)),
                _allTile(now),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _allTile(DateTime now) {
    if (_all == null) {
      return _tile(
        'All time',
        'Tap to load',
        onTap: () => setState(() {
          _all = _services.employeeClockRecords(widget.uid);
        }),
      );
    }
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _all,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _tile('All time', '…');
        }
        if (snap.hasError) {
          return _tile(
            'All time',
            'Error',
            onTap: () => setState(() => _all = null),
          );
        }
        return _tile('All time', _fmt(_totals(snap.data!, now).all));
      },
    );
  }

  Widget _tile(String label, String value, {VoidCallback? onTap}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            decoration: BoxDecoration(
              color: Colors.blueGrey[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                FittedBox(
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
