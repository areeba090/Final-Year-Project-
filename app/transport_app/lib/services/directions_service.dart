import 'dart:convert';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_polyline_algorithm/google_polyline_algorithm.dart';
import 'package:http/http.dart' as http;
import '../config/maps_config.dart';

/// Fetches the road-following route between origin and destination using Google Directions API.
/// Returns a list of LatLng points along the path, or null if the API key is missing or the request fails.
Future<List<LatLng>?> getRoadRoutePoints({
  required double originLat,
  required double originLng,
  required double destLat,
  required double destLng,
}) async {
  final key = googleMapsApiKey;
  if (key.isEmpty) return null;

  final origin = '$originLat,$originLng';
  final destination = '$destLat,$destLng';
  final url = Uri.parse(
    'https://maps.googleapis.com/maps/api/directions/json'
    '?origin=$origin'
    '&destination=$destination'
    '&mode=driving'
    '&key=$key',
  );

  try {
    final response = await http.get(url).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final status = data['status'] as String?;
    if (status != 'OK') return null;

    final routes = data['routes'] as List<dynamic>?;
    if (routes == null || routes.isEmpty) return null;

    final route = routes.first as Map<String, dynamic>;
    final overviewPolyline = route['overview_polyline'] as Map<String, dynamic>?;
    final encoded = overviewPolyline?['points'] as String?;
    if (encoded == null || encoded.isEmpty) return null;

    final decoded = decodePolyline(encoded);
    if (decoded.isEmpty) return null;

    // decodePolyline returns List<List<num>> with [lat, lng] per point
    return decoded
        .map((p) => LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()))
        .toList();
  } catch (_) {
    return null;
  }
}
