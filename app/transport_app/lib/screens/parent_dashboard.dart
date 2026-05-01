import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';
import '../services/web_notifications.dart';
import '../services/local_notifications.dart';
import '../config/maps_config.dart';
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
  bool _savingPersonalInfo = false;
  String? _requestingForChildId;

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
        final String title = isDeviation
            ? 'Route deviation'
            : (isStarted ? 'Child Picked Up' : 'Child Dropped Off');
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
  final TextEditingController _locationSearchController = TextEditingController();
  String? _childSchool;
  String? _childRoute;
  int? _editingChildIndex;
  LatLng? _selectedParentLocation;
  bool _loadingParentLocation = false;
  GoogleMapController? _childLocationMapController;
  LatLng? _pendingChildMapCameraTarget;
  static final RegExp _nameRegex = RegExp(r"^[A-Za-z ]{2,40}$");
  static final RegExp _timeRegex =
      RegExp(r"^(0?[1-9]|1[0-2]):[0-5][0-9]\s?(AM|PM|am|pm)$");

  int? _parse12HourTimeToMinutes(String value) {
    final normalized = value.trim().toUpperCase();
    final match = RegExp(r"^(\d{1,2}):(\d{2})\s?(AM|PM)$").firstMatch(normalized);
    if (match == null) return null;
    final hourRaw = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    final period = match.group(3)!;
    if (hourRaw == null || minute == null || hourRaw < 1 || hourRaw > 12) {
      return null;
    }
    int hour24 = hourRaw % 12;
    if (period == 'PM') hour24 += 12;
    return hour24 * 60 + minute;
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    _childNameController.dispose();
    _childAgeController.dispose();
    _childRouteDetailsController.dispose();
    _childSchoolOnController.dispose();
    _childSchoolOffController.dispose();
    _locationSearchController.dispose();
    super.dispose();
  }

  Future<void> _pickTimeForController(TextEditingController controller) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      helpText: 'Select time',
    );
    if (picked == null) return;
    final hour = picked.hourOfPeriod == 0 ? 12 : picked.hourOfPeriod;
    final minute = picked.minute.toString().padLeft(2, '0');
    final period = picked.period == DayPeriod.am ? 'AM' : 'PM';
    setState(() {
      controller.text = '$hour:$minute $period';
    });
  }

  String? _validateChildForm(List<Map<String, dynamic>> parentChildren) {
    final name = _childNameController.text.trim();
    final ageText = _childAgeController.text.trim();
    final routeDetails = _childRouteDetailsController.text.trim();
    final schoolOn = _childSchoolOnController.text.trim();
    final schoolOff = _childSchoolOffController.text.trim();

    if (_childSchool == null || _childRoute == null) {
      return 'Please select school and route.';
    }
    if (!_nameRegex.hasMatch(name)) {
      return 'Child name must be 2-40 letters only.';
    }
    final age = int.tryParse(ageText);
    if (age == null || age < 3 || age > 18) {
      return 'Age must be a valid number between 3 and 18.';
    }
    if (routeDetails.length < 5) {
      return 'Route details must be at least 5 characters.';
    }
    if (!_timeRegex.hasMatch(schoolOn) || !_timeRegex.hasMatch(schoolOff)) {
      return 'Use time format like 07:30 AM for school on/off.';
    }
    final onMinutes = _parse12HourTimeToMinutes(schoolOn);
    final offMinutes = _parse12HourTimeToMinutes(schoolOff);
    if (onMinutes == null || offMinutes == null) {
      return 'Please choose valid school on/off times.';
    }
    if (offMinutes - onMinutes < 180) {
      return 'School off time must be at least 3 hours after school on time.';
    }
    if (_selectedParentLocation == null) {
      return 'Please select parent location on the map.';
    }
    
    // Photo mandatory check
    final hasPhoto = _childImageBytes != null || 
                     (_editingChildIndex != null && (parentChildren[_editingChildIndex!]['photo'] ?? '').toString().isNotEmpty);
    if (!hasPhoto) {
      return 'Please upload a child photo.';
    }
    
    return null;
  }

  Future<Position?> _getCurrentParentPosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return null;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return null;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      return null;
    }

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _focusChildLocationOnMap(LatLng target, {double zoom = 15}) async {
    final controller = _childLocationMapController;
    if (controller == null) {
      _pendingChildMapCameraTarget = target;
      return;
    }
    try {
      await controller.animateCamera(CameraUpdate.newLatLngZoom(target, zoom));
    } catch (_) {
      // Fallback for platforms where animateCamera can be flaky right after rebuild.
      await controller.moveCamera(CameraUpdate.newLatLngZoom(target, zoom));
    }
  }

  Future<LatLng?> _resolveAddressToLatLng(String query) async {
    final cleaned = query.trim();
    if (cleaned.isEmpty) return null;
    final key = googleMapsApiKey;
    if (key.isNotEmpty) {
      final geocodeUrl = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?address=${Uri.encodeQueryComponent(cleaned)}'
        '&key=$key',
      );
      try {
        final response =
            await http.get(geocodeUrl).timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          if ((data['status'] as String?) == 'OK') {
            final results = data['results'] as List<dynamic>? ?? const [];
            if (results.isNotEmpty) {
              final first = results.first as Map<String, dynamic>;
              final geometry = first['geometry'] as Map<String, dynamic>?;
              final location = geometry?['location'] as Map<String, dynamic>?;
              final lat = (location?['lat'] as num?)?.toDouble();
              final lng = (location?['lng'] as num?)?.toDouble();
              if (lat != null && lng != null) {
                return LatLng(lat, lng);
              }
            }
          }
        }
      } catch (_) {
        // Fallback to geocoding package below.
      }
    }
    try {
      final result = await locationFromAddress(cleaned);
      if (result.isEmpty) return null;
      return LatLng(result.first.latitude, result.first.longitude);
    } catch (_) {
      // Final fallback: OpenStreetMap Nominatim (no API key required).
      final nominatimUrl = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeQueryComponent(cleaned)}'
        '&format=json'
        '&limit=1',
      );
      try {
        final response = await http.get(
          nominatimUrl,
          headers: const {
            'User-Agent': 'transport-app/1.0 (location-search)',
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) return null;
        final data = jsonDecode(response.body) as List<dynamic>;
        if (data.isEmpty) return null;
        final first = data.first as Map<String, dynamic>;
        final lat = double.tryParse((first['lat'] ?? '').toString());
        final lng = double.tryParse((first['lon'] ?? '').toString());
        if (lat == null || lng == null) return null;
        return LatLng(lat, lng);
      } catch (_) {
        return null;
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchLocationSuggestions(
      String query) async {
    final cleaned = query.trim();
    final key = googleMapsApiKey;
    if (cleaned.isEmpty) return const [];
    if (key.isEmpty) {
      // If Google key isn't available, still provide suggestions via Nominatim.
      final nominatimUrl = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeQueryComponent(cleaned)}'
        '&format=json'
        '&addressdetails=1'
        '&limit=8',
      );
      try {
        final response = await http.get(
          nominatimUrl,
          headers: const {
            'User-Agent': 'transport-app/1.0 (location-search)',
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) return const [];
        final data = jsonDecode(response.body) as List<dynamic>;
        return data
            .map((item) => item as Map<String, dynamic>)
            .map((item) {
              final lat = double.tryParse((item['lat'] ?? '').toString());
              final lng = double.tryParse((item['lon'] ?? '').toString());
              return <String, dynamic>{
                'description': (item['display_name'] ?? '').toString(),
                'placeId': (item['place_id'] ?? '').toString(),
                'lat': lat,
                'lng': lng,
              };
            })
            .where((item) =>
                (item['description'] as String).isNotEmpty &&
                item['lat'] != null &&
                item['lng'] != null)
            .toList();
      } catch (_) {
        return const [];
      }
    }
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/autocomplete/json'
      '?input=${Uri.encodeQueryComponent(cleaned)}'
      '&key=$key',
    );
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return const [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final status = data['status'] as String?;
      if (status == 'OK') {
        final predictions = data['predictions'] as List<dynamic>? ?? const [];
        final placesResults = predictions
            .map((item) => item as Map<String, dynamic>)
            .map((item) => <String, dynamic>{
                  'description': (item['description'] ?? '').toString(),
                  'placeId': (item['place_id'] ?? '').toString(),
                })
            .where((item) =>
                (item['description'] as String).isNotEmpty &&
                (item['placeId'] as String).isNotEmpty)
            .toList();
        if (placesResults.isNotEmpty) return placesResults;
      }

      // Fallback: geocoding API suggestions so dropdown still appears
      // even when Places Autocomplete is unavailable/restricted.
      final geocodeUrl = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?address=${Uri.encodeQueryComponent(cleaned)}'
        '&key=$key',
      );
      final geoResponse = await http.get(geocodeUrl).timeout(
            const Duration(seconds: 8),
          );
      if (geoResponse.statusCode != 200) return const [];
      final geoData = jsonDecode(geoResponse.body) as Map<String, dynamic>;
      final geoStatus = geoData['status'] as String?;
      if (geoStatus != 'OK') return const [];
      final results = geoData['results'] as List<dynamic>? ?? const [];
      return results
          .map((item) => item as Map<String, dynamic>)
          .map((item) {
            final geometry = item['geometry'] as Map<String, dynamic>?;
            final location = geometry?['location'] as Map<String, dynamic>?;
            final lat = (location?['lat'] as num?)?.toDouble();
            final lng = (location?['lng'] as num?)?.toDouble();
            return <String, dynamic>{
              'description': (item['formatted_address'] ?? '').toString(),
              'placeId': (item['place_id'] ?? '').toString(),
              'lat': lat,
              'lng': lng,
            };
          })
          .where((item) =>
              (item['description'] as String).isNotEmpty &&
              item['lat'] != null &&
              item['lng'] != null)
          .take(8)
          .toList();
    } catch (_) {
      // Fallback to Nominatim if Google requests fail/restricted.
      final nominatimUrl = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeQueryComponent(cleaned)}'
        '&format=json'
        '&addressdetails=1'
        '&limit=8',
      );
      try {
        final response = await http.get(
          nominatimUrl,
          headers: const {
            'User-Agent': 'transport-app/1.0 (location-search)',
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) return const [];
        final data = jsonDecode(response.body) as List<dynamic>;
        return data
            .map((item) => item as Map<String, dynamic>)
            .map((item) {
              final lat = double.tryParse((item['lat'] ?? '').toString());
              final lng = double.tryParse((item['lon'] ?? '').toString());
              return <String, dynamic>{
                'description': (item['display_name'] ?? '').toString(),
                'placeId': (item['place_id'] ?? '').toString(),
                'lat': lat,
                'lng': lng,
              };
            })
            .where((item) =>
                (item['description'] as String).isNotEmpty &&
                item['lat'] != null &&
                item['lng'] != null)
            .toList();
      } catch (_) {
        return const [];
      }
    }
  }

  Future<LatLng?> _resolvePlaceIdToLatLng(String placeId) async {
    final key = googleMapsApiKey;
    if (placeId.trim().isEmpty || key.isEmpty) return null;
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/details/json'
      '?place_id=${Uri.encodeQueryComponent(placeId)}'
      '&fields=geometry'
      '&key=$key',
    );
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if ((data['status'] as String?) != 'OK') return null;
      final result = data['result'] as Map<String, dynamic>?;
      final geometry = result?['geometry'] as Map<String, dynamic>?;
      final location = geometry?['location'] as Map<String, dynamic>?;
      final lat = (location?['lat'] as num?)?.toDouble();
      final lng = (location?['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      return LatLng(lat, lng);
    } catch (_) {
      return null;
    }
  }

  Future<void> _openParentLocationPickerModal() async {
    var tempSelectedLocation =
        _selectedParentLocation ?? const LatLng(24.8607, 67.0011);
    var loadingCurrent = false;
    var searchingLocation = false;
    var loadingSuggestions = false;
    List<Map<String, dynamic>> suggestions = [];
    Timer? searchDebounce;
    _locationSearchController.clear();

    final picked = await showModalBottomSheet<LatLng>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            // Auto-load current location when modal opens
            Future<void> loadCurrentLocationOnOpen() async {
              try {
                final position = await _getCurrentParentPosition();
                if (position != null && setModalState != null) {
                  final currentLocation = LatLng(position.latitude, position.longitude);
                  setModalState(() => tempSelectedLocation = currentLocation);
                  _pendingChildMapCameraTarget = currentLocation;
                  await _focusChildLocationOnMap(currentLocation, zoom: 16);
                }
              } catch (e) {
                print("Error loading current location: $e");
              }
            }
            
            // Call on first build
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (mounted) {
                await loadCurrentLocationOnOpen();
              }
            });
            
            Future<void> useCurrentInModal() async {
              setModalState(() => loadingCurrent = true);
              try {
                final position = await _getCurrentParentPosition();
                if (position == null) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Unable to fetch current location.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                final point = LatLng(position.latitude, position.longitude);
                setModalState(() => tempSelectedLocation = point);
                await _focusChildLocationOnMap(point, zoom: 16);
              } finally {
                if (mounted) {
                  setModalState(() => loadingCurrent = false);
                }
              }
            }

            Future<void> searchAddressInModal() async {
              final query = _locationSearchController.text.trim();
              if (query.isEmpty) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Enter an address or place name to search.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              setModalState(() => searchingLocation = true);
              try {
                LatLng? point = await _resolveAddressToLatLng(query);
                if (point == null) {
                  final candidates = await _fetchLocationSuggestions(query);
                  if (candidates.isNotEmpty) {
                    final first = candidates.first;
                    final lat = (first['lat'] as num?)?.toDouble();
                    final lng = (first['lng'] as num?)?.toDouble();
                    final placeId = (first['placeId'] ?? '').toString();
                    point =
                        (lat != null && lng != null) ? LatLng(lat, lng) : null;
                    point ??= await _resolvePlaceIdToLatLng(placeId);
                    point ??=
                        await _resolveAddressToLatLng((first['description'] ?? '').toString());
                  }
                }
                if (point == null) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Location not found. Try a more specific address.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                final resolvedPoint = point;
                setModalState(() => tempSelectedLocation = resolvedPoint);
                await _focusChildLocationOnMap(resolvedPoint, zoom: 16);
                if (mounted) {
                  setModalState(() => suggestions = []);
                }
              } finally {
                if (mounted) {
                  setModalState(() => searchingLocation = false);
                }
              }
            }

            Future<void> updateSuggestions(String query) async {
              final cleaned = query.trim();
              if (cleaned.length < 2) {
                if (mounted) {
                  setModalState(() {
                    loadingSuggestions = false;
                    suggestions = [];
                  });
                }
                return;
              }
              setModalState(() => loadingSuggestions = true);
              final results = await _fetchLocationSuggestions(cleaned);
              if (!mounted) return;
              if (_locationSearchController.text.trim() != cleaned) return;
              setModalState(() {
                loadingSuggestions = false;
                suggestions = results;
              });
            }

            Future<void> selectSuggestion(Map<String, dynamic> item) async {
              final description = (item['description'] ?? '').toString();
              final placeId = (item['placeId'] ?? '').toString();
              final lat = (item['lat'] as num?)?.toDouble();
              final lng = (item['lng'] as num?)?.toDouble();
              _locationSearchController.text = description;
              setModalState(() {
                searchingLocation = true;
                suggestions = [];
              });
              try {
                LatLng? point =
                    (lat != null && lng != null) ? LatLng(lat, lng) : null;
                point ??= await _resolvePlaceIdToLatLng(placeId);
                point ??= await _resolveAddressToLatLng(description);
                if (point == null) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Unable to open selected location.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                setModalState(() => tempSelectedLocation = point!);
                await _focusChildLocationOnMap(point, zoom: 16);
              } finally {
                if (mounted) {
                  setModalState(() => searchingLocation = false);
                }
              }
            }

            return SizedBox(
              height: MediaQuery.of(modalContext).size.height * 0.8,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Select parent location',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(modalContext).pop(),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () =>
                              Navigator.of(modalContext).pop(tempSelectedLocation),
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _locationSearchController,
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => searchAddressInModal(),
                            onChanged: (value) {
                              searchDebounce?.cancel();
                              searchDebounce = Timer(
                                const Duration(milliseconds: 350),
                                () => updateSuggestions(value),
                              );
                            },
                            decoration: const InputDecoration(
                              labelText: 'Search location',
                              hintText: 'e.g. Mirpur Abbottabad',
                              prefixIcon: Icon(Icons.search_rounded),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton(
                          onPressed: searchingLocation ? null : searchAddressInModal,
                          child: searchingLocation
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Search'),
                        ),
                      ],
                    ),
                  ),
                  if (loadingSuggestions)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  if (suggestions.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      constraints: const BoxConstraints(maxHeight: 180),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: suggestions.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = suggestions[index];
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.place_rounded, size: 18),
                            title: Text(
                              item['description'] ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => selectSuggestion(item),
                          );
                        },
                      ),
                    ),
                  Expanded(
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: tempSelectedLocation,
                        zoom: 15,
                      ),
                      onMapCreated: (controller) {
                        _childLocationMapController = controller;
                        final target =
                            _pendingChildMapCameraTarget ?? tempSelectedLocation;
                        _pendingChildMapCameraTarget = null;
                        _focusChildLocationOnMap(target, zoom: 16);
                      },
                      onTap: (position) {
                        setModalState(() => tempSelectedLocation = position);
                      },
                      markers: {
                        Marker(
                          markerId: const MarkerId('selected_parent_location'),
                          position: tempSelectedLocation,
                          infoWindow: const InfoWindow(
                            title: 'Selected parent location',
                          ),
                        ),
                      },
                      myLocationButtonEnabled: false,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                    child: Row(
                      children: [
                        const Spacer(),
                        OutlinedButton.icon(
                          onPressed: loadingCurrent ? null : useCurrentInModal,
                          icon: loadingCurrent
                              ? const SizedBox(
                                  height: 14,
                                  width: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.my_location_rounded, size: 16),
                          label: const Text('Use current'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    searchDebounce?.cancel();
    _childLocationMapController = null;
    _pendingChildMapCameraTarget = null;
    _locationSearchController.clear();

    if (picked != null && mounted) {
      setState(() {
        _selectedParentLocation = picked;
      });
    }
  }

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
              onPressed: _savingPersonalInfo
                  ? null
                  : () async {
                      setState(() => _savingPersonalInfo = true);
                      try {
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
                      } finally {
                        if (mounted) {
                          setState(() => _savingPersonalInfo = false);
                        }
                      }
                    },
              icon: const Icon(Icons.save_rounded, size: 20),
              label: Text(_savingPersonalInfo ? 'Saving…' : 'Save'),
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
                    'You\'ll see "Child Picked Up" and "Child Dropped Off" alerts here when the driver starts or ends your child\'s ride.',
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
            final String titleText = isDeviation
                ? 'Route deviation'
                : (isStarted ? 'Child Picked Up' : 'Child Dropped Off');
            final Color avatarColor = isDeviation ? AppTheme.warning : (isStarted ? AppTheme.success : AppTheme.primary);
            final IconData avatarIcon = isDeviation ? Icons.warning_rounded : (isStarted ? Icons.directions_car_rounded : Icons.check_circle_rounded);
            final Color cardHighlight = read ? Colors.transparent : (isDeviation ? AppTheme.warning.withOpacity(0.08) : (isStarted ? AppTheme.success.withOpacity(0.08) : AppTheme.primary.withOpacity(0.08)));

            return _premiumCard(
              margin: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context)),
              baseColor: cardHighlight == Colors.transparent ? Colors.white : cardHighlight,
              padding: EdgeInsets.symmetric(horizontal: AppTheme.horizontalPadding(context), vertical: 8),
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
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    final year = d.year.toString();
    final hour = d.hour.toString().padLeft(2, '0');
    final minute = d.minute.toString().padLeft(2, '0');
    // Show full date and time for each notification.
    return '$day/$month/$year  $hour:$minute';
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
            _premiumCard(
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
            SizedBox(height: AppTheme.verticalSpacing(context) * 2),
            Text('Your children', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
            SizedBox(height: AppTheme.verticalSpacing(context)),
            if (children.isEmpty)
              _premiumCard(
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
              )
            else
              ...children.asMap().entries.map((e) {
                final i = e.key + 1;
                final child = e.value;
                return _premiumCard(
                  margin: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context)),
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
      final validationError = _validateChildForm(parentChildren);
      if (validationError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(validationError),
            behavior: SnackBarBehavior.floating,
          ),
        );
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
          'parentLatitude': _selectedParentLocation!.latitude,
          'parentLongitude': _selectedParentLocation!.longitude,
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
          'parentLatitude': _selectedParentLocation!.latitude,
          'parentLongitude': _selectedParentLocation!.longitude,
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
        _selectedParentLocation = null;
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
            TextField(
              controller: _childSchoolOnController,
              readOnly: true,
              onTap: () => _pickTimeForController(_childSchoolOnController),
              decoration: InputDecoration(
                labelText: 'School on time',
                hintText: 'Select time',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.access_time_rounded),
                  onPressed: () => _pickTimeForController(_childSchoolOnController),
                ),
              ),
              textInputAction: TextInputAction.next,
            ),
            SizedBox(height: AppTheme.verticalSpacing(context)),
            TextField(
              controller: _childSchoolOffController,
              readOnly: true,
              onTap: () => _pickTimeForController(_childSchoolOffController),
              decoration: InputDecoration(
                labelText: 'School off time',
                hintText: 'Select time',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.access_time_rounded),
                  onPressed: () => _pickTimeForController(_childSchoolOffController),
                ),
              ),
              textInputAction: TextInputAction.done,
            ),
            SizedBox(height: AppTheme.verticalSpacing(context)),
            Text(
              'Parent location',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openParentLocationPickerModal,
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: Text(
                      _selectedParentLocation == null
                          ? 'Open map picker'
                          : 'Update on map',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loadingParentLocation
                        ? null
                        : () async {
                            setState(() => _loadingParentLocation = true);
                            try {
                              final pos = await _getCurrentParentPosition();
                              if (pos != null && mounted) {
                                setState(() {
                                  _selectedParentLocation =
                                      LatLng(pos.latitude, pos.longitude);
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Current location selected'),
                                    backgroundColor: AppTheme.success,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              } else if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Unable to fetch current location.'),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            } finally {
                              if (mounted) {
                                setState(() => _loadingParentLocation = false);
                              }
                            }
                          },
                    icon: _loadingParentLocation
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location_rounded, size: 18),
                    label: const Text('Use current'),
                  ),
                ),
              ],
            ),
            if (_selectedParentLocation != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Location added successfully',
                        style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
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
              return _premiumCard(
                margin: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context)),
                padding: EdgeInsets.zero,
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
                            final lat = (child['parentLatitude'] as num?)?.toDouble();
                            final lng = (child['parentLongitude'] as num?)?.toDouble();
                            _selectedParentLocation =
                                (lat != null && lng != null) ? LatLng(lat, lng) : null;
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
        final isRequesting = _requestingForChildId == childId;

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

                      return _premiumCard(
                        margin: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context) * 2),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Center(
                                child: Padding(
                                  padding: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context) * 2),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        // Child Avatar
                                        GestureDetector(
                                          onTap: () {
                                            final url = child['photo']?.toString() ?? '';
                                            if (url.isNotEmpty) {
                                              _viewImage('Child: ${child['name']}', NetworkImage(url));
                                            }
                                          },
                                          child: _circularAvatar(
                                            imageUrl: child['photo']?.toString() ?? '',
                                            label: 'Child',
                                            radius: 45,
                                          ),
                                        ),
                                        const SizedBox(width: 20),
                                        // Connection Icon
                                        Icon(Icons.swap_horiz_rounded, color: AppTheme.primary.withOpacity(0.3), size: 28),
                                        const SizedBox(width: 20),
                                        // Driver Avatar
                                        GestureDetector(
                                          onTap: () {
                                            final url = driverData['profilePic']?.toString() ?? '';
                                            if (url.isNotEmpty) {
                                              _viewImage('Driver: ${driverData['name']}', NetworkImage(url));
                                            }
                                          },
                                          child: _circularAvatar(
                                            imageUrl: driverData['profilePic']?.toString() ?? '',
                                            label: 'Driver',
                                            radius: 45,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              _driverInfoRow(Icons.person_rounded, 'Driver', driverData['name']?.toString() ?? '—'),
                              _driverInfoRow(Icons.phone_rounded, 'Phone Number', driverData['phone']?.toString() ?? '—'),
                              _driverInfoRow(Icons.directions_car_rounded, 'Vehicle Name', driverData['vehicleName']?.toString() ?? '—'),
                              _driverInfoRow(Icons.numbers_rounded, 'Vehicle Number', driverData['vehicleNumber']?.toString() ?? '—'),
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
                              Row(
                                children: [
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => DriverLocationScreen(childId: childId))),
                                      icon: const Icon(Icons.location_on_rounded, size: 20),
                                      label: const Text('Track driver'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () async {
                                        final phone = driverData['phone']?.toString() ?? '';
                                        if (phone.isNotEmpty) {
                                          final telUri = Uri(scheme: 'tel', path: phone);
                                          if (await canLaunchUrl(telUri)) {
                                            await launchUrl(telUri);
                                          }
                                        }
                                      },
                                      icon: const Icon(Icons.phone_rounded, size: 20),
                                      label: const Text('Call driver'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                      );
                    },
                  );
                }

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _firestore.collection('users').where('role', isEqualTo: 'driver').snapshots(),
                  builder: (context, driversSnap) {
                    if (!driversSnap.hasData) return const Center(child: CircularProgressIndicator());
                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _firestore
                          .collection('requests')
                          .where('status', isEqualTo: 'approved')
                          .snapshots(),
                      builder: (context, approvedRequestsSnap) {
                        if (!approvedRequestsSnap.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        final approvedRequests = approvedRequestsSnap.data!.docs;
                        final Map<String, int> occupiedSeatsByDriver = {};
                        for (final req in approvedRequests) {
                          final reqData = req.data();
                          final driverId = (reqData['driverId'] ?? '').toString();
                          if (driverId.isEmpty) continue;
                          final childIds = (reqData['childIds'] as List?) ?? const [];
                          occupiedSeatsByDriver[driverId] =
                              (occupiedSeatsByDriver[driverId] ?? 0) + childIds.length;
                        }

                        final drivers = driversSnap.data!.docs.where((doc) {
                          final d = doc.data();
                          if (d['school'] != childSchool || d['route'] != childRoute) {
                            return false;
                          }
                          final seats = int.tryParse((d['seats'] ?? '').toString()) ?? 0;
                          final occupied = occupiedSeatsByDriver[doc.id] ?? 0;
                          return seats <= 0 || occupied < seats;
                        }).toList();

                        if (drivers.isEmpty) {
                          return _premiumCard(
                            margin: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context) * 2),
                            child: Text('No drivers available for this route yet.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary)),
                          );
                        }

                        return Column(
                          children: drivers.map((doc) {
                        final d = doc.data();
                        return _premiumCard(
                          margin: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context)),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if ((d['profilePic'] ?? '').toString().isNotEmpty)
                                  Center(
                                    child: Container(
                                      margin: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context) * 1.5),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppTheme.primary.withOpacity(0.1),
                                            blurRadius: 12,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(16),
                                        child: Image.network(
                                          d['profilePic'].toString(),
                                          height: 100,
                                          width: 100,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => Container(
                                            height: 100,
                                            width: 100,
                                            color: AppTheme.primary.withOpacity(0.1),
                                            child: Icon(Icons.person_rounded, size: 50, color: AppTheme.primary.withOpacity(0.5)),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                _driverInfoRow(Icons.person_rounded, 'Name', d['name']?.toString() ?? '—'),
                                _driverInfoRow(Icons.badge_rounded, 'CNIC', d['cnic']?.toString() ?? '—'),
                                _driverInfoRow(Icons.directions_car_rounded, 'Vehicle', '${d['vehicleName'] ?? '—'} (${d['vehicleNumber'] ?? '—'})'),
                                _driverInfoRow(Icons.route_rounded, 'Route', d['route']?.toString() ?? '—'),
                                SizedBox(height: AppTheme.verticalSpacing(context)),
                                FilledButton(
                                  onPressed: isRequesting
                                      ? null
                                      : () async {
                                          setState(() => _requestingForChildId = childId);
                                          try {
                                            // Create a single request document instead of one per admin.
                                            final adminSnapshot = await _firestore
                                                .collection('users')
                                                .where('role', isEqualTo: 'admin')
                                                .limit(1)
                                                .get();
                                            String? adminId;
                                            if (adminSnapshot.docs.isNotEmpty) {
                                              adminId = adminSnapshot.docs.first.id;
                                            }
                                            final requestData = <String, dynamic>{
                                              'parentId': _currentUser.uid,
                                              'driverId': doc.id,
                                              'childIds': [childId],
                                              'status': 'pending',
                                              'timestamp': FieldValue.serverTimestamp(),
                                            };
                                            if (adminId != null) {
                                              requestData['adminId'] = adminId;
                                            }
                                            await _firestore.collection('requests').add(requestData);
                                            if (mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('Request sent to admin'),
                                                  backgroundColor: AppTheme.success,
                                                  behavior: SnackBarBehavior.floating,
                                                ),
                                              );
                                            }
                                          } finally {
                                            if (mounted) {
                                              setState(() => _requestingForChildId = null);
                                            }
                                          }
                                        },
                                  child: isRequesting
                                      ? const SizedBox(
                                          height: 18,
                                          width: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Text('Request driver'),
                                ),
                              ],
                            ),
                        );
                          }).toList(),
                        );
                      },
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

  Widget _circularAvatar({required String imageUrl, required String label, double radius = 40}) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.primary.withOpacity(0.5),
                AppTheme.accent.withOpacity(0.5),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withOpacity(0.15),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: CircleAvatar(
              radius: radius,
              backgroundColor: AppTheme.subtleSurface,
              backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
              child: imageUrl.isEmpty
                  ? Icon(Icons.person_rounded, size: radius, color: AppTheme.primary.withOpacity(0.5))
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      ],
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
          backgroundColor: AppTheme.surface,
          appBar: AppBar(
            title: Text(_navItems[_selectedIndex].label),
            actions: [
              if (_selectedIndex == 2)
                IconButton(
                  icon: const Icon(Icons.notifications_active_outlined),
                  onPressed: () {
                    setState(() => _selectedIndex = 1);
                  },
                ),
            ],
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
                          return _drawerNavTile(
                            icon: e.value.icon,
                            label: e.value.label,
                            selected: selected,
                            onTap: () {
                              setState(() => _selectedIndex = e.key);
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
              SafeArea(child: pages[_selectedIndex]),
            ],
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
