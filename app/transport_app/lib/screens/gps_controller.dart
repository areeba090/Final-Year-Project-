import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

class GPSController {
  static StreamSubscription<Position>? _positionStream;
  static final _firestore = FirebaseFirestore.instance;

  /// Start GPS tracking for a given driverId
  static Future<void> startTracking(String driverId) async {
    // Check location permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        print("Location permission denied");
        return;
      }
    }

    // If already tracking, return
    if (_positionStream != null) return;

    // Start listening to location updates
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((Position position) async {
      await _updateLocation(driverId, position);
    }, onError: (e) {
      print("GPS stream error: $e");
      // Retry after 5 seconds if GPS fails
      Future.delayed(const Duration(seconds: 5), () async {
        final pos = await _getLastKnownPosition();
        if (pos != null) await _updateLocation(driverId, pos);
      });
    });
  }

  /// Stop GPS tracking
  static Future<void> stopTracking() async {
    if (_positionStream != null) {
      await _positionStream!.cancel();
      _positionStream = null;
    }
  }

  /// Safe Firestore update with retry
  static Future<void> _updateLocation(String driverId, Position position) async {
    try {
      await _firestore.collection('driverLocations').doc(driverId).set({
        'latitude': position.latitude,
        'longitude': position.longitude,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'onRide',
      }, SetOptions(merge: true));
    } catch (e) {
      print("Failed to update location, retrying... $e");
      // Retry after 3 seconds
      Future.delayed(const Duration(seconds: 3), () => _updateLocation(driverId, position));
    }
  }

  /// Get last known position in case GPS stream fails
  static Future<Position?> _getLastKnownPosition() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (e) {
      print("Failed to get last known position: $e");
      return null;
    }
  }
}