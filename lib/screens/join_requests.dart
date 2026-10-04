
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:contractor_hub/components/app_bar.dart';
import 'package:contractor_hub/components/time_ago.dart';
import 'package:contractor_hub/services/firebase_services.dart';
import 'package:flutter/material.dart';
 
final services = FirebaseServices.instance;
 
class JoinRequestsScreen extends StatefulWidget {
  const JoinRequestsScreen({super.key});
 
  @override
  State<JoinRequestsScreen> createState() => _JoinRequestsScreenState();
}
 
class _JoinRequestsScreenState extends State<JoinRequestsScreen> {
  String? _companyId;
 
  @override
  void initState() {
    super.initState();
    _load();
  }
 
  Future<void> _load() async {
    final uid = services.currentUid;
    if (uid == null) return;
    final companyId = await services.getUsersCompanyId(uid);
    if (mounted) setState(() => _companyId = companyId);
  }
 
  Future<void> _confirmApprove(BuildContext context, String uid, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Approve this request?'),
        content: Text('$name will get full access to the company.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
 
    try {
      await services.approveJoinRequest(uid);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$name approved')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not approve: $e')),
        );
      }
    }
  }
 
  Future<void> _confirmDeny(BuildContext context, String uid, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Deny this request?'),
        content: Text("$name's request will be deleted. They can register again if this was a mistake."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Deny'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
 
    try {
      await services.denyJoinRequest(uid);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("$name's request denied")),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not deny: $e')),
        );
      }
    }
  }
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBarWidget(),
      backgroundColor: Colors.grey[100],
      body: _companyId == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: services.pendingJoinRequests(_companyId!),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: Text(
                        'Error loading requests: ${snapshot.error}',
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inbox_outlined, size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 8),
                        Text('No pending requests', style: TextStyle(color: Colors.grey[600])),
                      ],
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data();
                    final name = data['name'] as String? ?? 'Unknown';
                    // NOTE: registration writes this field as 'userEmail',
                    // not 'email' — reading the wrong key silently showed a
                    // blank line for every request.
                    final email = data['userEmail'] as String? ?? '';
                    final requestedAt = data['createdAt'] as Timestamp?;
 
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6, offset: const Offset(0, 2)),
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
                                Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                                if (email.isNotEmpty)
                                  Text(email, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                                if (requestedAt != null)
                                  Text(
                                    'Requested ${formatTimeAgo(requestedAt)}',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Approve',
                            icon: const Icon(Icons.check_circle, color: Colors.green),
                            onPressed: () => _confirmApprove(context, doc.id, name),
                          ),
                          IconButton(
                            tooltip: 'Deny',
                            icon: const Icon(Icons.cancel, color: Colors.red),
                            onPressed: () => _confirmDeny(context, doc.id, name),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}