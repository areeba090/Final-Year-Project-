import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class DriverRideMapScreen extends StatefulWidget {
  final String childName;
  final String rideModeLabel;
  final String pickupLabel;
  final String destinationLabel;
  final LatLng pickupLocation;
  final LatLng destinationLocation;
  final bool liveTrackingMode;

  const DriverRideMapScreen({
    super.key,
    required this.childName,
    required this.rideModeLabel,
    required this.pickupLabel,
    required this.destinationLabel,
    required this.pickupLocation,
    required this.destinationLocation,
    required this.liveTrackingMode,
  });

  @override
  State<DriverRideMapScreen> createState() => _DriverRideMapScreenState();
}

class _DriverRideMapScreenState extends State<DriverRideMapScreen> {
  GoogleMapController? _mapController;
  StreamSubscription<Position>? _positionSub;
  LatLng? _driverPosition;

  @override
  void initState() {
    super.initState();
    _startDriverPositionUpdates();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _startDriverPositionUpdates() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
    }

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((position) {
      if (!mounted) return;
      setState(() {
        _driverPosition = LatLng(position.latitude, position.longitude);
      });
      _fitMapBounds();
    });
  }

  void _fitMapBounds() {
    if (_mapController == null) return;
    final points = <LatLng>[
      widget.pickupLocation,
      widget.destinationLocation,
      if (_driverPosition != null) _driverPosition!,
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
        90,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('pickup'),
        position: widget.pickupLocation,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(title: 'Pickup: ${widget.pickupLabel}'),
      ),
      Marker(
        markerId: const MarkerId('destination'),
        position: widget.destinationLocation,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(title: 'Destination: ${widget.destinationLabel}'),
      ),
      if (_driverPosition != null)
        Marker(
          markerId: const MarkerId('driver'),
          position: _driverPosition!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'Driver live location'),
        ),
    };

    final polylines = <Polyline>{
      Polyline(
        polylineId: const PolylineId('route'),
        points: [widget.pickupLocation, widget.destinationLocation],
        color: Colors.blue,
        width: 5,
      ),
    };

    final initialCenter = LatLng(
      (widget.pickupLocation.latitude + widget.destinationLocation.latitude) / 2,
      (widget.pickupLocation.longitude + widget.destinationLocation.longitude) / 2,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.rideModeLabel} • ${widget.childName}'),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: initialCenter, zoom: 13),
              markers: markers,
              polylines: polylines,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              onMapCreated: (controller) {
                _mapController = controller;
                _fitMapBounds();
              },
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 20,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  widget.liveTrackingMode
                      ? 'Live tracking mode is ON. Destination stays visible while your location updates.'
                      : 'Pickup and destination are ready. Move within 100m of pickup to enable Start Ride.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
