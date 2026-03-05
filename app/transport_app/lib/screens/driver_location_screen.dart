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
        if (!requestSnap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final requests = requestSnap.data!.docs;
        if (requests.isEmpty) {
          return const Scaffold(
            body: Center(child: Text("No driver assigned yet")),
          );
        }

        final driverId = requests.first.data()['driverId'] as String?;
        if (driverId == null || driverId.isEmpty) {
          return const Scaffold(
            body: Center(child: Text("Driver ID not found")),
          );
        }

        // Listen to live GPS updates written by GPSController
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: firestore.collection('driverLocations').doc(driverId).snapshots(),
          builder: (context, locationSnap) {
            if (!locationSnap.hasData || !locationSnap.data!.exists) {
              return const Scaffold(
                body: Center(child: Text("Waiting for driver location...")),
              );
            }

            final locData = locationSnap.data!.data();
            if (locData == null) {
              return const Scaffold(
                body: Center(child: Text("No location data available")),
              );
            }

            final lat = (locData['latitude'] ?? 0.0).toDouble();
            final lng = (locData['longitude'] ?? 0.0).toDouble();

            // Update marker only if coordinates exist
            if (lat != 0.0 && lng != 0.0) {
              _driverPosition = LatLng(lat, lng);
              _driverMarker = const Marker(
                markerId: MarkerId("driver"),
              ).copyWith(
                positionParam: _driverPosition,
              );

              // Animate camera when we have a controller
              if (_mapController != null && _driverPosition != null) {
                _mapController!.animateCamera(
                  CameraUpdate.newLatLng(_driverPosition!),
                );
              }
            }

            return Scaffold(
              appBar: AppBar(title: const Text("Driver Live Location")),
              body: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: _driverPosition ?? const LatLng(34.168, 73.221),
                  zoom: 16,
                ),
                markers: _driverMarker != null ? {_driverMarker!} : {},
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
                onMapCreated: (controller) {
                  _mapController = controller;
                  if (_driverPosition != null) {
                    _mapController!.moveCamera(
                      CameraUpdate.newLatLng(_driverPosition!),
                    );
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