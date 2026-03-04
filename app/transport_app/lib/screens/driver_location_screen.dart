import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class DriverLocationScreen extends StatefulWidget {
  final String childId;
  const DriverLocationScreen({Key? key, required this.childId}) : super(key: key);

  @override
  State<DriverLocationScreen> createState() => _DriverLocationScreenState();
}

class _DriverLocationScreenState extends State<DriverLocationScreen> {
  GoogleMapController? _mapController;
  Marker? _driverMarker;
  LatLng? _driverPosition;

  @override
  Widget build(BuildContext context) {
    final firestore = FirebaseFirestore.instance;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: firestore
          .collection('requests')
          .where('childIds', arrayContains: widget.childId)
          .where('status', isEqualTo: 'approved')
          .snapshots(),
      builder: (context, requestSnap) {
        if (!requestSnap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));

        final requests = requestSnap.data!.docs;
        if (requests.isEmpty) return const Scaffold(body: Center(child: Text("No driver assigned yet")));

        final driverId = requests.first.data()['driverId'] as String?;
        if (driverId == null) return const Scaffold(body: Center(child: Text("Driver ID not found")));

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: firestore.collection('users').doc(driverId).snapshots(),
          builder: (context, driverSnap) {
            if (!driverSnap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));

            final driverData = driverSnap.data?.data();
            if (driverData == null) return const Scaffold(body: Center(child: Text("Driver data not found")));

            // Get Firestore driver location
            final lat = (driverData['location']?['lat'] ?? 0.0).toDouble();
            final lng = (driverData['location']?['lng'] ?? 0.0).toDouble();

            // Update marker only if coordinates exist
            if (lat != 0.0 && lng != 0.0) {
              _driverPosition = LatLng(lat, lng);
              _driverMarker = Marker(
                markerId: const MarkerId("driver"),
                position: _driverPosition!,
                infoWindow: InfoWindow(
                  title: driverData['name'] ?? 'Driver',
                  snippet: "${driverData['vehicleName'] ?? ''} (${driverData['vehicleNumber'] ?? ''})",
                ),
              );

              // Animate camera only once or when position changes
              if (_mapController != null) {
                _mapController!.animateCamera(
                  CameraUpdate.newLatLng(_driverPosition!),
                );
              }
            }

            return Scaffold(
              appBar: AppBar(title: Text("Tracking ${driverData['name'] ?? 'Driver'}")),
              body: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: _driverPosition ?? const LatLng(34.168, 73.221), // fallback to a city center
                  zoom: 16,
                ),
                markers: _driverMarker != null ? {_driverMarker!} : {},
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
                onMapCreated: (controller) {
                  _mapController = controller;
                  // Move camera if driver already has location
                  if (_driverPosition != null) {
                    _mapController!.moveCamera(CameraUpdate.newLatLng(_driverPosition!));
                  }
                },
              ),
            );
          },
        );
      },
    );
  }
}