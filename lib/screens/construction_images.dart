import 'dart:io';
 
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:contractor_hub/components/app_bar.dart';
import 'package:contractor_hub/components/time_ago.dart';
import 'package:contractor_hub/constants.dart';
import 'package:contractor_hub/services/firebase_services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
 
/// One photo, parsed once from its Firestore doc so the UI never has to
/// cast raw map values (the old code crashed on a null note, a null
/// uploader, and a Timestamp cast to String).
class _Photo {
  final String id;
  final String? imageUrl; // Firebase Storage download URL (visible to everyone)
  final String path; // legacy: local device path from before Storage
  final String note;
  final String? uploadedBy;
  final Timestamp? uploadedAt;
 
  const _Photo({
    required this.id,
    required this.imageUrl,
    required this.path,
    required this.note,
    required this.uploadedBy,
    required this.uploadedAt,
  });
 
  factory _Photo.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return _Photo(
      id: doc.id,
      imageUrl: d['imageUrl'] as String?,
      path: d['imagePath'] as String? ?? '',
      note: (d['note'] as String?)?.trim() ?? '',
      uploadedBy: d['uploadedBy'] as String?,
      // serverTimestamp() is null in the local snapshot until the server
      // confirms the write.
      uploadedAt: d['uploadedAt'] as Timestamp?,
    );
  }
}
 
class _PhotoChoice {
  final ImageSource source;
  final String note;
  const _PhotoChoice(this.source, this.note);
}
 
class ConstructionImages extends StatefulWidget {
  const ConstructionImages({super.key});
 
  @override
  State<ConstructionImages> createState() => _ConstructionImagesState();
}
 
class _ConstructionImagesState extends State<ConstructionImages> {
  final services = FirebaseServices.instance;
  final auth = FirebaseAuth.instance;
  final firestore = FirebaseFirestore.instance;
  final storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();
 
  // Filters (applied on-device to the selected job's photos).
  final _searchController = TextEditingController();
  String _noteQuery = '';
  bool _onlyMine = false;
  DateTimeRange? _dateRange;
 
  bool _loadingCompanyInfo = true;
  String? _companyId;
  String? _companyPaymentPlan;
  int _maxCompanyImages = 0;
 
  Stream<QuerySnapshot<Map<String, dynamic>>>? _jobsStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _foldersStream;
  String? selectedJobId;
 
  // One lookup per uploader, shared by every card and the full-screen viewer.
  final Map<String, Future<String?>> _nameFutures = {};
  Future<String?> _nameOf(String uid) =>
      _nameFutures.putIfAbsent(uid, () => services.getUserNameByUid(uid));
 
  @override
  void initState() {
    super.initState();
    _loadCompanyInfo();
  }
 
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
 
  Future<void> _loadCompanyInfo() async {
    setState(() => _loadingCompanyInfo = true);
 
    try {
      final uid = auth.currentUser?.uid;
      if (uid == null) {
        setState(() {
          _companyId = null;
          _loadingCompanyInfo = false;
        });
        return;
      }
 
      final userDoc = await firestore.collection('users').doc(uid).get();
      final fetchedCompanyId = userDoc.data()?['companyId'] as String?;
 
      if (fetchedCompanyId == null) {
        setState(() {
          _companyId = null;
          _loadingCompanyInfo = false;
        });
        return;
      }
 
      final companyDoc =
          await firestore.collection('companies').doc(fetchedCompanyId).get();
      final plan =
          companyDoc.data()?['companyPaymentPlan'] as String? ?? 'small';
 
      if (!mounted) return;
      setState(() {
        _companyId = fetchedCompanyId;
        _companyPaymentPlan = plan;
        _maxCompanyImages = _maxImagesForPlan(plan);
        _jobsStream = services.jobsForCompany(fetchedCompanyId);
        _foldersStream = firestore
            .collection('imageFolders')
            .where('companyId', isEqualTo: fetchedCompanyId)
            .snapshots();
        _loadingCompanyInfo = false;
      });
    } catch (e) {
      debugPrint('error loading company info: $e');
      if (!mounted) return;
      setState(() {
        _companyId = null;
        _loadingCompanyInfo = false;
      });
    }
  }
 
  int _maxImagesForPlan(String plan) {
    switch (plan) {
      case 'medium':
        return 2000;
      case 'large':
        return 1000000000;
      case 'small':
      default:
        return 250;
    }
  }
 
  Future<int> _currentCompanyImageCount() async {
    if (_companyId == null) return 0;
    final countSnapshot = await firestore
        .collection('jobImages')
        .where('companyId', isEqualTo: _companyId)
        .count()
        .get();
    return countSnapshot.count ?? 0;
  }
 
  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
 
  Future<void> _addImages(String jobId) async {
    if (_companyId == null) {
      _snack('Could not determine your company');
      return;
    }
 
    final currentCount = await _currentCompanyImageCount();
    if (currentCount >= _maxCompanyImages) {
      _snack(
        'Your company has reached its image limit ($_maxCompanyImages) for '
        'the $_companyPaymentPlan plan. Upgrade to add more.',
      );
      return;
    }
    if (!mounted) return;
 
    final choice = await showDialog<_PhotoChoice>(
      context: context,
      builder: (_) => const _AddPhotoDialog(),
    );
    if (choice == null) return;
 
    final picked = await _picker
        .pickImage(
          source: choice.source,
          imageQuality: 85,
          maxWidth: 2560, // keeps uploads small without hurting legibility
        )
        .catchError((Object e) {
      _snack('Could not open the picker: $e');
      return null;
    });
    if (picked == null || !mounted) return;
    await _uploadPhoto(picked, jobId, choice.note);
  }
 
  /// Uploads to Firebase Storage, then records the download URL in
  /// Firestore. Photos are never edited or deleted afterwards.
  Future<void> _uploadPhoto(XFile picked, String jobId, String note) async {
    final uid = auth.currentUser?.uid;
    if (uid == null || _companyId == null) return;
 
    final progress = ValueNotifier<double>(0);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Uploading photo'),
          content: ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (_, v, __) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: v == 0 ? null : v),
                const SizedBox(height: 8),
                Text('${(v * 100).round()}%'),
              ],
            ),
          ),
        ),
      ),
    );
 
    try {
      final bytes = await picked.readAsBytes();
      final dot = picked.name.lastIndexOf('.');
      final ext = dot == -1 ? 'jpg' : picked.name.substring(dot + 1).toLowerCase();
      final contentType =
          picked.mimeType ?? (ext == 'png' ? 'image/png' : 'image/jpeg');
      final path = 'companies/$_companyId/jobImages/$jobId/'
          '${DateTime.now().millisecondsSinceEpoch}_$uid.$ext';
 
      final ref = storage.ref(path);
      final task = ref.putData(bytes, SettableMetadata(contentType: contentType));
      final sub = task.snapshotEvents.listen((s) {
        if (s.totalBytes > 0) progress.value = s.bytesTransferred / s.totalBytes;
      });
      await task;
      await sub.cancel();
      final url = await ref.getDownloadURL();
 
      await firestore.collection('jobImages').add({
        'companyId': _companyId,
        'jobId': jobId,
        'imageUrl': url,
        'storagePath': path,
        'uploadedAt': FieldValue.serverTimestamp(),
        'uploadedBy': uid,
        'note': note,
      });
    } catch (e) {
      _snack('Failed to upload image: $e');
    } finally {
      if (mounted) Navigator.of(context).pop(); // close the progress dialog
    }
  }
 
  Future<void> _addFolder(List<String> existingNames) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NewFolderDialog(existingNames: existingNames),
    );
    if (name == null || _companyId == null) return;
    try {
      final ref = await firestore.collection('imageFolders').add({
        'companyId': _companyId,
        'name': name,
        'createdBy': auth.currentUser?.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) setState(() => selectedJobId = ref.id);
    } catch (e) {
      _snack('Could not create folder: $e');
    }
  }
 
  void _openViewer(List<_Photo> photos, int index) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => _FullScreenViewer(
          photos: photos,
          initialIndex: index,
          nameOf: _nameOf,
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }
 
  /// Jobs (from the Jobs screen, the same names clock in/out uses) followed
  /// by image-only folders. Folders live in their own collection, so they
  /// never appear anywhere else in the app.
  Widget _buildJobPickerRow() {
    final jobsStream = _jobsStream;
    if (jobsStream == null) {
      return const Center(child: Text('Could not load jobs'));
    }
 
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: jobsStream,
      builder: (context, jobsSnap) {
        if (jobsSnap.hasError) {
          return Center(child: Text('Error: ${jobsSnap.error}'));
        }
        if (!jobsSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
 
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _foldersStream,
          builder: (context, folderSnap) {
            if (folderSnap.hasError) {
              return Center(child: Text('Folders error: ${folderSnap.error}'));
            }
            final jobs = jobsSnap.data!.docs;
            // Sorted on-device so no extra Firestore index is needed.
            final folders = [...(folderSnap.data?.docs ?? [])]..sort((a, b) =>
                (a.data()['name'] as String? ?? '')
                    .toLowerCase()
                    .compareTo((b.data()['name'] as String? ?? '').toLowerCase()));
            final folderNames =
                folders.map((f) => f.data()['name'] as String? ?? '').toList();
 
            return ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                SizedBox(
                  width: 110,
                  child: _NewFolderCard(onTap: () => _addFolder(folderNames)),
                ),
                for (final doc in jobs)
                  _pickerItem(
                    id: doc.id,
                    name: doc.data()['name'] as String? ?? 'Unnamed job',
                    isFolder: false,
                  ),
                for (final doc in folders)
                  _pickerItem(
                    id: doc.id,
                    name: doc.data()['name'] as String? ?? 'Unnamed folder',
                    isFolder: true,
                  ),
              ],
            );
          },
        );
      },
    );
  }
 
  Widget _pickerItem({
    required String id,
    required String name,
    required bool isFolder,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: SizedBox(
        width: 150,
        child: _JobCard(
          jobName: name,
          isFolder: isFolder,
          isSelected: selectedJobId == id,
          onTap: () => setState(() => selectedJobId = id),
          onAddPhoto: () => _addImages(id),
        ),
      ),
    );
  }
 
  // ───────────────────────── filters ─────────────────────────
 
  bool get _filtersActive =>
      _noteQuery.isNotEmpty || _onlyMine || _dateRange != null;
 
  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _noteQuery = '';
      _onlyMine = false;
      _dateRange = null;
    });
  }
 
  List<_Photo> _applyFilters(List<_Photo> all) {
    if (!_filtersActive) return all;
    final me = auth.currentUser?.uid;
    final q = _noteQuery.toLowerCase();
    // Inclusive of the whole last day.
    final from = _dateRange?.start;
    final until = _dateRange?.end.add(const Duration(days: 1));
 
    return all.where((p) {
      if (_onlyMine && p.uploadedBy != me) return false;
      if (q.isNotEmpty && !p.note.toLowerCase().contains(q)) return false;
      if (_dateRange != null) {
        final t = p.uploadedAt?.toDate();
        if (t == null) return false;
        if (t.isBefore(from!) || !t.isBefore(until!)) return false;
      }
      return true;
    }).toList();
  }
 
  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _dateRange,
    );
    if (r != null) setState(() => _dateRange = r);
  }
 
  String _rangeLabel(DateTimeRange r) {
    String d(DateTime x) => '${x.month}/${x.day}/${x.year % 100}';
    return r.start == r.end ? d(r.start) : '${d(r.start)} – ${d(r.end)}';
  }
 
  Widget _buildFilterBar({required int shown, required int total}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _noteQuery = v.trim()),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search notes',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _noteQuery.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _noteQuery = '');
                      },
                    ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  label: const Text('Added by me'),
                  avatar: const Icon(Icons.person, size: 16),
                  selected: _onlyMine,
                  onSelected: (v) => setState(() => _onlyMine = v),
                ),
                const SizedBox(width: 8),
                InputChip(
                  label: Text(_dateRange == null
                      ? 'Date'
                      : _rangeLabel(_dateRange!)),
                  avatar: const Icon(Icons.date_range, size: 16),
                  selected: _dateRange != null,
                  onPressed: _pickDateRange,
                  onDeleted: _dateRange == null
                      ? null
                      : () => setState(() => _dateRange = null),
                ),
                if (_filtersActive) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _clearFilters,
                    child: const Text('Clear all'),
                  ),
                ],
              ],
            ),
          ),
          if (_filtersActive)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Showing $shown of $total',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ),
        ],
      ),
    );
  }
 
  Widget _buildImageGrid() {
    final jobId = selectedJobId;
    if (jobId == null) {
      return Center(
        child: Text(
          'Select a job above to see and add its photos',
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }
 
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: firestore
          .collection('jobImages')
          .where('companyId', isEqualTo: _companyId)
          .where('jobId', isEqualTo: jobId)
          // Needs a composite index (companyId, jobId, uploadedAt desc); the
          // console prints a link to create it the first time.
          .orderBy('uploadedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('${snapshot.error}');
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
 
        final all = snapshot.data!.docs.map(_Photo.fromDoc).toList();
        final photos = _applyFilters(all);
        if (all.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.photo_library_outlined,
                    size: 48, color: Colors.grey[400]),
                const SizedBox(height: 8),
                Text('No photos for this job yet',
                    style: TextStyle(color: Colors.grey[600])),
              ],
            ),
          );
        }
 
        return Column(
          children: [
            _buildFilterBar(shown: photos.length, total: all.length),
            Expanded(
              child: photos.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off,
                              size: 44, color: Colors.grey[400]),
                          const SizedBox(height: 8),
                          Text('No photos match these filters',
                              style: TextStyle(color: Colors.grey[600])),
                          TextButton(
                            onPressed: _clearFilters,
                            child: const Text('Clear filters'),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(4),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 220,
                        childAspectRatio: 0.72,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: photos.length,
                      itemBuilder: (context, index) {
                        final p = photos[index];
                        return _PhotoCard(
                          photo: p,
                          nameFuture: p.uploadedBy == null
                              ? null
                              : _nameOf(p.uploadedBy!),
                          onTap: () => _openViewer(photos, index),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppBarWidget(title: 'Construction Images'),
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: _loadingCompanyInfo
            ? const Center(child: CircularProgressIndicator())
            : _companyId == null
                ? const Center(child: Text('Could not determine your company'))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 12),
                      SizedBox(height: 120, child: _buildJobPickerRow()),
                      const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Divider(height: 1),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: _buildImageGrid(),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
 
// ───────────────────────── photo card ─────────────────────────
 
String _agoText(Timestamp? t) => t == null ? 'just now' : formatTimeAgo(t);
 
/// Image on top; note, uploader and time all inside the same rounded card.
class _PhotoCard extends StatelessWidget {
  final _Photo photo;
  final Future<String?>? nameFuture;
  final VoidCallback onTap;
 
  const _PhotoCard({
    required this.photo,
    required this.nameFuture,
    required this.onTap,
  });
 
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  onTap: onTap,
                  child: Hero(
                    tag: 'photo-${photo.id}',
                    child: _PhotoImage(photo: photo, fit: BoxFit.cover, thumb: true),
                  ),
                ),
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: IgnorePointer(
                    child: CircleAvatar(
                      radius: 12,
                      backgroundColor: Colors.black54,
                      child: const Icon(Icons.fullscreen,
                          size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  photo.note.isEmpty ? 'No note' : photo.note,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: photo.note.isEmpty ? Colors.grey : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                FutureBuilder<String?>(
                  future: nameFuture,
                  builder: (context, snap) => Text(
                    'By ${snap.data ?? (nameFuture == null ? 'unknown' : '…')}'
                    ' · ${_agoText(photo.uploadedAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
 
class _PhotoImage extends StatelessWidget {
  final _Photo photo;
  final BoxFit fit;
  final bool thumb;
  const _PhotoImage({required this.photo, required this.fit, this.thumb = false});
 
  Widget _missing(String text) => Container(
        color: Colors.grey[200],
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_not_supported, color: Colors.grey[500]),
            const SizedBox(height: 4),
            Text(text, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          ],
        ),
      );
 
  @override
  Widget build(BuildContext context) {
    final url = photo.imageUrl;
    if (url != null) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: fit,
        // Grid thumbnails decode at a small size so a long list stays smooth;
        // the full-screen viewer loads the original.
        memCacheWidth: thumb ? 600 : null,
        placeholder: (_, __) => Container(
          color: Colors.grey[200],
          alignment: Alignment.center,
          child: const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        errorWidget: (_, __, ___) => _missing('Could not load'),
      );
    }
    // Photos added before Storage only exist on the uploader's device.
    if (!kIsWeb && photo.path.isNotEmpty) {
      return Image.file(
        File(photo.path),
        fit: fit,
        errorBuilder: (_, __, ___) => _missing('Old photo, not on this device'),
      );
    }
    return _missing('No image');
  }
}
 
// ───────────────────────── full-screen viewer ─────────────────────────
 
class _FullScreenViewer extends StatefulWidget {
  final List<_Photo> photos;
  final int initialIndex;
  final Future<String?> Function(String uid) nameOf;
 
  const _FullScreenViewer({
    required this.photos,
    required this.initialIndex,
    required this.nameOf,
  });
 
  @override
  State<_FullScreenViewer> createState() => _FullScreenViewerState();
}
 
class _FullScreenViewerState extends State<_FullScreenViewer> {
  late final PageController _pages =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  final _zoom = TransformationController();
  bool _zoomed = false;
  bool _showChrome = true;
 
  @override
  void initState() {
    super.initState();
    // Lock page swiping while zoomed so panning a zoomed photo doesn't flip
    // to the next one.
    _zoom.addListener(() {
      final zoomed = _zoom.value.getMaxScaleOnAxis() > 1.01;
      if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
    });
  }
 
  @override
  void dispose() {
    _zoom.dispose();
    _pages.dispose();
    super.dispose();
  }
 
  String _fullDate(Timestamp? t) {
    if (t == null) return 'just now';
    final d = t.toDate().toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }
 
  @override
  Widget build(BuildContext context) {
    final p = widget.photos[_index];
 
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pages,
            itemCount: widget.photos.length,
            // Don't let the page swipe fight with pinch-zoom panning.
            physics: _zoomed
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            onPageChanged: (i) {
              _zoom.value = Matrix4.identity();
              setState(() => _index = i);
            },
            itemBuilder: (context, i) {
              final photo = widget.photos[i];
              return GestureDetector(
                onTap: () => setState(() => _showChrome = !_showChrome),
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  // Only the visible page uses the controller.
                  transformationController: i == _index ? _zoom : null,
                  child: Center(
                    child: Hero(
                      tag: 'photo-${photo.id}',
                      child: _PhotoImage(photo: photo, fit: BoxFit.contain),
                    ),
                  ),
                ),
              );
            },
          ),
          if (_showChrome) ...[
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                      Text(
                        '${_index + 1} / ${widget.photos.length}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(width: 12),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (p.note.isNotEmpty)
                        Text(p.note,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      FutureBuilder<String?>(
                        future: p.uploadedBy == null
                            ? null
                            : widget.nameOf(p.uploadedBy!),
                        builder: (context, snap) => Text(
                          'By ${snap.data ?? (p.uploadedBy == null ? 'unknown' : '…')}'
                          ' · ${_fullDate(p.uploadedAt)}',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
 
// ───────────────────────── add-photo dialog ─────────────────────────
 
class _AddPhotoDialog extends StatefulWidget {
  const _AddPhotoDialog();
 
  @override
  State<_AddPhotoDialog> createState() => _AddPhotoDialogState();
}
 
class _AddPhotoDialogState extends State<_AddPhotoDialog> {
  final _note = TextEditingController();
 
  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }
 
  void _pick(ImageSource source) =>
      Navigator.pop(context, _PhotoChoice(source, _note.text.trim()));
 
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Add a photo'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
              decoration: kInputDecoration.copyWith(
                hintText: 'Note (e.g. image of ductwork)',
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pick(ImageSource.gallery),
                    icon: const Icon(Icons.image),
                    label: const Text('Gallery'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pick(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Camera'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
 
// ───────────────────────── job card ─────────────────────────
 
class _JobCard extends StatelessWidget {
  final String jobName;
  final bool isFolder;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onAddPhoto;
 
  const _JobCard({
    required this.jobName,
    required this.isFolder,
    required this.isSelected,
    required this.onTap,
    required this.onAddPhoto,
  });
 
  @override
  Widget build(BuildContext context) {
    final base = isFolder ? Colors.teal : Colors.blue;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected ? base : base[700],
          borderRadius: BorderRadius.circular(12),
          border: isSelected ? Border.all(color: base[900]!, width: 2) : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isFolder)
                  const Padding(
                    padding: EdgeInsets.only(right: 4, top: 1),
                    child: Icon(Icons.folder, color: Colors.white70, size: 16),
                  ),
                Expanded(
                  child: Text(
                    jobName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                onPressed: onAddPhoto,
                icon: const Icon(Icons.add_a_photo, color: Colors.white, size: 20),
                tooltip: 'Add photo',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
 
class _NewFolderCard extends StatelessWidget {
  final VoidCallback onTap;
  const _NewFolderCard({required this.onTap});
 
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.teal, width: 1.5),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.create_new_folder, color: Colors.teal, size: 30),
            SizedBox(height: 6),
            Text('New folder',
                style: TextStyle(
                    color: Colors.teal,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
 
class _NewFolderDialog extends StatefulWidget {
  final List<String> existingNames;
  const _NewFolderDialog({required this.existingNames});
 
  @override
  State<_NewFolderDialog> createState() => _NewFolderDialogState();
}
 
class _NewFolderDialogState extends State<_NewFolderDialog> {
  final _controller = TextEditingController();
  String? _error;
 
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
 
  void _create() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a folder name');
      return;
    }
    if (widget.existingNames.any((n) => n.toLowerCase() == name.toLowerCase())) {
      setState(() => _error = 'A folder with that name already exists');
      return;
    }
    Navigator.pop(context, name);
  }
 
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('New image folder'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Folder name',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _create(),
          ),
          const SizedBox(height: 8),
          Text(
            'Folders only hold photos. They are not jobs, so they won\'t '
            'appear in clock in/out, expenses or anywhere else.',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _create, child: const Text('Create')),
      ],
    );
  }
}