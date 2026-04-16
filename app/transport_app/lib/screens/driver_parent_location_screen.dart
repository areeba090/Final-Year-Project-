import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../theme/app_theme.dart';

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
    _fitBounds();
  }

  void _fitBounds() {
    if (_mapController == null || _driverPosition == null) return;
    final sw = LatLng(
      _driverPosition!.latitude < _parentPosition.latitude
          ? _driverPosition!.latitude
          : _parentPosition.latitude,
      _driverPosition!.longitude < _parentPosition.longitude
          ? _driverPosition!.longitude
          : _parentPosition.longitude,
    );
    final ne = LatLng(
      _driverPosition!.latitude > _parentPosition.latitude
          ? _driverPosition!.latitude
          : _parentPosition.latitude,
      _driverPosition!.longitude > _parentPosition.longitude
          ? _driverPosition!.longitude
          : _parentPosition.longitude,
    );
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(southwest: sw, northeast: ne),
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
          points: [_driverPosition!, _parentPosition],
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
