import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:contractor_hub/components/reusable_icon_button.dart';
import 'package:contractor_hub/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:provider/provider.dart';

// ───────────────────────────────────────────────────────────────────────────
// ROUTE NAMES: change these to match the routes map in main.dart.
// ───────────────────────────────────────────────────────────────────────────
const _kHomeRoute = '/homePage';
const _kWelcomeRoute = '/welcomeScreen';
const _kJoinRequestsRoute = '/joinRequests';
const _kClockRoute = '/clockInOut';

/// Screens the search icon can jump to: (label, route, keywords).
const _kSearchTargets = <(String, String, String)>[
  ('Home', '/homePage', 'main dashboard'),
  ('Clock In / Out', '/clockInOut', 'time hours punch map'),
  ('ToDo List', '/toDoList', 'tasks checklist'),
  (
    'Expense tracker',
    '/expenseTracker',
    'po purchase order cost code receipts',
  ),
  ('Construction Images', '/constructionImages', 'photos pictures jobsite'),
  ('Contacts', '/contacts', 'phone people groups'),
  ('Administrator panel', '/administratorPanel', 'admin boss employees jobs'),
  ('Join requests', _kJoinRequestsRoute, 'pending approve employees'),
];

class AppBarWidget extends StatelessWidget implements PreferredSizeWidget {
  /// Page name, e.g. AppBarWidget(title: 'To Do List').
  final String? title;

  const AppBarWidget({super.key, this.title});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 34);

  void _snack(ScaffoldMessengerState m, String text) =>
      m.showSnackBar(SnackBar(content: Text(text)));

  Future<void> _confirmAndSignOut(BuildContext context) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final AuthProvider auth;
    try {
      auth = context.read<AuthProvider>();
    } catch (e) {
      debugPrint('Logout: AuthProvider lookup failed: $e');
      _snack(
        messenger,
        'Logout failed: AuthProvider is not provided above this screen. ($e)',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to sign in again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await auth.signOut();
    } catch (e) {
      debugPrint('Logout: signOut threw: $e');
      _snack(messenger, 'Could not sign out: $e');
      return;
    }

    try {
      navigator.pushNamedAndRemoveUntil(_kWelcomeRoute, (r) => false);
    } catch (e) {
      debugPrint('Logout: navigation failed: $e');
      _snack(
        messenger,
        "Signed out, but couldn't open $_kWelcomeRoute (is the route registered?): $e",
      );
    }
  }

  void _openProfileSheet(
    BuildContext context,
    Map<String, dynamic>? user,
    bool isBoss,
  ) {
    final name = (user?['name'] as String?) ?? 'Unknown';
    final company = (user?['companyName'] as String?) ?? '';
    final email = FirebaseAuth.instance.currentUser?.email ?? '';

    // Bottom sheet (not PopupMenuButton) on purpose: a popup menu that opens
    // a dialog caused the `dependents.isEmpty` assertion earlier.
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 28,
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(fontSize: 24),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (email.isNotEmpty)
                Text(email, style: TextStyle(color: Colors.grey[600])),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                children: [
                  Chip(
                    label: Text(isBoss ? 'Boss' : 'Employee'),
                    visualDensity: VisualDensity.compact,
                  ),
                  if (company.isNotEmpty)
                    Chip(
                      label: Text(company),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text('Log out'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmAndSignOut(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openNotificationsSheet(BuildContext context, String uid) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (_, scroll) =>
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .collection('notifications')
                  .orderBy('createdAt', descending: true)
                  .limit(50)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const Center(child: Text('No notifications yet'));
                }
                return Column(
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () async {
                          final batch = FirebaseFirestore.instance.batch();
                          for (final d in docs) {
                            if (d.data()['read'] != true) {
                              batch.update(d.reference, {'read': true});
                            }
                          }
                          try {
                            await batch.commit();
                          } catch (e) {
                            debugPrint('mark all read failed: $e');
                          }
                        },
                        child: const Text('Mark all read'),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: scroll,
                        itemCount: docs.length,
                        itemBuilder: (_, i) {
                          final d = docs[i].data();
                          final unread = d['read'] != true;
                          return ListTile(
                            leading: Icon(
                              unread
                                  ? Icons.notifications_active
                                  : Icons.notifications_none,
                              color: unread ? Colors.orange : Colors.grey,
                            ),
                            title: Text(
                              d['title'] as String? ?? 'Notification',
                              style: TextStyle(
                                fontWeight: unread
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: Text(d['body'] as String? ?? ''),
                            onTap: () => docs[i].reference
                                .update({'read': true})
                                .catchError(
                                  (e) => debugPrint('mark read failed: $e'),
                                ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
      ),
    );
  }

  Widget _badge({required int count, required Widget child}) {
    if (count <= 0) return child;
    return Badge(label: Text(count > 99 ? '99+' : '$count'), child: child);
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final db = FirebaseFirestore.instance;

    // One stream of the user's doc. includeMetadataChanges lets us detect
    // "offline" with no extra package: isFromCache stays true with no server.
    final userStream = uid == null
        ? null
        : db
              .collection('users')
              .doc(uid)
              .snapshots(includeMetadataChanges: true);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userStream,
      builder: (context, userSnap) {
        final user = userSnap.data?.data();
        final isBoss =
            user != null && (user['isEmployee'] as bool? ?? true) == false;
        final companyId = user?['companyId'] as String?;
        final offline = userSnap.data?.metadata.isFromCache ?? false;
        final name = (user?['name'] as String?) ?? '';

        return AppBar(
          elevation: 2,
          backgroundColor: Colors.blueGrey[800],
          foregroundColor: Colors.white,
          centerTitle: true,
          automaticallyImplyLeading: false,
          leading: canPop
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Back',
                  onPressed: () => Navigator.pop(context),
                )
              : null,
          title: Text(
            title ?? 'Contractor Hub',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          actions: [
            IconButton(
              tooltip: 'Search',
              icon: const Icon(Icons.search),
              onPressed: () => showSearch<void>(
                context: context,
                delegate: _ScreenSearchDelegate(isBoss: isBoss),
              ),
            ),
            if (uid != null)
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: db
                    .collection('users')
                    .doc(uid)
                    .collection('notifications')
                    .where('read', isEqualTo: false)
                    .snapshots(),
                builder: (context, s) => IconButton(
                  tooltip: 'Notifications',
                  icon: _badge(
                    count: s.data?.docs.length ?? 0,
                    child: const Icon(Icons.notifications_outlined),
                  ),
                  onPressed: () => _openNotificationsSheet(context, uid),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Tooltip(
                message: 'Profile',
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _openProfileSheet(context, user, isBoss),
                  child: CircleAvatar(
                    radius: 15,
                    backgroundColor: Colors.white24,
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(34),
            child: SizedBox(
              height: 50,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ReusableIconButton(
                    onPressed: () => Navigator.pushNamedAndRemoveUntil(
                      context,
                      _kHomeRoute,
                      (r) => false,
                    ),
                    icon: const Icon(Icons.home),
                  ),
                  // Boss only: pending join requests with a count badge.
                  if (isBoss && companyId != null)
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: db
                          .collection('users')
                          .where('companyId', isEqualTo: companyId)
                          .where('status', isEqualTo: 'pending')
                          .snapshots(),
                      builder: (context, s) {
                        final count = s.data?.docs.length ?? 0;
                        if (count == 0) return const SizedBox.shrink();
                        return IconButton(
                          tooltip: 'Join requests',
                          icon: _badge(
                            count: count,
                            child: const Icon(Icons.person_add_alt_1),
                          ),
                          onPressed: () =>
                              Navigator.pushNamed(context, _kJoinRequestsRoute),
                        );
                      },
                    ),
                  // Clocked-in chip (open clockRecord = no clockOutTime).
                  if (uid != null)
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: db
                          .collection('clockRecords')
                          .where('uid', isEqualTo: uid)
                          .where('clockOutTime', isNull: true)
                          .limit(1)
                          .snapshots(),
                      builder: (context, s) {
                        final docs = s.data?.docs ?? [];
                        if (docs.isEmpty) return const SizedBox.shrink();
                        final site =
                            docs.first.data()['jobSiteName'] as String? ??
                            'a job';
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: ActionChip(
                            backgroundColor: Colors.green[600],
                            side: BorderSide.none,
                            visualDensity: VisualDensity.compact,
                            avatar: const Icon(
                              Icons.circle,
                              size: 10,
                              color: Colors.white,
                            ),
                            label: Text(
                              'Clocked in: $site',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                            onPressed: () =>
                                Navigator.pushNamed(context, _kClockRoute),
                          ),
                        );
                      },
                    ),
                  if (offline)
                    const Tooltip(
                      message:
                          "Offline. Changes will sync when you're back online.",
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(
                          Icons.cloud_off,
                          size: 20,
                          color: Colors.orangeAccent,
                        ),
                      ),
                    ),
                  ReusableIconButton(
                    onPressed: () => _confirmAndSignOut(context),
                    icon: const Icon(Icons.logout),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Search that jumps to a screen by name or keyword.
class _ScreenSearchDelegate extends SearchDelegate<void> {
  final bool isBoss;
  _ScreenSearchDelegate({required this.isBoss})
    : super(searchFieldLabel: 'Search screens');

  List<(String, String, String)> _matches() {
    final q = query.trim().toLowerCase();
    return _kSearchTargets.where((t) {
      final bossOnly =
          t.$2 == '/administratorPanel' || t.$2 == _kJoinRequestsRoute;
      if (bossOnly && !isBoss) return false;
      return q.isEmpty ||
          t.$1.toLowerCase().contains(q) ||
          t.$3.toLowerCase().contains(q);
    }).toList();
  }

  @override
  List<Widget>? buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, null),
  );

  @override
  Widget buildResults(BuildContext context) => _list(context);

  @override
  Widget buildSuggestions(BuildContext context) => _list(context);

  Widget _list(BuildContext context) {
    final items = _matches();
    if (items.isEmpty) return const Center(child: Text('No matching screens'));
    return ListView(
      children: [
        for (final t in items)
          ListTile(
            leading: const Icon(Icons.arrow_forward),
            title: Text(t.$1),
            onTap: () {
              final nav = Navigator.of(context);
              close(context, null);
              nav.pushNamed(t.$2);
            },
          ),
      ],
    );
  }
}
