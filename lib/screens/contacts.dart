import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:contractor_hub/components/app_bar.dart';
import 'package:contractor_hub/constants.dart';
import 'package:contractor_hub/services/firebase_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
 
final services = FirebaseServices.instance;
final firestore = FirebaseFirestore.instance;
 
const _syncedGroupName = 'Synced from Phone';
 
class Contacts extends StatefulWidget {
  const Contacts({super.key});
 
  @override
  State<Contacts> createState() => _ContactsState();
}
 
class _ContactsState extends State<Contacts> {
  bool _loadingCompany = true;
  String? _companyId;
  bool _isBoss = false;
  bool _syncing = false;
 
  String? _selectedGroupId; // null = "All"
  String _searchText = '';
  final TextEditingController _searchController = TextEditingController();
 
  @override
  void initState() {
    super.initState();
    _loadCompany();
    _searchController.addListener(() {
      setState(() => _searchText = _searchController.text.trim().toLowerCase());
    });
  }
 
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
 
  Future<void> _loadCompany() async {
    final uid = services.currentUid;
    if (uid == null) {
      setState(() => _loadingCompany = false);
      return;
    }
    final user = await services.getUser(uid);
    if (!mounted) return;
    setState(() {
      _companyId = user?['companyId'] as String?;
      _isBoss = !(user?['isEmployee'] as bool? ?? true);
      _loadingCompany = false;
    });
  }
 
  Future<String> _ensureSyncedGroup() async {
    final existing = await firestore
        .collection('contactGroups')
        .where('companyId', isEqualTo: _companyId)
        .where('name', isEqualTo: _syncedGroupName)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) return existing.docs.first.id;
 
    final newGroup = await firestore.collection('contactGroups').add({
      'companyId': _companyId,
      'name': _syncedGroupName,
      'createdBy': services.currentUid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return newGroup.id;
  }
 
  Future<void> _syncWithPhoneContacts() async {
    if (_companyId == null) return;
 
    setState(() => _syncing = true);
    try {
      // flutter_contacts v2 API: permissions live under .permissions and
      // return a status enum rather than a bool. "limited" (iOS 18+) means
      // the person shared a subset of contacts, which is still usable.
      final status = await FlutterContacts.permissions.request(PermissionType.read);
      if (status != PermissionStatus.granted && status != PermissionStatus.limited) {
        throw Exception(
          status == PermissionStatus.permanentlyDenied
              ? 'Contacts permission was denied. Turn it on for this app in your phone settings.'
              : 'Contacts permission was denied',
        );
      }
 
      // v2 only fetches id + display name unless told otherwise, so ask for
      // phone and email explicitly.
      final deviceContacts = await FlutterContacts.getAll(
        properties: {ContactProperty.name, ContactProperty.phone, ContactProperty.email},
      );
      final groupId = await _ensureSyncedGroup();
 
      // Only ever compares against contacts THIS sync process previously
      // created (matched by deviceContactId) — manual contacts and groups,
      // the boss's own or anyone else's, are never read or touched here.
      final existingSynced = await firestore
          .collection('contacts')
          .where('companyId', isEqualTo: _companyId)
          .where('source', isEqualTo: 'synced')
          .get();
      final alreadySyncedIds = existingSynced.docs
          .map((d) => d.data()['deviceContactId'] as String?)
          .whereType<String>()
          .toSet();
 
      final toImport = <Map<String, dynamic>>[];
      for (final contact in deviceContacts) {
        // id and displayName are nullable in v2.
        final deviceId = contact.id;
        if (deviceId == null || alreadySyncedIds.contains(deviceId)) continue;
        final name = (contact.displayName ?? '').trim();
        if (name.isEmpty) continue;
        final phone = contact.phones.isNotEmpty ? contact.phones.first.number : null;
        final email = contact.emails.isNotEmpty ? contact.emails.first.address : null;
        if (phone == null && email == null) continue;
 
        toImport.add({
          'companyId': _companyId,
          'name': name,
          'phoneNumber': phone,
          'email': email,
          'groupId': groupId,
          'source': 'synced',
          'deviceContactId': deviceId,
          'addedBy': services.currentUid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
 
      // Firestore batches cap at 500 writes, so chunk large address books.
      const chunkSize = 400;
      for (var i = 0; i < toImport.length; i += chunkSize) {
        final batch = firestore.batch();
        final end = (i + chunkSize > toImport.length) ? toImport.length : i + chunkSize;
        for (final data in toImport.sublist(i, end)) {
          batch.set(firestore.collection('contacts').doc(), data);
        }
        await batch.commit();
      }
 
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Synced ${toImport.length} new contact${toImport.length == 1 ? '' : 's'} from your phone',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }
 
  Future<String?> _pickOrCreateGroup(
    BuildContext dialogContext,
    StateSetter setDialogState,
    String? currentGroupId,
  ) async {
    // Shown inline inside the add/edit contact dialog; kept as a separate
    // method only for the "create a new group" sub-dialog.
    final controller = TextEditingController();
    final newName = await showDialog<String>(
      context: dialogContext,
      builder: (innerContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('New group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: kInputDecoration.copyWith(hintText: 'e.g. Suppliers'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(innerContext), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(innerContext, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
 
    if (newName == null || newName.isEmpty) return null;
 
    final newGroup = await firestore.collection('contactGroups').add({
      'companyId': _companyId,
      'name': newName,
      'createdBy': services.currentUid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return newGroup.id;
  }
 
  Future<void> _openContactDialog({
    String? contactId,
    String initialName = '',
    String initialPhone = '',
    String initialEmail = '',
    String? initialGroupId,
  }) async {
    final nameController = TextEditingController(text: initialName);
    final phoneController = TextEditingController(text: initialPhone);
    final emailController = TextEditingController(text: initialEmail);
    String? selectedGroupId = initialGroupId;
 
    try {
      await showDialog(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: Text(contactId == null ? 'Add contact' : 'Edit contact'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: nameController,
                        autofocus: true,
                        decoration: kInputDecoration.copyWith(hintText: 'Name'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: kInputDecoration.copyWith(hintText: 'Phone (optional)'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: kInputDecoration.copyWith(hintText: 'Email (optional)'),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                              stream: firestore
                                  .collection('contactGroups')
                                  .where('companyId', isEqualTo: _companyId)
                                  .snapshots(),
                              builder: (context, snapshot) {
                                final groups = snapshot.data?.docs ?? [];
                                final sorted = [...groups]..sort((a, b) =>
                                    (a.data()['name'] as String? ?? '')
                                        .toLowerCase()
                                        .compareTo((b.data()['name'] as String? ?? '').toLowerCase()));
                                final validValue =
                                    sorted.any((g) => g.id == selectedGroupId) ? selectedGroupId : null;
 
                                return InputDecorator(
                                  decoration: const InputDecoration(
                                    labelText: 'Group',
                                    border: OutlineInputBorder(),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: validValue,
                                      isExpanded: true,
                                      hint: const Text('No group'),
                                      items: sorted
                                          .map(
                                            (g) => DropdownMenuItem<String>(
                                              value: g.id,
                                              child: Text(g.data()['name'] as String? ?? 'Unnamed'),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (value) =>
                                          setDialogState(() => selectedGroupId = value),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          IconButton(
                            tooltip: 'New group',
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () async {
                              final newGroupId =
                                  await _pickOrCreateGroup(dialogContext, setDialogState, selectedGroupId);
                              if (newGroupId != null) {
                                setDialogState(() => selectedGroupId = newGroupId);
                              }
                            },
                          ),
                        ],
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
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                    onPressed: () async {
                      final name = nameController.text.trim();
                      if (name.isEmpty) return;
 
                      final data = {
                        'companyId': _companyId,
                        'name': name,
                        'phoneNumber': phoneController.text.trim().isEmpty ? null : phoneController.text.trim(),
                        'email': emailController.text.trim().isEmpty ? null : emailController.text.trim(),
                        'groupId': selectedGroupId,
                      };
 
                      try {
                        if (contactId == null) {
                          await firestore.collection('contacts').add({
                            ...data,
                            'source': 'manual',
                            'addedBy': services.currentUid,
                            'createdAt': FieldValue.serverTimestamp(),
                          });
                        } else {
                          await firestore.collection('contacts').doc(contactId).update(data);
                        }
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
      nameController.dispose();
      phoneController.dispose();
      emailController.dispose();
    }
  }
 
  Future<void> _confirmDeleteContact(String contactId, String name) async {
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete this contact?'),
        content: Text('"$name" will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              try {
                await firestore.collection('contacts').doc(contactId).delete();
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
      ),
    );
  }
 
  Widget _buildGroupChips() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: firestore.collection('contactGroups').where('companyId', isEqualTo: _companyId).snapshots(),
      builder: (context, snapshot) {
        final groups = snapshot.data?.docs ?? [];
        final sorted = [...groups]..sort((a, b) =>
            (a.data()['name'] as String? ?? '').toLowerCase().compareTo((b.data()['name'] as String? ?? '').toLowerCase()));
 
        return SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: const Text('All'),
                  selected: _selectedGroupId == null,
                  onSelected: (_) => setState(() => _selectedGroupId = null),
                ),
              ),
              for (final group in sorted)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(group.data()['name'] as String? ?? 'Unnamed'),
                    selected: _selectedGroupId == group.id,
                    onSelected: (_) => setState(() => _selectedGroupId = group.id),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
 
  Widget _buildContactsList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: firestore.collection('contacts').where('companyId', isEqualTo: _companyId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Error loading contacts: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
 
        var docs = [...snapshot.data!.docs];
        docs.sort((a, b) =>
            (a.data()['name'] as String? ?? '').toLowerCase().compareTo((b.data()['name'] as String? ?? '').toLowerCase()));
 
        if (_selectedGroupId != null) {
          docs = docs.where((d) => d.data()['groupId'] == _selectedGroupId).toList();
        }
        if (_searchText.isNotEmpty) {
          docs = docs.where((d) {
            final data = d.data();
            final name = (data['name'] as String? ?? '').toLowerCase();
            final phone = (data['phoneNumber'] as String? ?? '').toLowerCase();
            final email = (data['email'] as String? ?? '').toLowerCase();
            return name.contains(_searchText) || phone.contains(_searchText) || email.contains(_searchText);
          }).toList();
        }
 
        if (docs.isEmpty) {
          return Center(
            child: Text(
              snapshot.data!.docs.isEmpty ? 'No contacts yet' : 'No contacts match',
              style: TextStyle(color: Colors.grey[600]),
            ),
          );
        }
 
        return ListView.separated(
          padding: const EdgeInsets.only(top: 4),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();
            final name = data['name'] as String? ?? 'Unnamed';
            final phone = data['phoneNumber'] as String?;
            final email = data['email'] as String?;
            final isSynced = data['source'] == 'synced';
 
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 1)),
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.blue[50],
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: TextStyle(color: Colors.blue[700], fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            ),
                            if (isSynced) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.grey[200],
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'Synced',
                                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (phone != null && phone.isNotEmpty)
                          Text(phone, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                        if (email != null && email.isNotEmpty)
                          Text(email, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit',
                    icon: const Icon(Icons.edit, size: 18),
                    color: Colors.grey[600],
                    onPressed: () => _openContactDialog(
                      contactId: doc.id,
                      initialName: name,
                      initialPhone: phone ?? '',
                      initialEmail: email ?? '',
                      initialGroupId: data['groupId'] as String?,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete, size: 18),
                    color: Colors.red,
                    onPressed: () => _confirmDeleteContact(doc.id, name),
                  ),
                ],
              ),
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
      backgroundColor: Colors.grey[100],
      body: _loadingCompany
          ? const Center(child: CircularProgressIndicator())
          : _companyId == null
              ? const Center(child: Text('Could not determine your company'))
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Contacts',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _searchController,
                          decoration: kInputDecoration.copyWith(
                            hintText: 'Search contacts',
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
                        _buildGroupChips(),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => _openContactDialog(),
                                icon: const Icon(Icons.person_add),
                                label: const Text('Add Contact'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                            if (_isBoss) ...[
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _syncing ? null : _syncWithPhoneContacts,
                                  icon: _syncing
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.sync),
                                  label: const Text('Sync Phone'),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 12),
                        Expanded(child: _buildContactsList()),
                      ],
                    ),
                  ),
                ),
    );
  }
}