import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../theme/app_theme.dart';
import '../services/directions_service.dart';

class DriverParentLocationScreen extends StatefulWidget {
  final String childName;
  final double parentLatitude;
  final double parentLongitude;

  const DriverParentLocationScreen({
    super.key,
    required this.childName,
    required this.parentLatitude,
    required this.parentLongitude,
  });

  @override
  State<DriverParentLocationScreen> createState() =>
      _DriverParentLocationScreenState();
}

class _DriverParentLocationScreenState extends State<DriverParentLocationScreen> {
  GoogleMapController? _mapController;
  LatLng? _driverPosition;
  Timer? _refreshTimer;
  List<LatLng>? _routePoints;

  LatLng get _parentPosition =>
      LatLng(widget.parentLatitude, widget.parentLongitude);

  @override
  void initState() {
    super.initState();
    _refreshDriverPosition();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _refreshDriverPosition();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _refreshDriverPosition() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
    }

    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    if (!mounted) return;
    setState(() {
      _driverPosition = LatLng(pos.latitude, pos.longitude);
    });
    _loadRoadRoute();
    _fitBounds();
  }

  Future<void> _loadRoadRoute() async {
    final driverPosition = _driverPosition;
    if (driverPosition == null) return;
    final points = await getRoadRoutePoints(
      originLat: driverPosition.latitude,
      originLng: driverPosition.longitude,
      destLat: _parentPosition.latitude,
      destLng: _parentPosition.longitude,
    );
    if (!mounted) return;
    setState(() {
      _routePoints = points;
    });
    _fitBounds();
  }

  void _fitBounds() {
    if (_mapController == null || _driverPosition == null) return;
    final points = <LatLng>[
      _driverPosition!,
      _parentPosition,
      ...?_routePoints,
    ];
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;
    for (final point in points.skip(1)) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        80,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('parent'),
        position: _parentPosition,
        infoWindow: InfoWindow(title: '${widget.childName} parent'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
      if (_driverPosition != null)
        Marker(
          markerId: const MarkerId('driver'),
          position: _driverPosition!,
          infoWindow: const InfoWindow(title: 'Your live location'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
    };

    final polylines = <Polyline>{
      if (_driverPosition != null)
        Polyline(
          polylineId: const PolylineId('driver_to_parent'),
          points: (_routePoints != null && _routePoints!.length >= 2)
              ? _routePoints!
              : [_driverPosition!, _parentPosition],
          color: AppTheme.primary,
          width: 5,
        ),
    };

    final initialCenter = _driverPosition ?? _parentPosition;

    return Scaffold(
      appBar: AppBar(title: const Text('Parent & Driver Live Map')),
      body: Stack(
        children: [
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: initialCenter, zoom: 14),
              markers: markers,
              polylines: polylines,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              onMapCreated: (controller) {
                _mapController = controller;
                _fitBounds();
              },
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Text(
                'Driver location refreshes every 10 seconds.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
