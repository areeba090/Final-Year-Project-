import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import 'gps_controller.dart';
import 'driver_location_screen.dart';
import 'driver_parent_location_screen.dart';
import 'driver_ride_map_screen.dart';
import 'login_screen.dart';
import '../services/directions_service.dart';

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
  final Map<String, Future<DocumentSnapshot>> _parentFutures = {};

  Future<DocumentSnapshot> _getParentFuture(String parentId) {
    if (!_parentFutures.containsKey(parentId)) {
      _parentFutures[parentId] = _firestore.collection('users').doc(parentId).get();
    }
    return _parentFutures[parentId]!;
  }

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
  final Map<String, _RideMode> _selectedRideModeByChild = {};

  Widget _premiumCard({
    required Widget child,
    EdgeInsetsGeometry? margin,
    EdgeInsetsGeometry? padding,
    Color? baseColor,
  }) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            baseColor ?? Colors.white,
            AppTheme.subtleSurface.withOpacity(0.4),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withOpacity(0.06),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.white,
            blurRadius: 0,
            offset: const Offset(-2, -2),
          ),
        ],
        border: Border.all(color: Colors.white.withOpacity(0.8), width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
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

    return _premiumCard(
      margin: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.primary.withOpacity(0.1), width: 2),
                ),
                child: CircleAvatar(
                  radius: 28,
                  backgroundImage: img,
                  backgroundColor: AppTheme.subtleSurface,
                  child: img == null ? const Icon(Icons.person_rounded, color: AppTheme.textSecondary) : null,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: AppTheme.textPrimary),
                ),
              ),
              if (isLoading)
                const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              else if (AppTheme.isNarrow(context))
                const SizedBox.shrink()
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _smallButton(context, 'Upload', () => _pickUpload(type), false),
                    if (img != null) ...[
                      const SizedBox(width: 8),
                      _smallButton(context, 'View', () => _viewImage(label, img!), false),
                    ],
                  ],
                ),
            ],
          ),
          if (AppTheme.isNarrow(context)) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _smallButton(context, 'Upload', () => _pickUpload(type), false)),
                if (img != null) ...[
                  const SizedBox(width: 8),
                  Expanded(child: _smallButton(context, 'View', () => _viewImage(label, img!), false)),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _smallButton(BuildContext context, String label, VoidCallback onPressed, bool loading) {
    if (loading) return const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2));
    return SizedBox(
      height: 38,
      child: label == 'Upload'
          ? ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                minimumSize: Size.zero,
              ),
              child: Text(label),
            )
          : OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                minimumSize: Size.zero,
              ),
              child: Text(label),
            ),
    );
  }

  void _viewImage(String label, ImageProvider img) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: Text(label),
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
          body: InteractiveViewer(
            child: Center(
              child: Image(image: img, fit: BoxFit.contain),
            ),
          ),
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

    final routeName = (child['route'] ?? '').toString();
    double schoolLat = 0, schoolLng = 0;
    if (routeName.isNotEmpty) {
      final bounds = await getRouteBoundsByRouteName(_firestore, routeName);
      if (bounds != null) {
        schoolLat = bounds.startLat;
        schoolLng = bounds.startLng;
      }
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DriverParentLocationScreen(
          childName: (child['name'] ?? 'Child').toString(),
          parentLatitude: lat,
          parentLongitude: lng,
          schoolLatitude: schoolLat,
          schoolLongitude: schoolLng,
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

  bool _isProfileComplete(Map<String, dynamic> d) {
    final requiredFields = [
      'name', 'cnic', 'phone', 'licenseNumber', 
      'vehicleName', 'vehicleNumber', 'school', 'route', 'seats',
      'profilePic', 'cnicPic', 'licensePic', 'vehiclePic'
    ];
    for (final field in requiredFields) {
      if ((d[field] ?? '').toString().trim().isEmpty) return false;
    }
    // Specific checks
    if ((d['cnic'] ?? '').toString().length != 13) return false;
    if ((d['phone'] ?? '').toString().length != 11) return false;
    
    return true;
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
      final message = type == 'ride_started'
          ? 'Child Picked Up: $childName.'
          : 'Child Dropped Off: $childName.';
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

  _RideMode _getRideModeForChild(String childId) {
    return _selectedRideModeByChild[childId] ?? _RideMode.morning;
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
                future: _getParentFuture(parentId),
                builder: (context, parentSnap) {
                  if (!parentSnap.hasData) return const SizedBox();
                  final parentData = parentSnap.data!.data() as Map<String, dynamic>? ?? {};
                  final children = parentData['children'] as List<dynamic>? ?? [];
                  final assignedChildren = children.where((c) => c['assignedDriver'] == _user.uid).toList();
                  if (assignedChildren.isEmpty) return const SizedBox();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    bool changed = false;
                    for (final c in assignedChildren) {
                      final id = c['id']?.toString();
                      if (id != null && _childToParent[id] != parentId) {
                        _childToParent[id] = parentId;
                        changed = true;
                      }
                    }
                    if (changed) {
                      setState(() {});
                    }
                  });

                  return Column(
                    children: assignedChildren.map((child) {
                      final picUrl = child['photo'] ?? '';
                      final childId = child['id'] as String? ?? '';
                      final isChildOnRide = _childrenOnRide.contains(childId);
                      final isActionLoading = _rideActionChildId == childId;
                      final selectedRideMode = _getRideModeForChild(childId);
                      final pickupLabel = selectedRideMode == _RideMode.morning ? "Parent's Home" : 'School';
                      final destinationLabel = selectedRideMode == _RideMode.morning ? 'School' : "Parent's Home";
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
                                      SegmentedButton<_RideMode>(
                                        segments: const [
                                          ButtonSegment<_RideMode>(
                                            value: _RideMode.morning,
                                            label: Text('Morning Ride'),
                                            icon: Icon(Icons.wb_sunny_outlined, size: 16),
                                          ),
                                          ButtonSegment<_RideMode>(
                                            value: _RideMode.evening,
                                            label: Text('Evening Ride'),
                                            icon: Icon(Icons.nightlight_round, size: 16),
                                          ),
                                        ],
                                        selected: {selectedRideMode},
                                        onSelectionChanged: isChildOnRide
                                            ? null
                                            : (selection) {
                                                setState(() {
                                                  _selectedRideModeByChild[childId] = selection.first;
                                                });
                                              },
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: isActionLoading
                                            ? null
                                            : () async {
                                                final routeName = (driverData['route'] ?? '').toString();
                                                if (routeName.isEmpty) {
                                                  if (mounted) {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      const SnackBar(
                                                        content: Text('Route is not set for this driver.'),
                                                        behavior: SnackBarBehavior.floating,
                                                      ),
                                                    );
                                                  }
                                                  return;
                                                }
                                                final bounds = await getRouteBoundsByRouteName(
                                                  _firestore,
                                                  routeName,
                                                );
                                                 if (bounds == null || !mounted) return;
                                                 final parentLat = (child['parentLatitude'] as num?)?.toDouble();
                                                 final parentLng = (child['parentLongitude'] as num?)?.toDouble();

                                                 await Navigator.push(
                                                   context,
                                                   MaterialPageRoute(
                                                     builder: (_) => DriverRideMapScreen(
                                                       childName: (child['name'] ?? 'Child').toString(),
                                                       rideModeLabel: selectedRideMode == _RideMode.morning
                                                           ? 'Morning Ride'
                                                           : 'Evening Ride',
                                                       parentLocation: LatLng(parentLat ?? bounds.startLat, parentLng ?? bounds.startLng),
                                                       schoolLocation: LatLng(bounds.startLat, bounds.startLng),
                                                       isMorningRide: selectedRideMode == _RideMode.morning,
                                                       liveTrackingMode: isChildOnRide,
                                                      ),
                                                    ),
                                                  );
                                                },
                                        icon: const Icon(Icons.map_outlined, size: 18),
                                        label: Text(narrow ? 'Map' : 'Show map'),
                                      ),
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

                                                  final parentLat = (child['parentLatitude'] as num?)?.toDouble();
                                                  final parentLng = (child['parentLongitude'] as num?)?.toDouble();
                                                  
                                                  // Set GPS tracking bounds based on ride mode
                                                  double startLatForBounds, startLngForBounds, endLatForBounds, endLngForBounds;
                                                  
                                                  if (selectedRideMode == _RideMode.morning) {
                                                    // Morning ride: Parent home → School
                                                    startLatForBounds = parentLat ?? bounds.startLat;
                                                    startLngForBounds = parentLng ?? bounds.startLng;
                                                    endLatForBounds = bounds.startLat;
                                                    endLngForBounds = bounds.startLng;
                                                  } else {
                                                    // Evening ride: School → Parent home
                                                    startLatForBounds = bounds.startLat;
                                                    startLngForBounds = bounds.startLng;
                                                    endLatForBounds = parentLat ?? bounds.endLat;
                                                    endLngForBounds = parentLng ?? bounds.endLng;
                                                  }

                                                  if (!newRideOn) {
                                                    final distanceToDest = Geolocator.distanceBetween(
                                                      currentPosition.latitude,
                                                      currentPosition.longitude,
                                                      endLatForBounds,
                                                      endLngForBounds,
                                                    );
                                                    if (distanceToDest > 50) {
                                                      if (mounted) {
                                                        ScaffoldMessenger.of(context).showSnackBar(
                                                          const SnackBar(
                                                            content: Text('Move within 50m of destination to stop the ride.'),
                                                            backgroundColor: AppTheme.error,
                                                            behavior: SnackBarBehavior.floating,
                                                          ),
                                                        );
                                                      }
                                                      return;
                                                    }
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
                                                    
                                                    final routePoints = await getRoadRoutePoints(
                                                      originLat: startLatForBounds,
                                                      originLng: startLngForBounds,
                                                      destLat: endLatForBounds,
                                                      destLng: endLngForBounds,
                                                    );

                                                    final driverBounds = DriverRouteBounds(
                                                      startLat: startLatForBounds,
                                                      startLng: startLngForBounds,
                                                      endLat: endLatForBounds,
                                                      endLng: endLngForBounds,
                                                      polylinePoints: routePoints?.map((p) => (p.latitude, p.longitude)).toList(),
                                                    );
                                                    
                                                    // Initialize driverLocations doc immediately so parent sees driver right away
                                                    if (newRideOn) {
                                                      try {
                                                        await _firestore.collection('driverLocations').doc(_user.uid).set({
                                                          'status': 'onRide',
                                                          'timestamp': FieldValue.serverTimestamp(),
                                                          'latitude': currentPosition.latitude,
                                                          'longitude': currentPosition.longitude,
                                                        }, SetOptions(merge: true));
                                                      } catch (e) {
                                                        print('Failed to initialize driverLocations: $e');
                                                      }
                                                    }
                                                    
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
                                                              content: const Text('GPS failed to start. Please check location services in settings.'),
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
        final isComplete = _isProfileComplete(data);
        
        // Force profile tab if incomplete
        if (!isComplete && _index != 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _index != 0) setState(() => _index = 0);
          });
        }

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
          drawer: _drawer(data, isComplete),
          appBar: AppBar(
            title: Text(_navItems[_index].label),
            actions: [
              if (_index == 0 && isComplete)
                IconButton(
                  icon: const Icon(Icons.notifications_outlined),
                  onPressed: () => setState(() => _index = 2),
                ),
            ],
          ),
          body: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppTheme.primary.withOpacity(0.04),
                        AppTheme.surface,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: -80,
                right: -80,
                child: CircleAvatar(
                  radius: 120,
                  backgroundColor: AppTheme.primary.withOpacity(0.03),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    if (!isComplete)
                      Container(
                        width: double.infinity,
                        color: AppTheme.error.withOpacity(0.1),
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: AppTheme.error, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Complete your profile to unlock all features',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.error),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Expanded(child: pages[_index]),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _drawer(Map<String, dynamic> data, bool isComplete) {
    return Drawer(
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
                    final isProfileTab = e.key == 0;
                    final enabled = isProfileTab || isComplete;
                    final selected = _index == e.key;
                    
                    return Opacity(
                      opacity: enabled ? 1.0 : 0.5,
                      child: _drawerNavTile(
                        icon: e.value.icon,
                        label: e.value.label + (enabled ? '' : ' 🔒'),
                        selected: selected,
                        onTap: () {
                          if (enabled) {
                            setState(() => _index = e.key);
                            Navigator.pop(context);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please complete and save your profile first')),
                            );
                          }
                        },
                      ),
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
    );
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  const _NavItem(this.label, this.icon);
}

enum _RideMode { morning, evening }
