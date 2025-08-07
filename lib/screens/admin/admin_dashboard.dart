import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:custom_info_window/custom_info_window.dart';
import '../services/auth_service.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:ui' as ui;
import '../services/api_service.dart';
import '../services/location_service.dart';

class AdminDashboardScreen extends StatefulWidget {
final AuthService authService;
const AdminDashboardScreen({super.key, required this.authService});

@override
_AdminDashboardScreenState createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
GoogleMapController? _mapController;
final CustomInfoWindowController _customInfoWindowController = CustomInfoWindowController();
final _destinationController = TextEditingController();
final _nameController = TextEditingController();
final _emailController = TextEditingController();
final _numberController = TextEditingController();
final _usernameController = TextEditingController();
final _passwordController = TextEditingController();

List<dynamic> _users = [];
String? _selectedUserId;
LatLng? _currentPosition;
LatLng? _selectedDestination;
String? _selectedPlaceId;
bool _isUpdating = false;

Map<String, LatLng> _userDestinations = {};
Map<String, double> _userDistances = {};
Map<String, String> _userDurations = {};
Map<String, double> _userSpeeds = {};
Map<String, List<LatLng>> _userRoutes = {};

List<Map<String, dynamic>> _placeSuggestions = [];
Map<String, LatLng> _userLocations = {};
Set<Marker> _markers = {};
Set<Polyline> _polylines = {};

bool _isLoadingSuggestions = false;
bool _isSelectingDestination = false;
bool _showDestinationCard = false;
BitmapDescriptor? _userIcon;

final _formKey = GlobalKey<FormState>();

@override
void initState() {
super.initState();
_loadUserIcon();
_fetchUsers();
_fetchTodayDestinations();
_initMapPosition();
_startDataMonitoring();
}
Future<void> _loadUserIcon() async {
  try {
    // Load SVG and convert to BitmapDescriptor
    final svgString = await DefaultAssetBundle.of(context).loadString('assets/run.svg');
    final pictureInfo = await vg.loadPicture(SvgStringLoader(svgString), null);

    // Create a canvas to draw the SVG
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Set the size for the icon (smaller like WhatsApp)
    const size = Size(108, 108);

    // Scale the SVG to fit the desired size
    final scale = size.width / pictureInfo.size.width;
    canvas.scale(scale);

    // Draw the SVG on the canvas
    canvas.drawPicture(pictureInfo.picture);

    // Convert to image
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.width.toInt(), size.height.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

    // Create BitmapDescriptor from bytes
    _userIcon = BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());

    // Clean up
    pictureInfo.picture.dispose();
    picture.dispose();

    if (mounted) setState(() {});
  } catch (e) {
    debugPrint('Error loading SVG user icon: $e');
    // Fallback to default marker
    _userIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
    if (mounted) setState(() {});
  }
}
Future<void> _initMapPosition() async {
try {
final locationService = Provider.of<LocationService>(context, listen: false);
if (locationService.currentPosition != null) {
_currentPosition = LatLng(
locationService.currentPosition!.latitude,
locationService.currentPosition!.longitude,
);
} else {
_currentPosition = const LatLng(13.0827, 80.2707); // Chennai, Tamil Nadu
}

if (_mapController != null) {
await _mapController!.animateCamera(
CameraUpdate.newLatLngZoom(_currentPosition!, 14),
);
}
} catch (e) {
debugPrint('Error initializing map position: $e');
}
}

Future<void> _fetchUsers() async {
try {
final users = await Provider.of<ApiService>(context, listen: false)
    .getUsers(widget.authService.token ?? '');
if (mounted) {
setState(() {
_users = users;
});
}
} catch (e) {
if (mounted) {
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
content: Text('Failed to load users: $e'),
backgroundColor: Colors.redAccent,
),
);
}
}
}

Future<void> _fetchTodayDestinations() async {
try {
final destinations = await Provider.of<ApiService>(context, listen: false)
    .getUserDestination(widget.authService.userId ?? '', widget.authService.token ?? '');
if (mounted) {
setState(() {
_userDestinations = {

destinations['userId']: LatLng(destinations['latitude'], destinations['longitude'])
};
});
}
} catch (e) {
debugPrint('Error fetching today\'s destinations: $e');
}
}

Future<void> _calculateDistancesAndRoutes() async {
_userDistances.clear();
_userDurations.clear();
_userSpeeds.clear();
_userRoutes.clear();

final apiService = Provider.of<ApiService>(context, listen: false);
for (var userId in _userLocations.keys) {
if (_userDestinations.containsKey(userId) && _userLocations[userId] != null) {
try {
final routeData = await apiService.getRoute(
_userLocations[userId]!,
_userDestinations[userId]!,
);
_userDistances[userId] = routeData['distance'] as double? ?? 0.0;
_userDurations[userId] = routeData['duration'] as String? ?? 'N/A';
_userRoutes[userId] = routeData['points'] as List<LatLng>? ?? [];

final trackingData = await apiService.getUserTrackingData(
userId,
widget.authService.token ?? '',
);
_userSpeeds[userId] = trackingData['speed'] as double? ?? 0.0;
} catch (e) {
debugPrint('Error calculating data for user $userId: $e');
_userDistances[userId] = 0.0;
_userDurations[userId] = 'N/A';
_userSpeeds[userId] = 0.0;
}
}
}
if (mounted) setState(() {});
}

Future<void> _startDataMonitoring() async {
  while (mounted) {
    if (!_isUpdating) {
      _isUpdating = true;
      try {
        final locations = await Provider.of<ApiService>(context, listen: false)
            .getAllUserLocations(widget.authService.token ?? '');
        if (mounted) {
          bool hasChanges = false;
          Map<String, LatLng> newLocations = {
            for (var loc in locations)
              loc['userId']: LatLng(loc['latitude'], loc['longitude'])
          };

          // Check if locations have actually changed
          if (newLocations.length != _userLocations.length ||
              !newLocations.entries.every((entry) =>
              _userLocations[entry.key] == entry.value)) {
            _userLocations = newLocations;
            hasChanges = true;
          }

          await _fetchTodayDestinations();

          if (hasChanges) {
            await _calculateDistancesAndRoutes();
            _updateMapElements();
          }
        }
      } catch (e) {
        debugPrint('Error in data monitoring: $e');
      } finally {
        _isUpdating = false;
      }
    }
    await Future.delayed(const Duration(seconds: 3)); // Increased interval
  }
}
void _updateMapElements() {
  Set<Marker> newMarkers = {};
  Set<Polyline> newPolylines = {};

  for (var entry in _userLocations.entries) {
    final userId = entry.key;
    final user = _users.firstWhere(
          (u) => u['_id'] == userId,
      orElse: () => {'name': 'Unknown User'},
    );
    final distance = _userDistances[userId]?.toStringAsFixed(2) ?? 'N/A';
    final duration = _userDurations[userId] ?? 'N/A';
    final speed = _userSpeeds[userId]?.toStringAsFixed(1) ?? 'N/A';

    // Create smaller user location marker (like WhatsApp)
    newMarkers.add(Marker(
      markerId: MarkerId('user_$userId'),
      position: entry.value,
      icon: _userIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      anchor: const Offset(0.5, 0.5), // Center the marker properly
      zIndex: 1, // Ensure user markers are above other elements
      onTap: () {
        _customInfoWindowController.addInfoWindow!(
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  user['name'] ?? 'User $userId',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                if (_userDestinations[userId] != null) ...[
                  Text(
                    'Distance: $distance km',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    'ETA: $duration',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    'Speed: $speed km/h',
                    style: const TextStyle(fontSize: 12),
                  ),
                ] else
                  const Text(
                    'No destination assigned',
                    style: TextStyle(fontSize: 12),
                  ),
              ],
            ),
          ),
          entry.value,
        );
      },
    ));

    // Route polylines with better styling
    if (_userRoutes.containsKey(userId) && _userRoutes[userId]!.isNotEmpty) {
      newPolylines.add(Polyline(
        polylineId: PolylineId('route_$userId'),
        points: _userRoutes[userId]!,
        color: Colors.blue.withOpacity(0.8),
        width: 4,
      ));
    }
  }

  // Destination markers (standard size)
  for (var entry in _userDestinations.entries) {
    final user = _users.firstWhere(
          (u) => u['_id'] == entry.key,
      orElse: () => {'name': 'Unknown User'},
    );
    newMarkers.add(Marker(
      markerId: MarkerId('dest_${entry.key}'),
      position: entry.value,
      infoWindow: InfoWindow(
        title: '${user['name']}\'s Destination',
        snippet: 'Tap to view details',
      ),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      anchor: const Offset(0.5, 1.0), // Anchor at bottom center for destination
    ));
  }

  // Selected destination marker
  if (_selectedDestination != null) {
    newMarkers.add(Marker(
      markerId: const MarkerId('temp_destination'),
      position: _selectedDestination!,
      infoWindow: const InfoWindow(
        title: 'Selected Destination',
        snippet: 'Tap to remove',
      ),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      anchor: const Offset(0.5, 1.0),
      onTap: _clearDestination,
    ));
  }

  if (mounted) {
    setState(() {
      _markers = newMarkers;
      _polylines = newPolylines;
    });
  }
}
void _clearDestination() {
setState(() {
_selectedDestination = null;
_selectedPlaceId = null;
_destinationController.clear();
_placeSuggestions.clear();
_isSelectingDestination = false;
});
_customInfoWindowController.hideInfoWindow!();
_updateMapElements();
}

Future<void> _searchPlaces(String query) async {
if (query.isEmpty) {
setState(() {
_placeSuggestions = [];
_isLoadingSuggestions = false;
});
return;
}

setState(() => _isLoadingSuggestions = true);

try {
const apiKey = 'AIzaSyDSdQdpZQxS1cI_6nbz32U9zgpdj8oddes';
final response = await http.get(
Uri.parse(
'https://maps.googleapis.com/maps/api/place/autocomplete/json'
'?input=${Uri.encodeQueryComponent(query)}'
'&key=$apiKey'
'&region=in'
'&components=country:in',
),
);

if (response.statusCode == 200) {
final data = jsonDecode(response.body);
if (mounted) {
setState(() {
_placeSuggestions = List<Map<String, dynamic>>.from(data['predictions'] ?? []);
_isLoadingSuggestions = false;
});
}
} else {
throw Exception('API request failed with status: ${response.statusCode}');
}
} catch (e) {
if (mounted) {
setState(() {
_isLoadingSuggestions = false;
_placeSuggestions = [];
});
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
content: Text('Error loading suggestions: $e'),
backgroundColor: Colors.redAccent,
),
);
}
}
}

Future<LatLng?> _getPlaceLocation(String placeId) async {
try {
const apiKey = 'AIzaSyDSdQdpZQxS1cI_6nbz32U9zgpdj8oddes';
final response = await http.get(
Uri.parse(
'https://maps.googleapis.com/maps/api/place/details/json'
'?place_id=$placeId'
'&key=$apiKey'
'&fields=geometry',
),
);

if (response.statusCode == 200) {
final data = jsonDecode(response.body);
final location = data['result']?['geometry']?['location'];
if (location != null) {
return LatLng(location['lat'] as double, location['lng'] as double);
}
}
throw Exception('Invalid place details response');
} catch (e) {
debugPrint('Error getting place location: $e');
return null;
}
}

Future<void> _selectPlaceFromSuggestions(Map<String, dynamic> suggestion) async {
final placeId = suggestion['place_id'] as String?;
final description = suggestion['description'] as String? ?? '';
if (placeId == null) return;

try {
final location = await _getPlaceLocation(placeId);
if (location != null && mounted) {
setState(() {
_selectedDestination = location;
_selectedPlaceId = placeId;
_destinationController.text = description;
_placeSuggestions.clear();
_isLoadingSuggestions = false;
});
_updateMapElements();
_mapController?.animateCamera(CameraUpdate.newLatLngZoom(location, 16));
}
} catch (e) {
if (mounted) {
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
content: Text('Error selecting location: $e'),
backgroundColor: Colors.redAccent,
),
);
}
}
}

void _onMapTap(LatLng position) {
if (_isSelectingDestination) {
setState(() {
_selectedDestination = position;
_selectedPlaceId = null;
_destinationController.text =
'${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
_placeSuggestions.clear();
_isSelectingDestination = false;
});
_updateMapElements();
ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(
content: Text('Destination selected from map'),
backgroundColor: Colors.green,
duration: Duration(seconds: 2),
),
);
}
}

Future<void> _assignDestination() async {
if (_selectedUserId == null) {
ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(
content: Text('Please select a user first'),
backgroundColor: Colors.orange,
),
);
return;
}

if (_selectedDestination == null) {
ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(
content: Text('Please select a destination first'),
backgroundColor: Colors.orange,
),
);
return;
}

try {
await Provider.of<ApiService>(context, listen: false).assignDestination(
_selectedUserId!,
{
'latitude': _selectedDestination!.latitude,
'longitude': _selectedDestination!.longitude,
},
widget.authService.token ?? '',
);

if (mounted) {
setState(() {
_userDestinations[_selectedUserId!] = _selectedDestination!;
});
await _calculateDistancesAndRoutes();
_updateMapElements();
ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(
content: Text('Destination assigned successfully!'),
backgroundColor: Colors.green,
),
);
_clearDestination();
}
} catch (e) {
if (mounted) {
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
content: Text('Failed to assign destination: $e'),
backgroundColor: Colors.redAccent,
),
);
}
}
}

Future<void> _deleteDestination(String userId) async {
try {
await Provider.of<ApiService>(context, listen: false)
    .deleteDestination(userId, widget.authService.token ?? '');
if (mounted) {
setState(() {
_userDestinations.remove(userId);
_userDistances.remove(userId);
_userDurations.remove(userId);
_userSpeeds.remove(userId);
_userRoutes.remove(userId);
});
_updateMapElements();
_customInfoWindowController.hideInfoWindow!();
ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(
content: Text('Destination deleted successfully!'),
backgroundColor: Colors.green,
),
);
}
} catch (e) {
if (mounted) {
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
content: Text('Failed to delete destination: $e'),
backgroundColor: Colors.redAccent,
),
);
}
}
}

Future<void> _showAddUserDialog() async {
_nameController.clear();
_emailController.clear();
_numberController.clear();
_usernameController.clear();
_passwordController.clear();

await showDialog(
context: context,
builder: (context) => AlertDialog(
shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
title: Text(
'Add New User',
style: Theme.of(context).textTheme.titleLarge?.copyWith(
color: Colors.purple.shade700,
fontWeight: FontWeight.bold,
),
),
content: SingleChildScrollView(
child: Form(
key: _formKey,
child: Column(
mainAxisSize: MainAxisSize.min,
children: [
...[
{'controller': _nameController, 'label': 'Full Name', 'icon': Icons.person},
{'controller': _emailController, 'label': 'Email', 'icon': Icons.email},
{'controller': _numberController, 'label': 'Phone Number', 'icon': Icons.phone},
{'controller': _usernameController, 'label': 'Username', 'icon': Icons.account_circle},
{'controller': _passwordController, 'label': 'Password', 'icon': Icons.lock, 'obscure': true},
].map((field) => Padding(
padding: const EdgeInsets.only(bottom: 12),
child: TextFormField(
controller: field['controller'] as TextEditingController,
obscureText: field['obscure'] == true,
decoration: InputDecoration(
labelText: field['label'] as String,
prefixIcon: Icon(field['icon'] as IconData),
border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
filled: true,
fillColor: Colors.grey.shade50,
),
validator: (value) {
if (value?.trim().isEmpty ?? true) return 'This field is required';
if (field['label'] == 'Email') {
if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value!)) {
return 'Enter a valid email address';
}
}
if (field['label'] == 'Phone Number') {
if (!RegExp(r'^\+?[\d\s-]{10,}$').hasMatch(value!)) {
return 'Enter a valid phone number';
}
}
return null;
},
),
)),
],
),
),
),
actions: [
TextButton(
onPressed: () => Navigator.pop(context),
child: const Text('Cancel'),
),
ElevatedButton.icon(
onPressed: () async {
if (_formKey.currentState!.validate()) {
await _addUser();
if (mounted) Navigator.pop(context);
}
},
icon: const Icon(Icons.person_add),
label: const Text('Add User'),
style: ElevatedButton.styleFrom(
backgroundColor: Colors.blue,
foregroundColor: Colors.white,
shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
),
),
],
),
);
}

Future<void> _addUser() async {
try {
await Provider.of<ApiService>(context, listen: false).addUser(
{
'username': _usernameController.text.trim(),
'password': _passwordController.text,
'name': _nameController.text.trim(),
'email': _emailController.text.trim(),
'number': _numberController.text.trim(),
},
widget.authService.token ?? '',
);
if (mounted) {
ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(
content: Text('User added successfully!'),
backgroundColor: Colors.green,
),
);
await _fetchUsers();
}
} catch (e) {
if (mounted) {
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
content: Text('Failed to add user: $e'),
backgroundColor: Colors.redAccent,
),
);
}
}
}

Future<void> _showUpdateUserDialog(Map<String, dynamic> user) async {
_nameController.text = user['name'] ?? '';
_emailController.text = user['email'] ?? '';
_numberController.text = user['number'] ?? '';
_usernameController.text = user['username'] ?? '';
_passwordController.clear();

await showDialog(
context: context,
builder: (context) => AlertDialog(
shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
title: Text(
'Update User',
style: Theme.of(context).textTheme.titleLarge?.copyWith(
color: Colors.purple.shade700,
fontWeight: FontWeight.bold,
),
),
content: SingleChildScrollView(
child: Form(
key: _formKey,
child: Column(
mainAxisSize: MainAxisSize.min,
children: [
...[
{'controller': _nameController, 'label': 'Full Name', 'icon': Icons.person},
{'controller': _emailController, 'label': 'Email', 'icon': Icons.email},
{'controller': _numberController, 'label': 'Phone Number', 'icon': Icons.phone},
{'controller': _usernameController, 'label': 'Username', 'icon': Icons.account_circle},
{'controller': _passwordController, 'label': 'Password (optional)', 'icon': Icons.lock, 'obscure': true},
].map((field) => Padding(
padding: const EdgeInsets.only(bottom: 12),
child: TextFormField(
controller: field['controller'] as TextEditingController,
obscureText: field['obscure'] == true,
decoration: InputDecoration(
labelText: field['label'] as String,
prefixIcon: Icon(field['icon'] as IconData),
border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
filled: true,
fillColor: Colors.grey.shade50,
),
validator: (value) {
if (field['label'] == 'Password (optional)') return null;
if (value?.trim().isEmpty ?? true) return 'This field is required';
if (field['label'] == 'Email') {
if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value!)) {
return 'Enter a valid email address';
}
}
if (field['label'] == 'Phone Number') {
if (!RegExp(r'^\+?[\d\s-]{10,}$').hasMatch(value!)) {
return 'Enter a valid phone number';
}
}
return null;
},
),
)),
],
),
),
),
actions: [
TextButton(
onPressed: () => Navigator.pop(context),
child: const Text('Cancel'),
),
ElevatedButton.icon(
onPressed: () async {
if (_formKey.currentState!.validate()) {
await _updateUser(user['_id']);
if (mounted) Navigator.pop(context);
}
},
icon: const Icon(Icons.update),
label: const Text('Update User'),
style: ElevatedButton.styleFrom(
backgroundColor: Colors.blue,
foregroundColor: Colors.white,
shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
),
),
],
),
);
}

Future<void> _updateUser(String userId) async {
try {
final updateData = {
'username': _usernameController.text.trim(),
'name': _nameController.text.trim(),
'email': _emailController.text.trim(),
'number': _numberController.text.trim(),
};
if (_passwordController.text.isNotEmpty) {
updateData['password'] = _passwordController.text;
}
await Provider.of<ApiService>(context, listen: false)
    .updateUser(userId, updateData, widget.authService.token ?? '');
if (mounted) {
ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(
content: Text('User updated successfully!'),
backgroundColor: Colors.green,
),
);
await _fetchUsers();
}
} catch (e) {
if (mounted) {
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
content: Text('Failed to update user: $e'),
backgroundColor: Colors.redAccent,
),
);
}
}
}

Widget _buildDestinationCard() {
  return AnimatedContainer(
    duration: const Duration(milliseconds: 300),
    curve: Curves.easeInOut,
    height: _showDestinationCard ? null : 0,
    child: Visibility(
      visible: _showDestinationCard,
      child: Card(
        margin: const EdgeInsets.all(12),
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Assign Destination',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade800,
                ),
              ),
              const SizedBox(height: 16),

              // User Selection Dropdown
              DropdownButtonFormField<String>(
                hint: const Text('Select User'),
                value: _selectedUserId,
                isExpanded: true,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  prefixIcon: const Icon(Icons.person, color: Colors.blue),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: _users.map((user) {
                  return DropdownMenuItem<String>(
                    value: user['_id'],
                    child: Text(
                      user['name'] ?? user['username'] ?? 'Unknown',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedUserId = value;
                    if (value != null && _userLocations[value] != null) {
                      _mapController?.animateCamera(
                        CameraUpdate.newLatLngZoom(_userLocations[value]!, 16),
                      );
                    }
                  });
                },
              ),
              const SizedBox(height: 12),

              // Destination Search Field
              TextField(
                controller: _destinationController,
                decoration: InputDecoration(
                  labelText: 'Search destination',
                  hintText: 'Enter place name',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  prefixIcon: const Icon(Icons.search, color: Colors.blue),
                  suffixIcon: _destinationController.text.isNotEmpty
                      ? IconButton(
                    icon: const Icon(Icons.clear, color: Colors.blue),
                    onPressed: _clearDestination,
                  )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onChanged: _searchPlaces,
              ),

              // Loading indicator
              if (_isLoadingSuggestions)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(child: CircularProgressIndicator()),
                ),

              // Place suggestions
              if (_placeSuggestions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 120),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _placeSuggestions.length,
                    itemBuilder: (context, index) {
                      final suggestion = _placeSuggestions[index];
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        leading: const Icon(Icons.location_on, size: 16, color: Colors.blue),
                        title: Text(
                          suggestion['description'] ?? '',
                          style: const TextStyle(fontSize: 12),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _selectPlaceFromSuggestions(suggestion),
                      );
                    },
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // Current destination info (if exists)
              if (_selectedUserId != null && _userDestinations[_selectedUserId] != null) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Current Destination:',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                            onPressed: () => _deleteDestination(_selectedUserId!),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      Text(
                        'Lat: ${_userDestinations[_selectedUserId]!.latitude.toStringAsFixed(4)}, '
                            'Lng: ${_userDestinations[_selectedUserId]!.longitude.toStringAsFixed(4)}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      Text(
                        'Distance: ${_userDistances[_selectedUserId]?.toStringAsFixed(2) ?? 'N/A'} km | '
                            'Time: ${_userDurations[_selectedUserId] ?? 'N/A'} | '
                            'Speed: ${_userSpeeds[_selectedUserId]?.toStringAsFixed(1) ?? 'N/A'} km/h',
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _isSelectingDestination = !_isSelectingDestination;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(_isSelectingDestination
                                ? 'Tap on map to select destination'
                                : 'Map selection disabled'),
                            backgroundColor: _isSelectingDestination ? Colors.blue : Colors.grey,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: Icon(
                        _isSelectingDestination ? Icons.touch_app : Icons.touch_app_outlined,
                        size: 16,
                      ),
                      label: Text(
                        _isSelectingDestination ? 'Cancel Select' : 'Select on Map',
                        style: const TextStyle(fontSize: 12),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isSelectingDestination ? Colors.orange : Colors.blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _assignDestination,
                      icon: const Icon(Icons.send, size: 16),
                      label: const Text('Assign', style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
@override

// 4. Replace the complete build method
@override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: const Text('Admin Dashboard'),
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue, Colors.purple],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.person_add, color: Colors.white),
          onPressed: _showAddUserDialog,
          tooltip: 'Add New User',
        ),
        IconButton(
          icon: Icon(
            _showDestinationCard ? Icons.visibility_off : Icons.visibility,
            color: Colors.white,
          ),
          onPressed: () {
            setState(() {
              _showDestinationCard = !_showDestinationCard;
            });
          },
          tooltip: _showDestinationCard ? 'Hide Controls' : 'Show Controls',
        ),
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white),
          onPressed: () async {
            if (!_isUpdating) {
              setState(() => _isUpdating = true);
              await _fetchUsers();
              await _fetchTodayDestinations();
              await _calculateDistancesAndRoutes();
              _updateMapElements();
              setState(() => _isUpdating = false);
            }
          },
          tooltip: 'Refresh',
        ),
        IconButton(
          icon: const Icon(Icons.logout, color: Colors.white),
          onPressed: () {
            widget.authService.logout();
            Navigator.pushReplacementNamed(context, '/user/login');
          },
          tooltip: 'Logout',
        ),
      ],
    ),
    body: Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.grey.shade100, Colors.white],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Stack(
        children: [
          Column(
            children: [
              _buildDestinationCard(),
              Expanded(
                child: Card(
                  margin: const EdgeInsets.all(12),
                  elevation: 6,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: _currentPosition ?? const LatLng(13.0827, 80.2707),
                        zoom: 14,
                      ),
                      markers: _markers,
                      polylines: _polylines,
                      onMapCreated: (controller) {
                        _mapController = controller;
                        _customInfoWindowController.googleMapController = controller;
                        _initMapPosition();
                      },
                      onTap: (position) {
                        _customInfoWindowController.hideInfoWindow!();
                        _onMapTap(position);
                      },
                      onCameraMove: (position) {
                        _customInfoWindowController.onCameraMove!();
                      },
                      myLocationEnabled: true,
                      myLocationButtonEnabled: true,
                      zoomControlsEnabled: true,
                      mapToolbarEnabled: true,
                    ),
                  ),
                ),
              ),
            ],
          ),
          CustomInfoWindow(
            controller: _customInfoWindowController,
            height: 100,
            width: 150,
            offset: 50,
          ),
        ],
      ),
    ),
  );
}
@override
void dispose() {
_destinationController.dispose();
_nameController.dispose();
_emailController.dispose();
_numberController.dispose();
_usernameController.dispose();
_passwordController.dispose();
_mapController?.dispose();
_customInfoWindowController.dispose();
super.dispose();
}
}
