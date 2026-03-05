import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
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

  // ================= CHILD FORM =================
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

  // ================= IMAGE PICK =================
  Future<void> _pickChildImage() async {
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() => _childImageBytes = bytes);
  }

  // ================= PERSONAL INFO =================
  Widget _personalInfo(Map<String, dynamic> data) {
    final name = TextEditingController(text: data['name']);
    final cnic = TextEditingController(text: data['cnic']);
    final phone = TextEditingController(text: data['phone']);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: "Name")),
        TextField(controller: cnic, decoration: const InputDecoration(labelText: "CNIC")),
        TextField(controller: phone, decoration: const InputDecoration(labelText: "Phone")),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () async {
            await _firestore.collection('users').doc(_currentUser.uid).set({
              "name": name.text,
              "cnic": cnic.text,
              "phone": phone.text,
            }, SetOptions(merge: true));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Saved!")));
          },
          child: const Text("Save"),
        )
      ]),
    );
  }

  // ================= NOTIFICATIONS (ride started / ride ended from driver) =================
  Widget _notificationsPage() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore
          .collection('notifications')
          .where('parentId', isEqualTo: _currentUser.uid)
          .snapshots(),
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
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Text(
                'No notifications yet.\nYou\'ll see "Ride started" and "Ride finished" here when the driver starts or ends the ride for your child.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final d = docs[index].data();
            final type = d['type'] as String? ?? '';
            final message = d['message'] as String? ?? '';
            final driverName = d['driverName'] as String? ?? 'Driver';
            final childName = d['childName'] as String?;
            final timestamp = d['timestamp'] as dynamic;
            final read = d['read'] as bool? ?? false;

            final isStarted = type == 'ride_started';
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              color: read ? null : (isStarted ? Colors.green.shade50 : Colors.blue.shade50),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: isStarted ? Colors.green : Colors.blue,
                  child: Icon(
                    isStarted ? Icons.directions_car : Icons.check_circle,
                    color: Colors.white,
                  ),
                ),
                title: Text(
                  isStarted ? 'Ride started' : 'Ride finished',
                  style: TextStyle(
                    fontWeight: read ? FontWeight.normal : FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  childName != null && childName.isNotEmpty
                      ? '$message — $driverName'
                      : '$message — $driverName',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: timestamp != null && timestamp is Timestamp
                    ? Text(
                        _formatTimestamp(timestamp as Timestamp),
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      )
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

  // ================= DASHBOARD =================
  Widget _dashboard(Map<String, dynamic> data) {
    final children = List<Map<String, dynamic>>.from(data['children'] ?? []);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(data['name'] ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text("CNIC: ${data['cnic'] ?? ''}"),
        Text("Phone: ${data['phone'] ?? ''}"),
        const SizedBox(height: 24),
        ...children.asMap().entries.map((e) {
          final i = e.key + 1;
          final child = e.value;
          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text("Child $i", style: const TextStyle(fontWeight: FontWeight.bold)),
                if ((child['photo'] ?? '').toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Image.network(child['photo'], height: 160, fit: BoxFit.cover),
                  ),
                Text("Name: ${child['name'] ?? ''}"),
                Text("School: ${child['school'] ?? ''}"),
                Text("Route: ${child['route'] ?? ''}"),
                Text("School Timing: ${child['schoolOn'] ?? ''} - ${child['schoolOff'] ?? ''}"),
                Text("Assigned Driver: ${child['assignedDriverName'] ?? 'Not Assigned'}"),
              ]),
            ),
          );
        })
      ]),
    );
  }

  // ================= CHILD FORM PAGE =================
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please fill all fields")),
        );
        return;
      }

      setState(() => _isUploading = true);

      String photoUrl = '';
      if (_childImageBytes != null) {
        final ref = FirebaseStorage.instance
            .ref()
            .child('child_photos/${DateTime.now().millisecondsSinceEpoch}.jpg');
        await ref.putData(_childImageBytes!);
        photoUrl = await ref.getDownloadURL();
      } else if (_editingChildIndex != null) {
        photoUrl = parentChildren[_editingChildIndex!]['photo'] ?? '';
      }

      String? assignedDriver;
      String? assignedDriverName;
      String childId;

      if (_editingChildIndex != null) {
        final old = parentChildren[_editingChildIndex!];
        childId = old['id'];
        assignedDriver = old['assignedDriver'];
        assignedDriverName = old['assignedDriverName'];
        parentChildren[_editingChildIndex!] = {
          "id": childId,
          "name": _childNameController.text,
          "age": _childAgeController.text,
          "school": _childSchool,
          "route": _childRoute,
          "routeDetails": _childRouteDetailsController.text,
          "schoolOn": _childSchoolOnController.text,
          "schoolOff": _childSchoolOffController.text,
          "photo": photoUrl,
          "assignedDriver": assignedDriver,
          "assignedDriverName": assignedDriverName,
        };
      } else {
        childId = _firestore.collection('children').doc().id;
        parentChildren.add({
          "id": childId,
          "name": _childNameController.text,
          "age": _childAgeController.text,
          "school": _childSchool,
          "route": _childRoute,
          "routeDetails": _childRouteDetailsController.text,
          "schoolOn": _childSchoolOnController.text,
          "schoolOff": _childSchoolOffController.text,
          "photo": photoUrl,
          "assignedDriver": null,
          "assignedDriverName": null,
        });
      }

      await _firestore.collection('users').doc(_currentUser.uid).set({
        "children": parentChildren
      }, SetOptions(merge: true));

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
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          GestureDetector(
            onTap: _pickChildImage,
            child: CircleAvatar(
              radius: 60,
              backgroundImage: _childImageBytes != null
                  ? MemoryImage(_childImageBytes!)
                  : (_editingChildIndex != null &&
                          (parentChildren[_editingChildIndex!]['photo'] ?? '').isNotEmpty
                      ? NetworkImage(parentChildren[_editingChildIndex!]['photo']) as ImageProvider
                      : null),
              child: _childImageBytes == null &&
                      (_editingChildIndex == null || (parentChildren[_editingChildIndex!]['photo'] ?? '').isEmpty)
                  ? const Icon(Icons.camera_alt)
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          TextField(controller: _childNameController, decoration: const InputDecoration(labelText: "Name")),
          TextField(controller: _childAgeController, decoration: const InputDecoration(labelText: "Age")),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot>(
            stream: _firestore.collection('schools').snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) return const CircularProgressIndicator();
              final schoolList = snap.data!.docs
                  .map((d) => (d.data() as Map<String, dynamic>)['name'].toString())
                  .toList();
              return DropdownButtonFormField<String>(
                value: _childSchool,
                hint: const Text("Select School"),
                items: schoolList.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (v) => setState(() => _childSchool = v),
              );
            },
          ),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot>(
            stream: _firestore.collection('routes').snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) return const CircularProgressIndicator();
              final routeList = snap.data!.docs
                  .map((d) => (d.data() as Map<String, dynamic>)['name'].toString())
                  .toList();
              return DropdownButtonFormField<String>(
                value: _childRoute,
                hint: const Text("Select Route"),
                items: routeList.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                onChanged: (v) => setState(() => _childRoute = v),
              );
            },
          ),
          TextField(controller: _childRouteDetailsController, decoration: const InputDecoration(labelText: "Route Details")),
          TextField(controller: _childSchoolOnController, decoration: const InputDecoration(labelText: "School On Timing")),
          TextField(controller: _childSchoolOffController, decoration: const InputDecoration(labelText: "School Off Timing")),
          const SizedBox(height: 16),
          _isUploading
              ? const CircularProgressIndicator()
              : ElevatedButton(
                  onPressed: saveChild,
                  child: Text(_editingChildIndex != null ? "Update Child" : "Add Child"),
                ),
          const SizedBox(height: 24),
          const Text("Added Children:", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...parentChildren.asMap().entries.map((entry) {
            final i = entry.key;
            final child = entry.value;
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: child['photo'] != null && child['photo'] != ''
                    ? Image.network(child['photo'], width: 50, fit: BoxFit.cover)
                    : const Icon(Icons.child_care),
                title: Text(child['name'] ?? ''),
                subtitle: Text("${child['school'] ?? ''} - ${child['route'] ?? ''}"),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue),
                      onPressed: () {
                        setState(() {
                          _editingChildIndex = i;
                          _childNameController.text = child['name'] ?? '';
                          _childAgeController.text = child['age'] ?? '';
                          _childRouteDetailsController.text = child['routeDetails'] ?? '';
                          _childSchoolOnController.text = child['schoolOn'] ?? '';
                          _childSchoolOffController.text = child['schoolOff'] ?? '';
                          _childSchool = child['school'];
                          _childRoute = child['route'];
                          _childImageBytes = null;
                        });
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () async {
                        parentChildren.removeAt(i);
                        await _firestore.collection('users').doc(_currentUser.uid).set({
                          "children": parentChildren
                        }, SetOptions(merge: true));
                      },
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  // ================= DRIVERS PAGE =================
  Widget _driversPage(Map<String, dynamic> parentData) {
    final parentChildren = List<Map<String, dynamic>>.from(parentData['children'] ?? []);
    if (parentChildren.isEmpty) return const Center(child: Text("No children added yet."));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: parentChildren.length,
      itemBuilder: (context, index) {
        final child = parentChildren[index];
        final childId = child['id'] ?? '';
        final childName = child['name'] ?? '';
        final childSchool = child['school'] ?? '';
        final childRoute = child['route'] ?? '';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Child ${index + 1}: $childName", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _firestore
                  .collection('requests')
                  .where('parentId', isEqualTo: _currentUser.uid)
                  .where('status', whereIn: ['pending', 'approved'])
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const CircularProgressIndicator();

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
                  if (driverId == null || driverId.isEmpty) return const Text("Driver not assigned yet");

                  return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    future: _firestore.collection('users').doc(driverId).get(),
                    builder: (context, driverSnap) {
                      if (!driverSnap.hasData) return const CircularProgressIndicator();
                      final driverData = driverSnap.data?.data();
                      if (driverData == null) return const Text("Driver data not found");

                      // ==== UPDATE CHILD ASSIGNED DRIVER ==== //
                      _updateAssignedDriver(driverId, driverData['name'], childId);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if ((child['photo'] ?? '').isNotEmpty)
                                Image.network(child['photo'], height: 120, fit: BoxFit.cover),
                              const SizedBox(height: 8),
                              Text("Driver Name: ${driverData['name'] ?? ''}"),
                              Text("CNIC: ${driverData['cnic'] ?? ''}"),
                              Text("License: ${driverData['licenseNumber'] ?? ''}"),
                              Text("Vehicle: ${driverData['vehicleName'] ?? ''} (${driverData['vehicleNumber'] ?? ''})"),
                              Text("School: ${driverData['school'] ?? ''}"),
                              Text("Route: ${driverData['route'] ?? ''}"),
                              Text("Seats: ${driverData['seats'] ?? ''}"),
                              const SizedBox(height: 8),
                              const Text("This driver has been assigned to your child"),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) => DriverLocationScreen(childId: childId),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.location_on),
                                label: const Text("Track Driver"),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                }

                // ===== AVAILABLE DRIVERS =====
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _firestore.collection('users').where('role', isEqualTo: 'driver').snapshots(),
                  builder: (context, driversSnap) {
                    if (!driversSnap.hasData) return const CircularProgressIndicator();

                    final drivers = driversSnap.data!.docs.where((doc) {
                      final d = doc.data();
                      return d['school'] == childSchool && d['route'] == childRoute;
                    }).toList();

                    if (drivers.isEmpty) return const Text("No available drivers for this child's route.");

                    return Column(
                      children: drivers.map((doc) {
                        final d = doc.data();
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if ((d['profilePic'] ?? '').toString().isNotEmpty)
                                  Image.network(d['profilePic'], height: 80, fit: BoxFit.cover),
                                const SizedBox(height: 6),
                                Text("Name: ${d['name'] ?? ''}"),
                                Text("CNIC: ${d['cnic'] ?? ''}"),
                                Text("License: ${d['licenseNumber'] ?? ''}"),
                                Text("Vehicle: ${d['vehicleName'] ?? ''} (${d['vehicleNumber'] ?? ''})"),
                                Text("School: ${d['school'] ?? ''}"),
                                Text("Route: ${d['route'] ?? ''}"),
                                Text("Seats: ${d['seats'] ?? ''}"),
                                const SizedBox(height: 6),
                                ElevatedButton(
                                  onPressed: () async {
                                    final adminSnapshot = await _firestore
                                        .collection('users')
                                        .where('role', isEqualTo: 'admin')
                                        .get();
                                    for (var adminDoc in adminSnapshot.docs) {
                                      await _firestore.collection('requests').add({
                                        "parentId": _currentUser.uid,
                                        "driverId": doc.id,
                                        "childIds": [childId],
                                        "status": "pending",
                                        "adminId": adminDoc.id,
                                        "timestamp": FieldValue.serverTimestamp(),
                                      });
                                    }
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text("Request sent to admin for approval")),
                                    );
                                  },
                                  child: const Text("Request Driver"),
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
            const SizedBox(height: 24),
          ],
        );
      },
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

  // ================= BUILD =================
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection('users').doc(_currentUser.uid).snapshots(),
      builder: (c, s) {
        if (!s.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));

        final data = s.data!.data() ?? {};

        final pages = [
          _personalInfo(data),
          _notificationsPage(),
          _dashboard(data),
          _driversPage(data),
          _childrenPage(data),
          const Center(child: Text("Payments")),
          const Center(child: Text("Reviews")),
        ];

        return Scaffold(
          appBar: AppBar(title: const Text("Parent Dashboard")),
          drawer: Drawer(
            child: ListView(children: [
              DrawerHeader(child: Text(data['name'] ?? 'Parent', style: const TextStyle(fontSize: 20))),
              _tile("Personal Info", 0),
              _tile("Notifications", 1),
              _tile("Dashboard", 2),
              _tile("Drivers", 3),
              _tile("Children", 4),
              _tile("Payments", 5),
              _tile("Reviews", 6),
              ListTile(
                title: const Text("Logout"),
                onTap: () async {
                  await FirebaseAuth.instance.signOut();
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
                },
              )
            ]),
          ),
          body: pages[_selectedIndex],
        );
      },
    );
  }

  ListTile _tile(String t, int i) => ListTile(
        title: Text(t),
        selected: _selectedIndex == i,
        onTap: () {
          setState(() => _selectedIndex = i);
          Navigator.pop(context);
        },
      );
}
