import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import 'gps_controller.dart';
import 'driver_location_screen.dart';
import 'driver_parent_location_screen.dart';
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
  final Set<String> _childrenOnRide = {};
  final Map<String, String> _childToParent = {};
  bool _savingProfile = false;
  String? _rideActionChildId;
  static const double _rideActionAllowedMeters = 100.0;

  Widget _premiumCard({
    required Widget child,
    EdgeInsetsGeometry? margin,
    EdgeInsetsGeometry? padding,
  }) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, AppTheme.subtleSurface.withOpacity(0.55)],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.9)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: padding ?? EdgeInsets.all(AppTheme.horizontalPadding(context)),
          child: child,
        ),
      ),
    );
  }

  Widget _drawerNavTile({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: selected ? AppTheme.primary.withOpacity(0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: selected ? AppTheme.primary : AppTheme.textSecondary,
          size: 22,
        ),
        title: Text(
          label,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppTheme.primary : AppTheme.textPrimary,
          ),
        ),
        onTap: onTap,
      ),
    );
  }

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

  Widget _imgRow(String label, Uint8List? local, String? url, String type, BuildContext context) {
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
    final isNarrow = AppTheme.isNarrow(context);
    return _premiumCard(
      margin: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context)),
      padding: EdgeInsets.all(isNarrow ? 12 : 16),
      child: Row(
          children: [
            CircleAvatar(
              radius: isNarrow ? 24 : 28,
              backgroundImage: img,
              backgroundColor: AppTheme.divider,
              child: img == null ? Icon(Icons.person, color: AppTheme.textSecondary) : null,
            ),
            SizedBox(width: isNarrow ? 12 : 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                  if (isNarrow)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _smallButton(context, 'Upload', () => _pickUpload(type), isLoading),
                        if (img != null) _smallButton(context, 'View', () => _viewImage(label, img!), false),
                      ],
                    )
                  else
                    const SizedBox(height: 4),
                ],
              ),
            ),
            if (!isNarrow) ...[
              if (isLoading)
                const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              else
                ElevatedButton(onPressed: () => _pickUpload(type), child: const Text('Upload')),
              if (img != null) ...[
                const SizedBox(width: 8),
                OutlinedButton(onPressed: () => _viewImage(label, img!), child: const Text('View')),
              ],
            ],
          ],
        ),
    );
  }

  Widget _smallButton(BuildContext context, String label, VoidCallback onPressed, bool loading) {
    if (loading) return const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2));
    return SizedBox(
      height: 32,
      child: label == 'Upload'
          ? ElevatedButton(onPressed: onPressed, child: Text(label))
          : OutlinedButton(onPressed: onPressed, child: Text(label)),
    );
  }

  void _viewImage(String label, ImageProvider img) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(label)),
          body: SafeArea(child: Center(child: Image(image: img))),
        ),
      ),
    );
  }

  Future<void> _openParentLocationForChild(Map<String, dynamic> child) async {
    final lat = (child['parentLatitude'] as num?)?.toDouble();
    final lng = (child['parentLongitude'] as num?)?.toDouble();
    if (lat == null || lng == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Parent location is not available for this child.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DriverParentLocationScreen(
          childName: (child['name'] ?? 'Child').toString(),
          parentLatitude: lat,
          parentLongitude: lng,
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    if (_nameC.text.isEmpty || _cnicC.text.length != 13 || _phoneC.text.length != 11) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill Name, CNIC (13 digits), and Phone (11 digits)')),
      );
      return;
    }
    setState(() => _savingProfile = true);
    try {
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('Profile saved'), backgroundColor: AppTheme.success, behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _savingProfile = false);
      }
    }
  }

  Future<Position?> _resolveCurrentPosition() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
    }
    return Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  }

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

    final padding = AppTheme.contentPadding(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;
        return SingleChildScrollView(
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: AppTheme.maxContentWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Documents & photos', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                SizedBox(height: AppTheme.verticalSpacing(context)),
                _imgRow('Profile', _profilePic, d['profilePic'], 'profilePic', context),
                _imgRow('CNIC', _cnicPic, d['cnicPic'], 'cnicPic', context),
                _imgRow('License', _licensePic, d['licensePic'], 'licensePic', context),
                _imgRow('Vehicle', _vehiclePic, d['vehiclePic'], 'vehiclePic', context),
                SizedBox(height: AppTheme.verticalSpacing(context) * 2),
                Text('Personal & vehicle info', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                SizedBox(height: AppTheme.verticalSpacing(context)),
                TextField(controller: _nameC, decoration: const InputDecoration(labelText: 'Name'), textInputAction: TextInputAction.next),
                SizedBox(height: AppTheme.verticalSpacing(context)),
                TextField(controller: _cnicC, decoration: const InputDecoration(labelText: 'CNIC (13 digits)'), keyboardType: TextInputType.number, inputFormatters: [LengthLimitingTextInputFormatter(13)], textInputAction: TextInputAction.next),
                SizedBox(height: AppTheme.verticalSpacing(context)),
                TextField(controller: _phoneC, decoration: const InputDecoration(labelText: 'Phone (11 digits)'), keyboardType: TextInputType.phone, inputFormatters: [LengthLimitingTextInputFormatter(11)], textInputAction: TextInputAction.next),
                SizedBox(height: AppTheme.verticalSpacing(context)),
                TextField(controller: _licenseC, decoration: const InputDecoration(labelText: 'License Number'), textInputAction: TextInputAction.next),
                SizedBox(height: AppTheme.verticalSpacing(context)),
                TextField(controller: _vehicleNameC, decoration: const InputDecoration(labelText: 'Vehicle Name'), textInputAction: TextInputAction.next),
                SizedBox(height: AppTheme.verticalSpacing(context)),
                TextField(controller: _vehicleNumberC, decoration: const InputDecoration(labelText: 'Vehicle Number'), textInputAction: TextInputAction.next),
                SizedBox(height: AppTheme.verticalSpacing(context)),
                StreamBuilder<QuerySnapshot>(
                  stream: _firestore.collection('schools').snapshots(),
                  builder: (context, schoolSnap) {
                    if (!schoolSnap.hasData) return const Center(child: CircularProgressIndicator());
                    final schoolList = schoolSnap.data!.docs.map((d) => (d.data() as Map<String, dynamic>)['name'].toString()).toList();
                    return DropdownButtonFormField<String>(
                      value: _selectedSchool,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'School'),
                      items: schoolList.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis, maxLines: 1))).toList(),
                      onChanged: (v) => setState(() => _selectedSchool = v),
                    );
                  },
                ),
                SizedBox(height: AppTheme.verticalSpacing(context)),
                StreamBuilder<QuerySnapshot>(
                  stream: _firestore.collection('routes').snapshots(),
                  builder: (context, routeSnap) {
                    if (!routeSnap.hasData) return const Center(child: CircularProgressIndicator());
                    final routeList = routeSnap.data!.docs.map((d) => (d.data() as Map<String, dynamic>)['name'].toString()).toList();
                    return DropdownButtonFormField<String>(
                      value: _selectedRoute,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Route'),
                      items: routeList.map((r) => DropdownMenuItem(value: r, child: Text(r, overflow: TextOverflow.ellipsis, maxLines: 1))).toList(),
                      onChanged: (v) => setState(() => _selectedRoute = v),
                    );
                  },
                ),
                SizedBox(height: AppTheme.verticalSpacing(context)),
                TextField(controller: _seatsC, decoration: const InputDecoration(labelText: 'Seats'), keyboardType: TextInputType.number, textInputAction: TextInputAction.done),
                SizedBox(height: AppTheme.verticalSpacing(context) * 2),
                FilledButton.icon(
                  onPressed: _savingProfile ? null : _saveProfile,
                  icon: const Icon(Icons.save_rounded, size: 20),
                  label: Text(_savingProfile ? 'Saving…' : 'Save profile'),
                ),
                SizedBox(height: MediaQuery.paddingOf(context).bottom + 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _dashboard(Map<String, dynamic> d) {
    final padding = AppTheme.contentPadding(context);
    final isOnRide = _childrenOnRide.isNotEmpty;
    return SingleChildScrollView(
      padding: padding,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: AppTheme.maxContentWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _premiumCard(
              child: Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundImage: d['profilePic'] != null ? NetworkImage(d['profilePic']) : null,
                      backgroundColor: AppTheme.primary.withOpacity(0.2),
                      child: d['profilePic'] == null ? const Icon(Icons.person, size: 32, color: AppTheme.primary) : null,
                    ),
                    SizedBox(width: AppTheme.horizontalPadding(context)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d['name'] ?? 'Driver', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isOnRide ? AppTheme.success.withOpacity(0.15) : AppTheme.textSecondary.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(isOnRide ? Icons.directions_car : Icons.pause_circle_outline, size: 16, color: isOnRide ? AppTheme.success : AppTheme.textSecondary),
                                const SizedBox(width: 6),
                                Text(isOnRide ? 'On ride' : 'Offline', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: isOnRide ? AppTheme.success : AppTheme.textSecondary)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ),
            SizedBox(height: AppTheme.verticalSpacing(context)),
            _infoTile(Icons.badge_outlined, 'CNIC', d['cnic'] ?? '—'),
            _infoTile(Icons.drive_eta_outlined, 'License', d['licenseNumber'] ?? '—'),
            _infoTile(Icons.directions_car_outlined, 'Vehicle', '${d['vehicleName'] ?? '—'} (${d['vehicleNumber'] ?? '—'})'),
            _infoTile(Icons.school_outlined, 'School', d['school'] ?? '—'),
            _infoTile(Icons.route_outlined, 'Route', d['route'] ?? '—'),
            _infoTile(Icons.event_seat_outlined, 'Seats', d['seats'] ?? '—'),
            SizedBox(height: MediaQuery.paddingOf(context).bottom + 16),
          ],
        ),
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return _premiumCard(
      margin: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context)),
      padding: EdgeInsets.zero,
      child: ListTile(
          leading: CircleAvatar(radius: 22, backgroundColor: AppTheme.primary.withOpacity(0.12), child: Icon(icon, color: AppTheme.primary, size: 22)),
          title: Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          subtitle: Text(value, style: const TextStyle(fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
      ),
    );
  }

  Future<void> _sendRideNotificationToParent({required String type, required String parentId, required String childName}) async {
    if (parentId.isEmpty) return;
    try {
      final driverSnap = await _firestore.collection('users').doc(_user.uid).get();
      final driverName = driverSnap.data()?['name'] ?? 'Driver';
      final message = type == 'ride_started' ? 'Ride started for $childName.' : 'Ride finished for $childName.';
      await _firestore.collection('notifications').add({
        'parentId': parentId,
        'type': type,
        'driverId': _user.uid,
        'driverName': driverName,
        'childName': childName,
        'message': message,
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
      });
    } catch (e) {
      debugPrint('Error sending ride notification: $e');
    }
  }

  Widget _assignedChildren(Map<String, dynamic> driverData) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('requests').where('driverId', isEqualTo: _user.uid).where('status', isEqualTo: 'approved').snapshots(),
      builder: (context, driverReqSnap) {
        if (!driverReqSnap.hasData) return const Center(child: CircularProgressIndicator());
        final driverRequests = driverReqSnap.data!.docs;
        if (driverRequests.isEmpty) {
          return Center(
            child: Padding(
              padding: AppTheme.contentPadding(context),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline, size: 64, color: AppTheme.textSecondary.withOpacity(0.5)),
                  const SizedBox(height: 16),
                  Text('No children assigned yet', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.textSecondary)),
                  const SizedBox(height: 8),
                  Text('Assigned children will appear here.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary)),
                ],
              ),
            ),
          );
        }
        final uniqueParentIds = driverRequests.map((d) => (d.data() as Map<String, dynamic>)['parentId'] as String?).whereType<String>().toSet().toList();

        return SingleChildScrollView(
          padding: AppTheme.contentPadding(context),
          child: Column(
            children: uniqueParentIds.map((parentId) {
              return FutureBuilder<DocumentSnapshot>(
                future: _firestore.collection('users').doc(parentId).get(),
                builder: (context, parentSnap) {
                  if (!parentSnap.hasData) return const SizedBox();
                  final parentData = parentSnap.data!.data() as Map<String, dynamic>? ?? {};
                  final children = parentData['children'] as List<dynamic>? ?? [];
                  final assignedChildren = children.where((c) => c['assignedDriver'] == _user.uid).toList();
                  if (assignedChildren.isEmpty) return const SizedBox();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    setState(() {
                      for (final c in assignedChildren) {
                        final id = c['id']?.toString();
                        if (id != null) _childToParent[id] = parentId;
                      }
                    });
                  });

                  return Column(
                    children: assignedChildren.map((child) {
                      final picUrl = child['photo'] ?? '';
                      final childId = child['id'] as String? ?? '';
                      final isChildOnRide = _childrenOnRide.contains(childId);
                      final isActionLoading = _rideActionChildId == childId;
                      return _premiumCard(
                        margin: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context)),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      if (picUrl.toString().isNotEmpty) {
                                        _viewImage(child['name'] ?? 'Child', NetworkImage(picUrl.toString()));
                                      }
                                    },
                                    child: CircleAvatar(
                                      radius: 28,
                                      backgroundImage: picUrl.toString().isNotEmpty ? NetworkImage(picUrl) : null,
                                      backgroundColor: AppTheme.primary.withOpacity(0.15),
                                      child: picUrl.toString().isEmpty ? const Icon(Icons.person, size: 28, color: AppTheme.primary) : null,
                                    ),
                                  ),
                                  SizedBox(width: AppTheme.horizontalPadding(context)),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(child['name'] ?? 'Unknown', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                                        const SizedBox(height: 2),
                                        Text('Age: ${child['age'] ?? '—'} • ${child['school'] ?? '—'}', style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                                        Text('Route: ${child['route'] ?? '—'}', style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                                        Text('Parent: ${parentData['name'] ?? 'Unknown'}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: AppTheme.verticalSpacing(context)),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final narrow = constraints.maxWidth < 320;
                                  return Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: () async {
                                          final telUri = Uri(scheme: 'tel', path: parentData['phone'] ?? '');
                                          if (await canLaunchUrl(telUri)) await launchUrl(telUri);
                                        },
                                        icon: const Icon(Icons.phone_outlined, size: 18),
                                        label: Text(narrow ? 'Call' : 'Call parent'),
                                      ),
                                      if (isChildOnRide)
                                        OutlinedButton.icon(
                                          onPressed: () => _openParentLocationForChild(
                                            child,
                                          ),
                                          icon: const Icon(
                                            Icons.location_on_outlined,
                                            size: 18,
                                          ),
                                          label: Text(
                                            narrow
                                                ? 'Location'
                                                : 'Parent location',
                                          ),
                                        ),
                                      FilledButton.icon(
                                        onPressed: isActionLoading
                                            ? null
                                            : () async {
                                                setState(() => _rideActionChildId = childId);
                                                try {
                                                  final newRideOn = !isChildOnRide;
                                                  final routeName =
                                                      (driverData['route'] ?? '').toString();
                                                  if (routeName.isEmpty) {
                                                    if (mounted) {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        const SnackBar(
                                                          content: Text(
                                                            'Route is not set. Please update your route before starting/stopping ride.',
                                                          ),
                                                          behavior: SnackBarBehavior.floating,
                                                        ),
                                                      );
                                                    }
                                                    return;
                                                  }

                                                  final bounds =
                                                      await getRouteBoundsByRouteName(
                                                    _firestore,
                                                    routeName,
                                                  );
                                                  if (bounds == null) {
                                                    if (mounted) {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        const SnackBar(
                                                          content: Text(
                                                            'Unable to verify route location for this ride.',
                                                          ),
                                                          behavior: SnackBarBehavior.floating,
                                                        ),
                                                      );
                                                    }
                                                    return;
                                                  }

                                                  final currentPosition =
                                                      await _resolveCurrentPosition();
                                                  if (currentPosition == null) {
                                                    if (mounted) {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        const SnackBar(
                                                          content: Text(
                                                            'Location permission is required to start/stop ride.',
                                                          ),
                                                          behavior: SnackBarBehavior.floating,
                                                        ),
                                                      );
                                                    }
                                                    return;
                                                  }

                                                  final targetLat = newRideOn
                                                      ? bounds.startLat
                                                      : bounds.endLat;
                                                  final targetLng = newRideOn
                                                      ? bounds.startLng
                                                      : bounds.endLng;
                                                  final distanceMeters =
                                                      Geolocator.distanceBetween(
                                                    currentPosition.latitude,
                                                    currentPosition.longitude,
                                                    targetLat,
                                                    targetLng,
                                                  );
                                                  if (distanceMeters >
                                                      _rideActionAllowedMeters) {
                                                    final actionText = newRideOn
                                                        ? 'start'
                                                        : 'stop';
                                                    if (mounted) {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                            'You can only $actionText ride within 100m of the expected location.',
                                                          ),
                                                          behavior: SnackBarBehavior.floating,
                                                        ),
                                                      );
                                                    }
                                                    return;
                                                  }

                                                  final childName = child['name'] ?? 'your child';
                                                  await _sendRideNotificationToParent(type: newRideOn ? 'ride_started' : 'ride_ended', parentId: parentId, childName: childName);
                                                  setState(() {
                                                    if (newRideOn) {
                                                      _childrenOnRide.add(childId);
                                                    } else {
                                                      _childrenOnRide.remove(childId);
                                                    }
                                                  });
                                                  if (_childrenOnRide.isNotEmpty) {
                                                    final parentIds = _childrenOnRide.map((c) => _childToParent[c]).whereType<String>().toSet().toList();
                                                    final driverBounds = bounds != null
                                                        ? DriverRouteBounds(startLat: bounds.startLat, startLng: bounds.startLng, endLat: bounds.endLat, endLng: bounds.endLng)
                                                        : null;
                                                    if (GPSController.isTracking) {
                                                      GPSController.updateRideParents(parentIds);
                                                    } else {
                                                      await GPSController.startTracking(_user.uid, routeBounds: driverBounds, parentIds: parentIds);
                                                      // Give GPS a moment to start
                                                      await Future.delayed(const Duration(milliseconds: 500));
                                                      if (!GPSController.isTracking) {
                                                        if (mounted) {
                                                          ScaffoldMessenger.of(context).showSnackBar(
                                                            SnackBar(
                                                              content: const Text('GPS permission required. Please enable location services in settings.'),
                                                              backgroundColor: AppTheme.error,
                                                              behavior: SnackBarBehavior.floating,
                                                            ),
                                                          );
                                                        }
                                                      }
                                                    }
                                                  } else {
                                                    GPSController.stopTracking();
                                                    await GPSController.clearRideStatus(_user.uid);
                                                  }
                                                  await _firestore.collection('users').doc(_user.uid).set({'rideStatus': _childrenOnRide.isNotEmpty ? 'on' : 'off'}, SetOptions(merge: true));
                                                } catch (e) {
                                                  if (mounted) {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(
                                                        content: Text('Error: $e'),
                                                        backgroundColor: AppTheme.error,
                                                        behavior: SnackBarBehavior.floating,
                                                      ),
                                                    );
                                                  }
                                                } finally {
                                                  if (mounted) {
                                                    setState(() => _rideActionChildId = null);
                                                  }
                                                }
                                              },
                                        style: FilledButton.styleFrom(backgroundColor: isChildOnRide ? AppTheme.error : AppTheme.success),
                                        icon: isActionLoading
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                              )
                                            : Icon(isChildOnRide ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 18),
                                        label: Text(
                                          isActionLoading
                                              ? 'Please wait…'
                                              : (isChildOnRide ? 'Stop ride' : 'Start ride'),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
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
            final padding = AppTheme.contentPadding(context);
            return SingleChildScrollView(
              padding: padding,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: AppTheme.maxContentWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      value: _selectedSchool,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'School'),
                      items: schoolList.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis, maxLines: 1))).toList(),
                      onChanged: (v) => setState(() => _selectedSchool = v),
                    ),
                    SizedBox(height: AppTheme.verticalSpacing(context)),
                    DropdownButtonFormField<String>(
                      value: _selectedRoute,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Route'),
                      items: routeList.map((r) => DropdownMenuItem(value: r, child: Text(r, overflow: TextOverflow.ellipsis, maxLines: 1))).toList(),
                      onChanged: (v) => setState(() => _selectedRoute = v),
                    ),
                    SizedBox(height: AppTheme.verticalSpacing(context)),
                    TextField(controller: _vehicleNameC, decoration: const InputDecoration(labelText: 'Vehicle name')),
                    SizedBox(height: AppTheme.verticalSpacing(context)),
                    TextField(controller: _seatsC, decoration: const InputDecoration(labelText: 'Seats'), keyboardType: TextInputType.number),
                    SizedBox(height: AppTheme.verticalSpacing(context) * 2),
                    FilledButton.icon(
                      onPressed: () async {
                        if (_selectedSchool == null || _selectedRoute == null) return;
                        await _firestore.collection('driverRoutes').add({
                          'driverId': _user.uid,
                          'school': _selectedSchool!,
                          'route': _selectedRoute!,
                          'vehicle': _vehicleNameC.text,
                          'seats': _seatsC.text,
                        });
                        await _firestore.collection('users').doc(_user.uid).set({'school': _selectedSchool!, 'route': _selectedRoute!}, SetOptions(merge: true));
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: const Text('Route saved'), backgroundColor: AppTheme.success, behavior: SnackBarBehavior.floating),
                          );
                        }
                      },
                      icon: const Icon(Icons.add_road_rounded, size: 20),
                      label: const Text('Add route'),
                    ),
                    SizedBox(height: MediaQuery.paddingOf(context).bottom + 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _empty(String title, IconData icon) {
    return Center(
      child: Padding(
        padding: AppTheme.contentPadding(context),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: AppTheme.textSecondary.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text('$title', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }

  static const List<_NavItem> _navItems = [
    _NavItem('Profile', Icons.person_rounded),
    _NavItem('Dashboard', Icons.dashboard_rounded),
    _NavItem('Assigned Children', Icons.people_rounded),
    _NavItem('Manage Route', Icons.route_rounded),
    _NavItem('Feedback', Icons.feedback_outlined),
    _NavItem('Earnings', Icons.payments_outlined),
  ];

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
          _assignedChildren(data),
          _manageRoute(),
          _empty('Feedback', Icons.feedback_outlined),
          _empty('Earnings', Icons.payments_outlined),
        ];

        return Scaffold(
          backgroundColor: AppTheme.surface,
          body: SafeArea(
            child: pages[_index],
          ),
          appBar: AppBar(
            title: Text(_navItems[_index].label),
          ),
          drawer: Drawer(
            child: SafeArea(
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(AppTheme.horizontalPadding(context)),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppTheme.primary, AppTheme.primaryDark],
                      ),
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: 16),
                        CircleAvatar(
                          radius: 40,
                          backgroundImage: data['profilePic'] != null ? NetworkImage(data['profilePic']) : null,
                          backgroundColor: Colors.white24,
                          child: data['profilePic'] == null ? const Icon(Icons.person, size: 40, color: Colors.white) : null,
                        ),
                        const SizedBox(height: 12),
                        Text(data['name'] ?? 'Driver', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
                        const SizedBox(height: 4),
                        Text(data['phone'] ?? '', style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.9))),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.symmetric(vertical: AppTheme.verticalSpacing(context)),
                      children: [
                        ..._navItems.asMap().entries.map((e) {
                          final selected = _index == e.key;
                          return _drawerNavTile(
                            icon: e.value.icon,
                            label: e.value.label,
                            selected: selected,
                            onTap: () {
                              setState(() => _index = e.key);
                              Navigator.pop(context);
                            },
                          );
                        }),
                        const Divider(height: 24),
                        _drawerNavTile(
                          icon: Icons.logout_rounded,
                          label: 'Logout',
                          selected: false,
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
}

class _NavItem {
  final String label;
  final IconData icon;
  const _NavItem(this.label, this.icon);
}
