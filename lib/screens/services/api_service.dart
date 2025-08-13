import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ApiService with ChangeNotifier {
final String baseUrl = 'https://trainer-backend-soj9.onrender.com';
final String googleMapsApiKey = 'AIzaSyDSdQdpZQxS1cI_6nbz32U9zgpdj8oddes';

Future<List<dynamic>> getUsers(String token) async {
final response = await http.get(
Uri.parse('$baseUrl/users'),
headers: {'Authorization': 'Bearer $token'},
);
if (response.statusCode == 200) {
notifyListeners();
return jsonDecode(response.body) as List<dynamic>;
}
throw Exception('Failed to load users: ${response.statusCode}');
}

Future<void> addUser(Map<String, dynamic> userData, String token) async {
  try {
    final response = await http.post(
      Uri.parse('$baseUrl/users'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(userData),
    );
    print('Add user response: ${response.statusCode}, ${response.body}'); // Debug log
    if (response.statusCode == 201) {
      notifyListeners();
      return;
    }
    String errorMessage = 'Unknown error';
    try {
      final body = jsonDecode(response.body);
      errorMessage = body['message']?.toString() ?? 'Error ${response.statusCode}';
    } catch (e) {
      errorMessage = response.body.isNotEmpty ? response.body : 'Error ${response.statusCode}';
    }
    throw Exception('Failed to add user: $errorMessage');
  } catch (e) {
    print('Error in addUser: $e'); // Debug log
    rethrow;
  }
}
Future<void> updateUser(String userId, Map<String, dynamic> userData, String token) async {
final response = await http.put(
Uri.parse('$baseUrl/users/$userId'),
headers: {
'Content-Type': 'application/json',
'Authorization': 'Bearer $token',
},
body: jsonEncode(userData),
);
if (response.statusCode != 200) {
throw Exception('Failed to update user: ${jsonDecode(response.body)['message'] ?? response.statusCode}');
}
notifyListeners();
}

Future<void> deleteUser(String userId, String token) async {
final response = await http.delete(
Uri.parse('$baseUrl/users/$userId'),
headers: {'Authorization': 'Bearer $token'},
);
if (response.statusCode != 200) {
throw Exception('Failed to delete user: ${response.statusCode}');
}
notifyListeners();
}
Future<void> sendProximityNotification(Map<String, dynamic> data, String token) async {
  try {
    final response = await http.post(
      Uri.parse('$baseUrl/api/notify-proximity'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(data),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to send proximity notification: ${response.body}');
    }
    print('Proximity notification request sent successfully');
  } catch (e) {
    print('Error sending proximity notification request: $e');
    rethrow;
  }
}
Future<void> assignDestination(String userId, Map<String, dynamic> destinationData, String token) async {
final response = await http.post(
Uri.parse('$baseUrl/destination'),
headers: {
'Content-Type': 'application/json',
'Authorization': 'Bearer $token',
},
body: jsonEncode({
'userId': userId,
...destinationData,
'date': DateTime.now().toIso8601String().split('T')[0], // e.g., 2025-08-01
}),
);
if (response.statusCode != 201) {
throw Exception('Failed to assign destination: ${jsonDecode(response.body)['message'] ?? response.statusCode}');
}
notifyListeners();
}

Future<void> deleteDestination(String userId, String token) async {
final response = await http.delete(
Uri.parse('$baseUrl/destination/$userId'),
headers: {'Authorization': 'Bearer $token'},
);
if (response.statusCode != 200) {
throw Exception('Failed to delete destination: ${jsonDecode(response.body)['message'] ?? response.statusCode}');
}
notifyListeners();
}



Future<Map<String, dynamic>> getRoute(LatLng origin, LatLng destination) async {
final url = 'https://maps.googleapis.com/maps/api/directions/json'
'?origin=${origin.latitude},${origin.longitude}'
'&destination=${destination.latitude},${destination.longitude}'
'&key=$googleMapsApiKey';

final response = await http.get(Uri.parse(url));
if (response.statusCode == 200) {
final data = json.decode(response.body);
if (data['status'] == 'OK') {
final polyline = data['routes'][0]['overview_polyline']['points'];
final duration = data['routes'][0]['legs'][0]['duration']['text'];
final distance = data['routes'][0]['legs'][0]['distance']['value'] / 1000.0; // km
notifyListeners();
return {
'points': _decodePolyline(polyline),
'duration': duration,
'distance': distance,
};
} else {
throw Exception('Directions API error: ${data['status']}');
}
} else {
throw Exception('Failed to fetch directions: ${response.statusCode}');
}
}

List<LatLng> _decodePolyline(String encoded) {
List<LatLng> points = [];
int index = 0, len = encoded.length;
int lat = 0, lng = 0;

while (index < len) {
int b, shift = 0, result = 0;
do {
b = encoded.codeUnitAt(index++) - 63;
result |= (b & 0x1f) << shift;
shift += 5;
} while (b >= 0x20);
int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
lat += dlat;

shift = 0;
result = 0;
do {
b = encoded.codeUnitAt(index++) - 63;
result |= (b & 0x1f) << shift;
shift += 5;
} while (b >= 0x20);
int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
lng += dlng;

points.add(LatLng(lat / 1E5, lng / 1E5));
}
return points;
}

Future<Map<String, dynamic>> getUserDestination(String userId, String token) async {
final response = await http.get(
Uri.parse('$baseUrl/destination/$userId'),
headers: {'Authorization': 'Bearer $token'},
);
if (response.statusCode == 200) {
notifyListeners();
return jsonDecode(response.body) as Map<String, dynamic>;
}
throw Exception('Failed to load destination: ${response.statusCode}');
}

Future<Map<String, dynamic>> getUserTrackingData(String userId, String token) async {
final response = await http.get(
Uri.parse('$baseUrl/tracking/$userId'),
headers: {'Authorization': 'Bearer $token'},
);
if (response.statusCode == 200) {
notifyListeners();
return jsonDecode(response.body) as Map<String, dynamic>;
}
throw Exception('Failed to load tracking data: ${response.statusCode}');
}

Future<List<dynamic>> getUserHistory(String userId, String token) async {
final response = await http.get(
Uri.parse('$baseUrl/history/$userId'),
headers: {'Authorization': 'Bearer $token'},
);
if (response.statusCode == 200) {
notifyListeners();
return jsonDecode(response.body) as List<dynamic>;
}
throw Exception('Failed to load history: ${response.statusCode}');
}

Future<List<dynamic>> getUserStatuses(String token) async {
  final response = await http.get(
    Uri.parse('$baseUrl/users/status'),
    headers: {'Authorization': 'Bearer $token'},
  );
  if (response.statusCode == 200) {
    notifyListeners();
    return jsonDecode(response.body) as List<dynamic>;
  }
  throw Exception('Failed to load user statuses: ${response.statusCode}');
}
Future<List<dynamic>> getAllUserLocations(String token) async {
final response = await http.get(
Uri.parse('$baseUrl/locations'),
headers: {'Authorization': 'Bearer $token'},
);
if (response.statusCode == 200) {
notifyListeners();
return jsonDecode(response.body) as List<dynamic>;
}
throw Exception('Failed to load user locations: ${response.statusCode}');
}

Future<void> sendLocationData(Map<String, dynamic> data, String token) async {
final response = await http.post(
Uri.parse('$baseUrl/location'),
headers: {
'Content-Type': 'application/json',
'Authorization': 'Bearer $token',
},
body: jsonEncode(data),
);
if (response.statusCode != 201) {
throw Exception('Failed to send location data: ${response.statusCode}');
}
notifyListeners();
}
}
