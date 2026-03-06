import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';
import '../services/web_notifications.dart';
import '../services/local_notifications.dart';
import 'login_screen.dart';
import 'driver_location_screen.dart';

class ParentDashboard extends StatefulWidget {
  const ParentDashboard({Key? key}) : super(key: key);

  @override
  State<ParentDashboard> createState() => _ParentDashboardState();
}

class _ParentDashboardState extends State<ParentDashboard> {
  final _firestore = FirebaseFirestore.instance;
  final _currentUser = FirebaseAuth.instance.currentUser!;
  int _selectedIndex = 2;
  final Set<String> _shownNotificationIds = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _notifSub;
  bool _requestedWebNotificationPermission = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb && !_requestedWebNotificationPermission) {
      _requestedWebNotificationPermission = true;
      requestNotificationPermission();
    }
    _listenForRideNotifications();
  }

  void _listenForRideNotifications() {
    _notifSub?.cancel();
    _notifSub = _firestore
        .collection('notifications')
        .where('parentId', isEqualTo: _currentUser.uid)
        .snapshots()
        .listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final doc = change.doc;
        final data = doc.data();
        if (data == null) continue;
        if (_shownNotificationIds.contains(doc.id)) continue;
        _shownNotificationIds.add(doc.id);
        final type = data['type'] as String? ?? '';
        final message = data['message'] as String? ?? '';
        final childName = data['childName'] as String?;
        final isDeviation = type == 'route_deviation';
        final isStarted = type == 'ride_started';
        final String title = isDeviation ? 'Route deviation' : (isStarted ? 'Ride started' : 'Ride finished');
        final String body = isDeviation ? message : (childName != null && childName.isNotEmpty ? message : message);
        if (kIsWeb) {
          showRideNotification(title, body);
        } else {
          LocalNotificationService.showRideNotification(title, body);
        }
      }
    });
  }

  Uint8List? _childImageBytes;
  bool _isUploading = false;
  final TextEditingController _childNameController = TextEditingController();
  final TextEditingController _childAgeController = TextEditingController();
  final TextEditingController _childRouteDetailsController = TextEditingController();
  final TextEditingController _childSchoolOnController = TextEditingController();
  final TextEditingController _childSchoolOffController = TextEditingController();
  String? _childSchool;
  String? _childRoute;
  int? _editingChildIndex;

  Future<void> _pickChildImage() async {
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() => _childImageBytes = bytes);
  }

  Widget _personalInfo(Map<String, dynamic> data) {
    final name = TextEditingController(text: data['name']?.toString() ?? '');
    final cnic = TextEditingController(text: data['cnic']?.toString() ?? '');
    final phone = TextEditingController(text: data['phone']?.toString() ?? '');

    final padding = AppTheme.contentPadding(context);
    return SingleChildScrollView(
      padding: padding,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: AppTheme.maxContentWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Personal information', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
            SizedBox(height: AppTheme.verticalSpacing(context)),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name'), textInputAction: TextInputAction.next),
            SizedBox(height: AppTheme.verticalSpacing(context)),
            TextField(controller: cnic, decoration: const InputDecoration(labelText: 'CNIC'), keyboardType: TextInputType.number, textInputAction: TextInputAction.next),
            SizedBox(height: AppTheme.verticalSpacing(context)),
            TextField(controller: phone, decoration: const InputDecoration(labelText: 'Phone'), keyboardType: TextInputType.phone, textInputAction: TextInputAction.done),
            SizedBox(height: AppTheme.verticalSpacing(context) * 2),
            FilledButton.icon(
              onPressed: () async {
                await _firestore.collection('users').doc(_currentUser.uid).set({
                  'name': name.text,
                  'cnic': cnic.text,
                  'phone': phone.text,
                }, SetOptions(merge: true));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: const Text('Saved'), backgroundColor: AppTheme.success, behavior: SnackBarBehavior.floating),
                  );
                }
              },
              icon: const Icon(Icons.save_rounded, size: 20),
              label: const Text('Save'),
            ),
            SizedBox(height: MediaQuery.paddingOf(context).bottom + 24),
          ],
        ),
      ),
    );
  }

  Widget _notificationsPage() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection('notifications').where('parentId', isEqualTo: _currentUser.uid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        var docs = snapshot.data!.docs;
        docs = docs.toList()
          ..sort((a, b) {
            final ta = a.data()['timestamp'] as Timestamp?;
            final tb = b.data()['timestamp'] as Timestamp?;
            if (ta == null && tb == null) return 0;
            if (ta == null) return 1;
            if (tb == null) return -1;
            return tb.compareTo(ta);
          });
        if (docs.length > 50) docs = docs.sublist(0, 50);

        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: AppTheme.contentPadding(context),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none_rounded, size: 64, color: AppTheme.textSecondary.withOpacity(0.5)),
                  const SizedBox(height: 16),
                  Text('No notifications yet', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.textPrimary)),
                  const SizedBox(height: 8),
                  Text(
                    'You\'ll see "Ride started" and "Ride finished" here when the driver starts or ends the ride for your child.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
          );
        }

        final padding = AppTheme.contentPadding(context);
        return ListView.builder(
          padding: padding,
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final d = doc.data();
            final type = d['type'] as String? ?? '';
            final message = d['message'] as String? ?? '';
            final driverName = d['driverName'] as String? ?? 'Driver';
            final childName = d['childName'] as String?;
            final timestamp = d['timestamp'] as dynamic;
            final read = d['read'] as bool? ?? false;
            final isStarted = type == 'ride_started';
            final isDeviation = type == 'route_deviation';
            final String titleText = isDeviation ? 'Route deviation' : (isStarted ? 'Ride started' : 'Ride finished');
            final Color avatarColor = isDeviation ? AppTheme.warning : (isStarted ? AppTheme.success : AppTheme.primary);
            final IconData avatarIcon = isDeviation ? Icons.warning_rounded : (isStarted ? Icons.directions_car_rounded : Icons.check_circle_rounded);
            final Color cardHighlight = read ? Colors.transparent : (isDeviation ? AppTheme.warning.withOpacity(0.08) : (isStarted ? AppTheme.success.withOpacity(0.08) : AppTheme.primary.withOpacity(0.08)));

            return Card(
              margin: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context)),
              color: cardHighlight,
              child: ListTile(
                contentPadding: EdgeInsets.symmetric(horizontal: AppTheme.horizontalPadding(context), vertical: 8),
                leading: CircleAvatar(
                  backgroundColor: avatarColor,
                  child: Icon(avatarIcon, color: Colors.white, size: 24),
                ),
                title: Text(
                  titleText,
                  style: TextStyle(fontWeight: read ? FontWeight.normal : FontWeight.w600, color: AppTheme.textPrimary),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    isDeviation ? message : (childName != null && childName.isNotEmpty ? '$message — $driverName' : '$message — $driverName'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  ),
                ),
                trailing: timestamp != null && timestamp is Timestamp
                    ? Text(_formatTimestamp(timestamp as Timestamp), style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary))
                    : null,
              ),
            );
          },
        );
      },
    );
  }

  String _formatTimestamp(Timestamp t) {
    final d = t.toDate();
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    return '${d.day}/${d.month}/${d.year}';
  }

  Widget _dashboard(Map<String, dynamic> data) {
    final children = List<Map<String, dynamic>>.from(data['children'] ?? []);
    final padding = AppTheme.contentPadding(context);

    return SingleChildScrollView(
      padding: padding,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: AppTheme.maxContentWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: EdgeInsets.all(AppTheme.horizontalPadding(context)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(data['name'] ?? 'Parent', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                    const SizedBox(height: 4),
                    Text('CNIC: ${data['cnic'] ?? '—'}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                    Text('Phone: ${data['phone'] ?? '—'}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                  ],
                ),
              ),
            ),
            SizedBox(height: AppTheme.verticalSpacing(context) * 2),
            Text('Your children', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
            SizedBox(height: AppTheme.verticalSpacing(context)),
            if (children.isEmpty)
              Card(
                child: Padding(
                  padding: EdgeInsets.all(AppTheme.horizontalPadding(context) * 1.5),
                  child: Column(
                    children: [
                      Icon(Icons.child_care_rounded, size: 48, color: AppTheme.textSecondary.withOpacity(0.5)),
                      const SizedBox(height: 12),
                      Text('No children added', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary)),
                      const SizedBox(height: 4),
                      Text('Go to Children to add your first child.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
              )
            else
              ...children.asMap().entries.map((e) {
                final i = e.key + 1;
                final child = e.value;
                return Card(
                  margin: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context)),
                  child: Padding(
                    padding: EdgeInsets.all(AppTheme.horizontalPadding(context)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if ((child['photo'] ?? '').toString().isNotEmpty)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(child['photo'].toString(), height: 72, width: 72, fit: BoxFit.cover),
                              )
                            else
                              CircleAvatar(
                                radius: 36,
                                backgroundColor: AppTheme.primary.withOpacity(0.15),
                                child: Icon(Icons.person_rounded, size: 36, color: AppTheme.primary),
                              ),
                            SizedBox(width: AppTheme.horizontalPadding(context)),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Child $i', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                                  const SizedBox(height: 2),
                                  Text(child['name']?.toString() ?? '—', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: AppTheme.textPrimary)),
                                  const SizedBox(height: 4),
                                  Text('${child['school'] ?? '—'} • ${child['route'] ?? '—'}', style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                                  Text('Timing: ${child['schoolOn'] ?? '—'} – ${child['schoolOff'] ?? '—'}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                                  const SizedBox(height: 4),
                                  Text('Driver: ${child['assignedDriverName'] ?? 'Not assigned'}', style: TextStyle(fontSize: 13, color: (child['assignedDriverName'] ?? '').toString().isEmpty ? AppTheme.warning : AppTheme.textSecondary)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
            SizedBox(height: MediaQuery.paddingOf(context).bottom + 24),
          ],
        ),
      ),
    );
  }

  Widget _childrenPage(Map<String, dynamic> data) {
    final parentChildren = List<Map<String, dynamic>>.from(data['children'] ?? []);

    Future<void> saveChild() async {
      if (_childSchool == null ||
          _childRoute == null ||
          _childNameController.text.isEmpty ||
          _childAgeController.text.isEmpty ||
          _childRouteDetailsController.text.isEmpty ||
          _childSchoolOnController.text.isEmpty ||
          _childSchoolOffController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all fields'), behavior: SnackBarBehavior.floating));
        return;
      }
      setState(() => _isUploading = true);

      String photoUrl = '';
      if (_childImageBytes != null) {
        final ref = FirebaseStorage.instance.ref().child('child_photos/${DateTime.now().millisecondsSinceEpoch}.jpg');
        await ref.putData(_childImageBytes!);
        photoUrl = await ref.getDownloadURL();
      } else if (_editingChildIndex != null) {
        photoUrl = parentChildren[_editingChildIndex!]['photo']?.toString() ?? '';
      }

      String? assignedDriver;
      String? assignedDriverName;
      String childId;

      if (_editingChildIndex != null) {
        final old = parentChildren[_editingChildIndex!];
        childId = old['id'] as String? ?? '';
        assignedDriver = old['assignedDriver'] as String?;
        assignedDriverName = old['assignedDriverName'] as String?;
        parentChildren[_editingChildIndex!] = {
          'id': childId,
          'name': _childNameController.text,
          'age': _childAgeController.text,
          'school': _childSchool,
          'route': _childRoute,
          'routeDetails': _childRouteDetailsController.text,
          'schoolOn': _childSchoolOnController.text,
          'schoolOff': _childSchoolOffController.text,
          'photo': photoUrl,
          'assignedDriver': assignedDriver,
          'assignedDriverName': assignedDriverName,
        };
      } else {
        childId = _firestore.collection('children').doc().id;
        parentChildren.add({
          'id': childId,
          'name': _childNameController.text,
          'age': _childAgeController.text,
          'school': _childSchool,
          'route': _childRoute,
          'routeDetails': _childRouteDetailsController.text,
          'schoolOn': _childSchoolOnController.text,
          'schoolOff': _childSchoolOffController.text,
          'photo': photoUrl,
          'assignedDriver': null,
          'assignedDriverName': null,
        });
      }

      await _firestore.collection('users').doc(_currentUser.uid).set({'children': parentChildren}, SetOptions(merge: true));

      final wasUpdate = _editingChildIndex != null;
      setState(() {
        _childImageBytes = null;
        _editingChildIndex = null;
        _childSchool = null;
        _childRoute = null;
        _childNameController.clear();
        _childAgeController.clear();
        _childRouteDetailsController.clear();
        _childSchoolOnController.clear();
        _childSchoolOffController.clear();
        _isUploading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(wasUpdate ? 'Child updated' : 'Child added'), backgroundColor: AppTheme.success, behavior: SnackBarBehavior.floating));
      }
    }

    final padding = AppTheme.contentPadding(context);
    return SingleChildScrollView(
      padding: padding,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: AppTheme.maxContentWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: GestureDetector(
                onTap: _pickChildImage,
                child: CircleAvatar(
                  radius: 56,
                  backgroundImage: _childImageBytes != null
                      ? MemoryImage(_childImageBytes!)
                      : (_editingChildIndex != null && (parentChildren[_editingChildIndex!]['photo'] ?? '').toString().isNotEmpty
                          ? NetworkImage(parentChildren[_editingChildIndex!]['photo'].toString()) as ImageProvider
                          : null),
                  backgroundColor: AppTheme.primary.withOpacity(0.1),
                  child: _childImageBytes == null && (_editingChildIndex == null || (parentChildren[_editingChildIndex!]['photo'] ?? '').toString().isEmpty)
                      ? Icon(Icons.camera_alt_rounded, size: 40, color: AppTheme.primary.withOpacity(0.6))
                      : null,
                ),
              ),
            ),
            SizedBox(height: AppTheme.verticalSpacing(context) * 2),
            TextField(controller: _childNameController, decoration: const InputDecoration(labelText: 'Name'), textInputAction: TextInputAction.next),
            SizedBox(height: AppTheme.verticalSpacing(context)),
            TextField(controller: _childAgeController, decoration: const InputDecoration(labelText: 'Age'), keyboardType: TextInputType.number, textInputAction: TextInputAction.next),
            SizedBox(height: AppTheme.verticalSpacing(context)),
            StreamBuilder<QuerySnapshot>(
              stream: _firestore.collection('schools').snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final schoolList = snap.data!.docs.map((d) => (d.data() as Map<String, dynamic>)['name'].toString()).toList();
                return DropdownButtonFormField<String>(
                  value: _childSchool,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'School'),
                  items: schoolList.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis, maxLines: 1))).toList(),
                  onChanged: (v) => setState(() => _childSchool = v),
                );
              },
            ),
            SizedBox(height: AppTheme.verticalSpacing(context)),
            StreamBuilder<QuerySnapshot>(
              stream: _firestore.collection('routes').snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final routeList = snap.data!.docs.map((d) => (d.data() as Map<String, dynamic>)['name'].toString()).toList();
                return DropdownButtonFormField<String>(
                  value: _childRoute,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Route'),
                  items: routeList.map((r) => DropdownMenuItem(value: r, child: Text(r, overflow: TextOverflow.ellipsis, maxLines: 1))).toList(),
                  onChanged: (v) => setState(() => _childRoute = v),
                );
              },
            ),
            SizedBox(height: AppTheme.verticalSpacing(context)),
            TextField(controller: _childRouteDetailsController, decoration: const InputDecoration(labelText: 'Route details'), textInputAction: TextInputAction.next),
            SizedBox(height: AppTheme.verticalSpacing(context)),
            TextField(controller: _childSchoolOnController, decoration: const InputDecoration(labelText: 'School on time'), textInputAction: TextInputAction.next),
            SizedBox(height: AppTheme.verticalSpacing(context)),
            TextField(controller: _childSchoolOffController, decoration: const InputDecoration(labelText: 'School off time'), textInputAction: TextInputAction.done),
            SizedBox(height: AppTheme.verticalSpacing(context) * 2),
            if (_isUploading)
              const Center(child: CircularProgressIndicator())
            else
              FilledButton.icon(
                onPressed: saveChild,
                icon: Icon(_editingChildIndex != null ? Icons.edit_rounded : Icons.add_rounded, size: 20),
                label: Text(_editingChildIndex != null ? 'Update child' : 'Add child'),
              ),
            SizedBox(height: AppTheme.verticalSpacing(context) * 2),
            Text('Added children', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
            SizedBox(height: AppTheme.verticalSpacing(context)),
            ...parentChildren.asMap().entries.map((entry) {
              final i = entry.key;
              final child = entry.value;
              final photo = child['photo']?.toString() ?? '';
              return Card(
                margin: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context)),
                child: ListTile(
                  contentPadding: EdgeInsets.symmetric(horizontal: AppTheme.horizontalPadding(context), vertical: 8),
                  leading: photo.isNotEmpty
                      ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(photo, width: 48, height: 48, fit: BoxFit.cover))
                      : CircleAvatar(backgroundColor: AppTheme.primary.withOpacity(0.15), child: const Icon(Icons.child_care_rounded, color: AppTheme.primary)),
                  title: Text(child['name']?.toString() ?? '—', style: const TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: Text('${child['school'] ?? '—'} • ${child['route'] ?? '—'}', style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_rounded, color: AppTheme.primary),
                        onPressed: () {
                          setState(() {
                            _editingChildIndex = i;
                            _childNameController.text = child['name']?.toString() ?? '';
                            _childAgeController.text = child['age']?.toString() ?? '';
                            _childRouteDetailsController.text = child['routeDetails']?.toString() ?? '';
                            _childSchoolOnController.text = child['schoolOn']?.toString() ?? '';
                            _childSchoolOffController.text = child['schoolOff']?.toString() ?? '';
                            _childSchool = child['school']?.toString();
                            _childRoute = child['route']?.toString();
                            _childImageBytes = null;
                          });
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_rounded, color: AppTheme.error),
                        onPressed: () async {
                          parentChildren.removeAt(i);
                          await _firestore.collection('users').doc(_currentUser.uid).set({'children': parentChildren}, SetOptions(merge: true));
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
              );
            }),
            SizedBox(height: MediaQuery.paddingOf(context).bottom + 24),
          ],
        ),
      ),
    );
  }

  Widget _driversPage(Map<String, dynamic> parentData) {
    final parentChildren = List<Map<String, dynamic>>.from(parentData['children'] ?? []);
    if (parentChildren.isEmpty) {
      return Center(
        child: Padding(
          padding: AppTheme.contentPadding(context),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.people_outline_rounded, size: 64, color: AppTheme.textSecondary.withOpacity(0.5)),
              const SizedBox(height: 16),
              Text('No children added yet', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.textSecondary)),
              const SizedBox(height: 8),
              Text('Add a child first, then request a driver for their route.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary)),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: AppTheme.contentPadding(context),
      itemCount: parentChildren.length,
      itemBuilder: (context, index) {
        final child = parentChildren[index];
        final childId = child['id']?.toString() ?? '';
        final childName = child['name']?.toString() ?? '';
        final childSchool = child['school']?.toString() ?? '';
        final childRoute = child['route']?.toString() ?? '';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context)),
              child: Text('$childName', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _firestore
                  .collection('requests')
                  .where('parentId', isEqualTo: _currentUser.uid)
                  .where('status', whereIn: ['pending', 'approved'])
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));

                final requests = snapshot.data!.docs;
                QueryDocumentSnapshot<Map<String, dynamic>>? approvedRequest;
                try {
                  approvedRequest = requests.firstWhere((r) {
                    final data = r.data();
                    return data['status'] == 'approved' && (data['childIds'] as List).contains(childId);
                  });
                } catch (_) {
                  approvedRequest = null;
                }

                if (approvedRequest != null) {
                  final driverId = approvedRequest.data()['driverId'] as String?;
                  if (driverId == null || driverId.isEmpty) return const SizedBox(height: 48, child: Center(child: Text('Driver not assigned yet')));

                  return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    future: _firestore.collection('users').doc(driverId).get(),
                    builder: (context, driverSnap) {
                      if (!driverSnap.hasData) return const Center(child: CircularProgressIndicator());
                      final driverData = driverSnap.data?.data();
                      if (driverData == null) return const SizedBox();

                      _updateAssignedDriver(driverId, driverData['name']?.toString() ?? '', childId);

                      return Card(
                        margin: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context) * 2),
                        child: Padding(
                          padding: EdgeInsets.all(AppTheme.horizontalPadding(context)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if ((child['photo'] ?? '').toString().isNotEmpty)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.network(child['photo'].toString(), height: 100, width: double.infinity, fit: BoxFit.cover),
                                ),
                              if ((child['photo'] ?? '').toString().isNotEmpty) SizedBox(height: AppTheme.verticalSpacing(context)),
                              _driverInfoRow(Icons.person_rounded, 'Driver', driverData['name']?.toString() ?? '—'),
                              _driverInfoRow(Icons.badge_rounded, 'CNIC', driverData['cnic']?.toString() ?? '—'),
                              _driverInfoRow(Icons.drive_eta_rounded, 'License', driverData['licenseNumber']?.toString() ?? '—'),
                              _driverInfoRow(Icons.directions_car_rounded, 'Vehicle', '${driverData['vehicleName'] ?? '—'} (${driverData['vehicleNumber'] ?? '—'})'),
                              _driverInfoRow(Icons.school_rounded, 'School', driverData['school']?.toString() ?? '—'),
                              _driverInfoRow(Icons.route_rounded, 'Route', driverData['route']?.toString() ?? '—'),
                              _driverInfoRow(Icons.event_seat_rounded, 'Seats', driverData['seats']?.toString() ?? '—'),
                              SizedBox(height: AppTheme.verticalSpacing(context)),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(color: AppTheme.success.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                child: Row(children: [
                                  const Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text('This driver is assigned to your child', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary))),
                                ]),
                              ),
                              SizedBox(height: AppTheme.verticalSpacing(context)),
                              FilledButton.icon(
                                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => DriverLocationScreen(childId: childId))),
                                icon: const Icon(Icons.location_on_rounded, size: 20),
                                label: const Text('Track driver'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                }

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _firestore.collection('users').where('role', isEqualTo: 'driver').snapshots(),
                  builder: (context, driversSnap) {
                    if (!driversSnap.hasData) return const Center(child: CircularProgressIndicator());
                    final drivers = driversSnap.data!.docs.where((doc) {
                      final d = doc.data();
                      return d['school'] == childSchool && d['route'] == childRoute;
                    }).toList();

                    if (drivers.isEmpty) {
                      return Card(
                        margin: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context) * 2),
                        child: Padding(
                          padding: EdgeInsets.all(AppTheme.horizontalPadding(context)),
                          child: Text('No drivers available for this route yet.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary)),
                        ),
                      );
                    }

                    return Column(
                      children: drivers.map((doc) {
                        final d = doc.data();
                        return Card(
                          margin: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context)),
                          child: Padding(
                            padding: EdgeInsets.all(AppTheme.horizontalPadding(context)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if ((d['profilePic'] ?? '').toString().isNotEmpty)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(d['profilePic'].toString(), height: 72, width: double.infinity, fit: BoxFit.cover),
                                  ),
                                if ((d['profilePic'] ?? '').toString().isNotEmpty) SizedBox(height: AppTheme.verticalSpacing(context)),
                                _driverInfoRow(Icons.person_rounded, 'Name', d['name']?.toString() ?? '—'),
                                _driverInfoRow(Icons.badge_rounded, 'CNIC', d['cnic']?.toString() ?? '—'),
                                _driverInfoRow(Icons.directions_car_rounded, 'Vehicle', '${d['vehicleName'] ?? '—'} (${d['vehicleNumber'] ?? '—'})'),
                                _driverInfoRow(Icons.route_rounded, 'Route', d['route']?.toString() ?? '—'),
                                SizedBox(height: AppTheme.verticalSpacing(context)),
                                FilledButton(
                                  onPressed: () async {
                                    final adminSnapshot = await _firestore.collection('users').where('role', isEqualTo: 'admin').get();
                                    for (var adminDoc in adminSnapshot.docs) {
                                      await _firestore.collection('requests').add({
                                        'parentId': _currentUser.uid,
                                        'driverId': doc.id,
                                        'childIds': [childId],
                                        'status': 'pending',
                                        'adminId': adminDoc.id,
                                        'timestamp': FieldValue.serverTimestamp(),
                                      });
                                    }
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request sent to admin'), backgroundColor: AppTheme.success, behavior: SnackBarBehavior.floating));
                                    }
                                  },
                                  child: const Text('Request driver'),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                );
              },
            ),
            SizedBox(height: AppTheme.verticalSpacing(context) * 2),
          ],
        );
      },
    );
  }

  Widget _driverInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context) * 0.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppTheme.textSecondary),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary))),
        ],
      ),
    );
  }

  Future<void> _updateAssignedDriver(String driverId, String driverName, String childId) async {
    final parentDoc = await _firestore.collection('users').doc(_currentUser.uid).get();
    final children = List<Map<String, dynamic>>.from(parentDoc.data()?['children'] ?? []);
    final index = children.indexWhere((c) => c['id'] == childId);
    if (index != -1 && (children[index]['assignedDriver'] != driverId)) {
      children[index]['assignedDriver'] = driverId;
      children[index]['assignedDriverName'] = driverName;
      await _firestore.collection('users').doc(_currentUser.uid).set({'children': children}, SetOptions(merge: true));
    }
  }

  static const List<_NavItem> _navItems = [
    _NavItem('Personal info', Icons.person_rounded),
    _NavItem('Notifications', Icons.notifications_rounded),
    _NavItem('Dashboard', Icons.dashboard_rounded),
    _NavItem('Drivers', Icons.people_rounded),
    _NavItem('Children', Icons.child_care_rounded),
    _NavItem('Payments', Icons.payment_rounded),
    _NavItem('Reviews', Icons.star_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection('users').doc(_currentUser.uid).snapshots(),
      builder: (c, s) {
        if (!s.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final data = s.data!.data() ?? {};
        final parentName = data['name']?.toString() ?? '';

        final pages = [
          _personalInfo(data),
          _notificationsPage(),
          _dashboard(data),
          _driversPage(data),
          _childrenPage(data),
          Center(child: _emptyPage('Payments', Icons.payment_rounded)),
          Center(child: _emptyPage('Reviews', Icons.star_rounded)),
        ];

        return Scaffold(
          body: SafeArea(child: pages[_selectedIndex]),
          appBar: AppBar(title: Text(_navItems[_selectedIndex].label)),
          drawer: Drawer(
            child: SafeArea(
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(AppTheme.horizontalPadding(context)),
                    color: AppTheme.primary,
                    child: Column(
                      children: [
                        const SizedBox(height: 16),
                        CircleAvatar(
                          radius: 40,
                          backgroundColor: Colors.white24,
                          child: Text(parentName.isEmpty ? '?' : parentName[0].toUpperCase(), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: Colors.white)),
                        ),
                        const SizedBox(height: 12),
                        Text(parentName.isEmpty ? 'Parent' : parentName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
                        const SizedBox(height: 4),
                        Text(data['phone']?.toString() ?? '', style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.9))),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.symmetric(vertical: AppTheme.verticalSpacing(context)),
                      children: [
                        ..._navItems.asMap().entries.map((e) {
                          final selected = _selectedIndex == e.key;
                          return ListTile(
                            leading: Icon(e.value.icon, color: selected ? AppTheme.primary : AppTheme.textSecondary, size: 24),
                            title: Text(e.value.label, style: TextStyle(fontWeight: selected ? FontWeight.w600 : FontWeight.normal, color: selected ? AppTheme.primary : AppTheme.textPrimary)),
                            selected: selected,
                            onTap: () {
                              setState(() => _selectedIndex = e.key);
                              Navigator.pop(context);
                            },
                          );
                        }),
                        const Divider(),
                        ListTile(
                          leading: const Icon(Icons.logout_rounded, color: AppTheme.error),
                          title: const Text('Logout', style: TextStyle(fontWeight: FontWeight.w500, color: AppTheme.error)),
                          onTap: () async {
                            await FirebaseAuth.instance.signOut();
                            if (context.mounted) {
                              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _emptyPage(String title, IconData icon) {
    return Padding(
      padding: AppTheme.contentPadding(context),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 56, color: AppTheme.textSecondary.withOpacity(0.5)),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  const _NavItem(this.label, this.icon);
}
