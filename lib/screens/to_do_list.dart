import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:contractor_hub/components/app_bar.dart';
import 'package:contractor_hub/components/time_ago.dart';
import 'package:contractor_hub/constants.dart';
import 'package:contractor_hub/services/firebase_services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

final auth = FirebaseAuth.instance;
final firebase = FirebaseFirestore.instance;
final services = FirebaseServices.instance;

// Simple in-memory cache so the same creator's name isn't re-fetched from
// Firestore for every tile on every stream rebuild (the ToDoItems stream
// re-emits for the whole collection whenever any single doc changes).
final Map<String, Future<Map<String, dynamic>?>> _userCache = {};

Future<Map<String, dynamic>?> _cachedGetUser(String uid) {
  return _userCache.putIfAbsent(uid, () => services.getUser(uid));
}

/// Formats a *future-facing* date (like a task's completion date) as
/// "Due in 3 days" / "Due today" / "Overdue by 2 days". Deliberately
/// separate from `formatTimeAgo`, which is written for past timestamps
/// (createdAt, clock-in times) and reads oddly applied to a future date.
String _formatDueDate(Timestamp dueTimestamp) {
  final due = dueTimestamp.toDate();
  final now = DateTime.now();
  final dueDay = DateTime(due.year, due.month, due.day);
  final today = DateTime(now.year, now.month, now.day);
  final dayDiff = dueDay.difference(today).inDays;

  if (dayDiff == 0) return 'Due today';
  if (dayDiff == 1) return 'Due tomorrow';
  if (dayDiff > 1) return 'Due in $dayDiff days';
  if (dayDiff == -1) return 'Overdue by 1 day';
  return 'Overdue by ${-dayDiff} days';
}

class ToDoList extends StatefulWidget {
  const ToDoList({super.key});

  @override
  State<ToDoList> createState() => _ToDoListState();
}

class _ToDoListState extends State<ToDoList> {
  TextEditingController newTaskController = TextEditingController();
  DateTime? _completionDate;
  String? _companyName;

  String get _currentUserUid => auth.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    _loadCompany();
  }

  @override
  void dispose() {
    newTaskController.dispose();
    super.dispose();
  }

  Future<void> _loadCompany() async {
    final user = await services.getUser(_currentUserUid);
    if (mounted) {
      setState(() {
        _companyName = user?['companyName'] as String?;
      });
    }
  }

  Future<void> _pickDate(
    BuildContext context,
    StateSetter setSheetState,
  ) async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _completionDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (pickedDate != null) {
      setSheetState(() => _completionDate = pickedDate);
    }
  }

  Future<void> _openNewTask() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 12,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'New Task',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: newTaskController,
                      autofocus: true,
                      decoration: kInputDecoration.copyWith(
                        hintText: 'e.g. take out garbage',
                        prefixIcon: const Icon(Icons.task_alt),
                      ),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: () => _pickDate(sheetContext, setSheetState),
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: Text(
                        _completionDate == null
                            ? 'Set completion date'
                            : '${_completionDate!.month}/${_completionDate!.day}/${_completionDate!.year}',
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        alignment: Alignment.centerLeft,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              _completionDate = null;
                              Navigator.pop(sheetContext);
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: () async {
                              if (newTaskController.text.trim().isEmpty ||
                                  _companyName == null) {
                                return;
                              }
                              final message = newTaskController.text.trim();
                              final completionDate = _completionDate;

                              try {
                                await firebase.collection('ToDoItems').add({
                                  'message': message,
                                  'createdAt': FieldValue.serverTimestamp(),
                                  'completionDate': completionDate == null
                                      ? null
                                      : Timestamp.fromDate(completionDate),
                                  'createdBy': _currentUserUid,
                                  'companyName': _companyName,
                                  'isCompleted': false,
                                });
                                if (sheetContext.mounted) {
                                  Navigator.pop(sheetContext);
                                }
                                newTaskController.clear();
                                if (mounted) {
                                  setState(() => _completionDate = null);
                                }
                              } catch (e) {
                                if (sheetContext.mounted) {
                                  ScaffoldMessenger.of(
                                    sheetContext,
                                  ).showSnackBar(
                                    SnackBar(
                                      content: Text('Could not save task: $e'),
                                    ),
                                  );
                                }
                              }
                            },
                            child: const Text('Save'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
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
      body: SafeArea(
        child: _companyName == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(child: ToDoListItems(companyName: _companyName!)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: ElevatedButton.icon(
                      onPressed: _openNewTask,
                      icon: const Icon(Icons.add),
                      label: const Text('Add task'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class ToDoListItems extends StatelessWidget {
  final String companyName;

  const ToDoListItems({super.key, required this.companyName});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: firebase
          .collection('ToDoItems')
          .where('companyName', isEqualTo: companyName)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.checklist_rtl, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 8),
                Text(
                  'No things to do yet',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        final docs = snapshot.data!.docs;
        final openTiles = <ToDoTile>[];
        final doneTiles = <ToDoTile>[];

        for (final doc in docs) {
          try {
            final data = doc.data() as Map<String, dynamic>;
            final toDoMessage = data['message'] as String;
            // Nullable: a task may be saved with no completion date picked,
            // and older docs won't have isCompleted at all.
            final completionDate = data['completionDate'] as Timestamp?;
            final createdAt = data['createdAt'] as Timestamp?;
            final createdByUid = data['createdBy'] as String;
            final isCompleted = data['isCompleted'] as bool? ?? false;

            final tile = ToDoTile(
              completionDate: completionDate,
              toDoMessage: toDoMessage,
              createdAt: createdAt,
              createdByUid: createdByUid,
              toDoId: doc.id,
              isCompleted: isCompleted,
            );

            (isCompleted ? doneTiles : openTiles).add(tile);
          } catch (e) {
            continue;
          }
        }

        // Open tasks first, completed tasks pushed to the bottom.
        final tiles = [...openTiles, ...doneTiles];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  const Text(
                    'To Do List',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${openTiles.length} open · ${doneTiles.length} done',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                itemCount: tiles.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) => tiles[index],
              ),
            ),
          ],
        );
      },
    );
  }
}

class ToDoTile extends StatelessWidget {
  final String toDoMessage;
  final Timestamp? completionDate;
  final Timestamp? createdAt;
  final String createdByUid;
  final String toDoId;
  final bool isCompleted;

  const ToDoTile({
    super.key,
    required this.completionDate,
    required this.toDoMessage,
    required this.createdAt,
    required this.createdByUid,
    required this.toDoId,
    required this.isCompleted,
  });

  Future<void> _toggleCompleted(BuildContext context) async {
    try {
      await firebase.collection('ToDoItems').doc(toDoId).update({
        'isCompleted': !isCompleted,
      });
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not update task: $e')));
      }
    }
  }

  Future<void> _editToDoItem(BuildContext context) async {
    final messageController = TextEditingController(text: toDoMessage);
    DateTime? editedDate = completionDate?.toDate();

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
                title: const Text('Edit task'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: messageController,
                        autofocus: true,
                        decoration: kInputDecoration.copyWith(hintText: 'Task'),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: dialogContext,
                            initialDate: editedDate ?? DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setDialogState(() => editedDate = picked);
                          }
                        },
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: Text(
                          editedDate == null
                              ? 'Set completion date'
                              : '${editedDate!.month}/${editedDate!.day}/${editedDate!.year}',
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          alignment: Alignment.centerLeft,
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
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      final newMessage = messageController.text.trim();
                      if (newMessage.isEmpty) return;

                      try {
                        await firebase
                            .collection('ToDoItems')
                            .doc(toDoId)
                            .update({
                              'message': newMessage,
                              'completionDate': editedDate == null
                                  ? null
                                  : Timestamp.fromDate(editedDate!),
                            });
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      } catch (e) {
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(
                              content: Text('Could not save changes: $e'),
                            ),
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
      messageController.dispose();
    }
  }

  Future<void> _deleteToDo(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Delete this task?',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          content: Text('"$toDoMessage" will be removed for everyone.'),
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
                  await firebase.collection('ToDoItems').doc(toDoId).delete();
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                } catch (e) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text('Could not delete task: $e')),
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

  @override
  Widget build(BuildContext context) {
    final due = completionDate;
    final isOverdue =
        !isCompleted &&
        due != null &&
        DateTime(
          due.toDate().year,
          due.toDate().month,
          due.toDate().day,
        ).isBefore(
          DateTime(
            DateTime.now().year,
            DateTime.now().month,
            DateTime.now().day,
          ),
        );

    return Container(
      decoration: BoxDecoration(
        color: isCompleted ? Colors.grey[50] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: isCompleted
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
        border: isCompleted ? Border.all(color: Colors.grey[200]!) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: isCompleted,
              activeColor: Colors.blue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              onChanged: (_) => _toggleCompleted(context),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      toDoMessage,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isCompleted ? Colors.grey[500] : Colors.black87,
                        decoration: isCompleted
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (due != null)
                      Row(
                        children: [
                          Icon(
                            Icons.event,
                            size: 14,
                            color: isOverdue ? Colors.red : Colors.blueGrey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatDueDate(due),
                            style: TextStyle(
                              fontSize: 13,
                              color: isCompleted
                                  ? Colors.grey[500]
                                  : (isOverdue ? Colors.red : Colors.blueGrey),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 4),
                    FutureBuilder<Map<String, dynamic>?>(
                      future: _cachedGetUser(createdByUid),
                      builder: (context, snapshot) {
                        final creatorName =
                            snapshot.connectionState == ConnectionState.waiting
                            ? '…'
                            : (snapshot.data?['name'] as String? ??
                                  'Unknown user');

                        return Text(
                          createdAt == null
                              ? 'Created by $creatorName'
                              : 'Created ${formatTimeAgo(createdAt)} by $creatorName',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: Colors.grey[600]),
              onSelected: (value) {
                // Defer to the next event-loop turn: opening a new route
                // (showDialog) synchronously inside PopupMenuButton's
                // onSelected, while the popup menu's own route is still
                // closing, corrupts Flutter's InheritedElement dependents
                // tracking and surfaces later as a
                // "dependents.isEmpty" framework assertion.
                Future.delayed(Duration.zero, () {
                  if (value == 'edit') _editToDoItem(context);
                  if (value == 'delete') _deleteToDo(context);
                });
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 18),
                      SizedBox(width: 8),
                      Text('Edit'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
