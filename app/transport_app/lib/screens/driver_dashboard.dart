import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'gps_controller.dart';
import 'login_screen.dart';

class DriverDashboard extends StatefulWidget {
  const DriverDashboard({Key? key}) : super(key: key);

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  final _firestore = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  final _user = FirebaseAuth.instance.currentUser!;
  int _index = 0;

  Uint8List? _profilePic, _cnicPic, _licensePic, _vehiclePic;
  bool _loadingProfile = false, _loadingCnic = false, _loadingLicense = false, _loadingVehicle = false;

  final _nameC = TextEditingController();
  final _cnicC = TextEditingController();
  final _phoneC = TextEditingController();
  final _licenseC = TextEditingController();
  final _vehicleNameC = TextEditingController();
  final _vehicleNumberC = TextEditingController();
  final _seatsC = TextEditingController();

  String? _selectedSchool;
  String? _selectedRoute;
  bool _rideOn = false;

  @override
  void dispose() {
    _nameC.dispose();
    _cnicC.dispose();
    _phoneC.dispose();
    _licenseC.dispose();
    _vehicleNameC.dispose();
    _vehicleNumberC.dispose();
    _seatsC.dispose();
    super.dispose();
  }

  // ================= Image Upload =================
  Future<void> _pickUpload(String type) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() {
      if (type == 'profilePic') _loadingProfile = true;
      if (type == 'cnicPic') _loadingCnic = true;
      if (type == 'licensePic') _loadingLicense = true;
      if (type == 'vehiclePic') _loadingVehicle = true;
    });

    try {
      final bytes = await picked.readAsBytes();
      final ref = _storage.ref('drivers/${_user.uid}/$type.jpg');
      await ref.putData(bytes);
      final url = await ref.getDownloadURL();
      await _firestore.collection('users').doc(_user.uid).set({type: url}, SetOptions(merge: true));

      setState(() {
        if (type == 'profilePic') _profilePic = bytes;
        if (type == 'cnicPic') _cnicPic = bytes;
        if (type == 'licensePic') _licensePic = bytes;
        if (type == 'vehiclePic') _vehiclePic = bytes;
      });
    } finally {
      setState(() {
        if (type == 'profilePic') _loadingProfile = false;
        if (type == 'cnicPic') _loadingCnic = false;
        if (type == 'licensePic') _loadingLicense = false;
        if (type == 'vehiclePic') _loadingVehicle = false;
      });
    }
  }

  Widget _imgRow(String label, Uint8List? local, String? url, String type) {
    ImageProvider? img = local != null
        ? MemoryImage(local)
        : (url != null && url.isNotEmpty ? NetworkImage(url) : null);

    bool isLoading = (type == 'profilePic')
        ? _loadingProfile
        : (type == 'cnicPic')
            ? _loadingCnic
            : (type == 'licensePic')
                ? _loadingLicense
                : _loadingVehicle;

    return ListTile(
      leading: CircleAvatar(backgroundImage: img),
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          isLoading
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : ElevatedButton(onPressed: () => _pickUpload(type), child: const Text("Upload")),
          const SizedBox(width: 8),
          if (img != null)
            ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: Text(label)),
                    body: Center(child: Image(image: img)),
                  ),
                ),
              ),
              child: const Text("View"),
            ),
        ],
      ),
    );
  }

  // ================= Profile Save =================
  Future<void> _saveProfile() async {
    if (_nameC.text.isEmpty || _cnicC.text.length != 13 || _phoneC.text.length != 11) return;

    await _firestore.collection('users').doc(_user.uid).set({
      'name': _nameC.text.trim(),
      'cnic': _cnicC.text.trim(),
      'phone': _phoneC.text.trim(),
      'licenseNumber': _licenseC.text.trim(),
      'vehicleName': _vehicleNameC.text.trim(),
      'vehicleNumber': _vehicleNumberC.text.trim(),
      'school': _selectedSchool ?? '',
      'route': _selectedRoute ?? '',
      'seats': _seatsC.text.trim(),
    }, SetOptions(merge: true));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile saved successfully')),
    );
  }

  // ================= Profile Tab =================
  Widget _profile(Map<String, dynamic> d) {
    _nameC.text = d['name'] ?? '';
    _cnicC.text = d['cnic'] ?? '';
    _phoneC.text = d['phone'] ?? '';
    _licenseC.text = d['licenseNumber'] ?? '';
    _vehicleNameC.text = d['vehicleName'] ?? '';
    _vehicleNumberC.text = d['vehicleNumber'] ?? '';
    _seatsC.text = d['seats'] ?? '';

    if (_selectedSchool == null && d['school'] != null && d['school'].toString().isNotEmpty) _selectedSchool = d['school'];
    if (_selectedRoute == null && d['route'] != null && d['route'].toString().isNotEmpty) _selectedRoute = d['route'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        _imgRow('Profile', _profilePic, d['profilePic'], 'profilePic'),
        _imgRow('CNIC', _cnicPic, d['cnicPic'], 'cnicPic'),
        _imgRow('License', _licensePic, d['licensePic'], 'licensePic'),
        _imgRow('Vehicle', _vehiclePic, d['vehiclePic'], 'vehiclePic'),
        TextField(controller: _nameC, decoration: const InputDecoration(labelText: 'Name')),
        const SizedBox(height: 12),
        TextField(controller: _cnicC, decoration: const InputDecoration(labelText: 'CNIC'), keyboardType: TextInputType.number),
        const SizedBox(height: 12),
        TextField(controller: _phoneC, decoration: const InputDecoration(labelText: 'Phone'), keyboardType: TextInputType.phone),
        const SizedBox(height: 12),
        TextField(controller: _licenseC, decoration: const InputDecoration(labelText: 'License Number')),
        const SizedBox(height: 12),
        TextField(controller: _vehicleNameC, decoration: const InputDecoration(labelText: 'Vehicle Name')),
        const SizedBox(height: 12),
        TextField(controller: _vehicleNumberC, decoration: const InputDecoration(labelText: 'Vehicle Number')),
        const SizedBox(height: 12),
        StreamBuilder<QuerySnapshot>(
          stream: _firestore.collection('schools').snapshots(),
          builder: (context, schoolSnap) {
            if (!schoolSnap.hasData) return const CircularProgressIndicator();
            final schoolList = schoolSnap.data!.docs.map((d) => (d.data() as Map<String, dynamic>)['name'].toString()).toList();
            return DropdownButtonFormField<String>(
              value: _selectedSchool,
              hint: const Text('Select School'),
              items: schoolList.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) => setState(() => _selectedSchool = v),
            );
          },
        ),
        const SizedBox(height: 12),
        StreamBuilder<QuerySnapshot>(
          stream: _firestore.collection('routes').snapshots(),
          builder: (context, routeSnap) {
            if (!routeSnap.hasData) return const CircularProgressIndicator();
            final routeList = routeSnap.data!.docs.map((d) => (d.data() as Map<String, dynamic>)['name'].toString()).toList();
            return DropdownButtonFormField<String>(
              value: _selectedRoute,
              hint: const Text('Select Route'),
              items: routeList.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
              onChanged: (v) => setState(() => _selectedRoute = v),
            );
          },
        ),
        const SizedBox(height: 12),
        TextField(controller: _seatsC, decoration: const InputDecoration(labelText: 'Seats'), keyboardType: TextInputType.number),
        const SizedBox(height: 12),
        ElevatedButton(onPressed: _saveProfile, child: const Text("Save")),
      ]),
    );
  }

  // ================= Dashboard Tab =================
  Widget _dashboard(Map<String, dynamic> d) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        ListTile(
          leading: CircleAvatar(backgroundImage: d['profilePic'] != null ? NetworkImage(d['profilePic']) : null),
          title: Text(d['name'] ?? 'Driver'),
          subtitle: Text(_rideOn ? 'On Ride' : 'Offline'),
        ),
        ListTile(title: Text('CNIC: ${d['cnic'] ?? ''}')),
        ListTile(title: Text('License: ${d['licenseNumber'] ?? ''}')),
        ListTile(title: Text('Vehicle: ${d['vehicleName'] ?? ''} (${d['vehicleNumber'] ?? ''})')),
        ListTile(title: Text('School: ${d['school'] ?? ''}')),
        ListTile(title: Text('Route: ${d['route'] ?? ''}')),
        ListTile(title: Text('Seats: ${d['seats'] ?? ''}')),
      ]),
    );
  }

  // ================= Assigned Children Tab FIXED =================
  Widget _assignedChildren() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('driver_requests')
          .where('driverId', isEqualTo: _user.uid)
          .where('status', isEqualTo: 'approved')
          .snapshots(),
      builder: (context, driverReqSnap) {
        if (!driverReqSnap.hasData) return const Center(child: CircularProgressIndicator());
        final driverRequests = driverReqSnap.data!.docs;

        if (driverRequests.isEmpty) return const Center(child: Text('No children assigned yet.'));

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: driverRequests.map((reqDoc) {
              final reqData = reqDoc.data() as Map<String, dynamic>;
              final parentId = reqData['parentId'];

              return FutureBuilder<DocumentSnapshot>(
                future: _firestore.collection('users').doc(parentId).get(),
                builder: (context, parentSnap) {
                  if (!parentSnap.hasData) return const SizedBox();
                  final parentData = parentSnap.data!.data() as Map<String, dynamic>? ?? {};
                  final children = parentData['children'] as List<dynamic>? ?? [];

                  // ==== FIX: assigned children show even if routeId missing ====
                  final assignedChildren = children.where((c) {
                    if (c['assignedDriver'] != _user.uid) return false;
                    if (c['routeId'] != null && reqData['routeId'] != null) {
                      return c['routeId'] == reqData['routeId'];
                    }
                    return true; // show if routeId missing
                  }).toList();

                  if (assignedChildren.isEmpty) return const SizedBox();

                  return Column(
                    children: assignedChildren.map((child) {
                      final picUrl = child['photo'] ?? '';
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      if (picUrl.isNotEmpty) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => Scaffold(
                                              appBar: AppBar(title: Text(child['name'] ?? 'Child')),
                                              body: Center(child: Image.network(picUrl)),
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                    child: CircleAvatar(
                                      radius: 30,
                                      backgroundImage: picUrl.isNotEmpty ? NetworkImage(picUrl) : null,
                                      child: picUrl.isEmpty ? const Icon(Icons.person, size: 30) : null,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(child['name'] ?? 'Unknown', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                        Text('Age: ${child['age'] ?? ''}'),
                                        Text('School: ${child['school'] ?? ''}'),
                                        Text('Route: ${child['route'] ?? ''}'),
                                        Text('Parent: ${parentData['name'] ?? 'Unknown'}'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  ElevatedButton(
                                    onPressed: () async {
                                      final telUri = Uri(scheme: 'tel', path: parentData['phone'] ?? '');
                                      if (await canLaunchUrl(telUri)) await launchUrl(telUri);
                                    },
                                    child: const Text('Call Parent'),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    onPressed: () {
                                      setState(() => _rideOn = !_rideOn);
                                      if (_rideOn) GPSController.startTracking(_user.uid);
                                      else GPSController.stopTracking();
                                      _firestore.collection('users').doc(_user.uid).set({
                                        'rideStatus': _rideOn ? 'on' : 'off',
                                      }, SetOptions(merge: true));
                                    },
                                    style: ElevatedButton.styleFrom(backgroundColor: _rideOn ? Colors.red : Colors.green),
                                    child: Text(_rideOn ? 'Stop Ride' : 'Start Ride'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  // ================= Manage Route =================
  Widget _manageRoute() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('routes').snapshots(),
      builder: (context, routeSnap) {
        if (!routeSnap.hasData) return const Center(child: CircularProgressIndicator());
        final routeList = routeSnap.data!.docs.map((d) => (d.data() as Map<String, dynamic>)['name'].toString()).toList();

        return StreamBuilder<QuerySnapshot>(
          stream: _firestore.collection('schools').snapshots(),
          builder: (context, schoolSnap) {
            if (!schoolSnap.hasData) return const Center(child: CircularProgressIndicator());
            final schoolList = schoolSnap.data!.docs.map((d) => (d.data() as Map<String, dynamic>)['name'].toString()).toList();

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    value: _selectedSchool,
                    hint: const Text('Select School'),
                    items: schoolList.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                    onChanged: (v) => setState(() => _selectedSchool = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _selectedRoute,
                    hint: const Text('Select Route'),
                    items: routeList.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                    onChanged: (v) => setState(() => _selectedRoute = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: _vehicleNameC, decoration: const InputDecoration(labelText: 'Vehicle Name')),
                  const SizedBox(height: 12),
                  TextField(controller: _seatsC, decoration: const InputDecoration(labelText: 'Seats'), keyboardType: TextInputType.number),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () async {
                      if (_selectedSchool == null || _selectedRoute == null) return;
                      await _firestore.collection('driverRoutes').add({
                        'driverId': _user.uid,
                        'school': _selectedSchool!,
                        'route': _selectedRoute!,
                        'vehicle': _vehicleNameC.text,
                        'seats': _seatsC.text,
                      });
                      await _firestore.collection('users').doc(_user.uid).set({
                        'school': _selectedSchool!,
                        'route': _selectedRoute!,
                      }, SetOptions(merge: true));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Route and school saved successfully')),
                      );
                    },
                    child: const Text("Add Route"),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ================= Feedback & Earnings =================
  Widget _empty(String t) => Center(child: Text("$t Page"));

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore.collection('users').doc(_user.uid).snapshots(),
      builder: (_, snap) {
        if (!snap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final data = snap.data!.data() as Map<String, dynamic>? ?? {};

        final pages = [
          _profile(data),
          _dashboard(data),
          _assignedChildren(),
          _manageRoute(),
          _empty('Feedback'),
          _empty('Earnings'),
        ];

        return Scaffold(
          appBar: AppBar(title: const Text("Driver Dashboard")),
          drawer: Drawer(
            child: ListView(
              children: [
                UserAccountsDrawerHeader(
                  accountName: Text(data['name'] ?? 'Driver'),
                  accountEmail: null,
                  currentAccountPicture: CircleAvatar(
                    backgroundImage: data['profilePic'] != null ? NetworkImage(data['profilePic']) : null,
                    child: data['profilePic'] == null ? const Icon(Icons.person, size: 40) : null,
                  ),
                ),
                ...['Profile', 'Dashboard', 'Assigned Children', 'Manage Route', 'Feedback', 'Earnings'].asMap().entries.map(
                      (e) => ListTile(title: Text(e.value), onTap: () => setState(() => _index = e.key)),
                    ),
                ListTile(
                  title: const Text("Logout"),
                  onTap: () async {
                    await FirebaseAuth.instance.signOut();
                    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
                  },
                )
              ],
            ),
          ),
          body: pages[_index],
        );
      },
    );
  }
}
