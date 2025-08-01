import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  _AdminDashboardScreenState createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              authService.logout();
              Navigator.pushReplacementNamed(context, '/admin/login');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search Users',
                suffixIcon: Icon(Icons.search),
              ),
              onChanged: (value) {
                setState(() {}); // Trigger rebuild for search filtering
              },
            ),
          ),
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: Provider.of<ApiService>(context, listen: false).getUsers(authService.token!),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Center(child: Text('Error loading users'));
                }
                final users = (snapshot.data ?? [])
                    .where((user) {
                  // Safe null checking for fullName
                  final fullName = user['fullName']?.toString() ?? '';
                  return fullName
                      .toLowerCase()
                      .contains(_searchController.text.toLowerCase());
                })
                    .toList();
                return ListView.builder(
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final user = users[index] as Map<String, dynamic>;
                    // Safe string conversion with fallbacks
                    final fullName = user['fullName']?.toString() ?? 'No Name';
                    final email = user['email']?.toString() ?? 'No Email';
                    final phoneNumber = user['phoneNumber']?.toString() ?? 'No Phone';

                    return ListTile(
                      title: Text(fullName),
                      subtitle: Text('$email | $phoneNumber'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => EditUserScreen(user: user),
                                ),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () async {
                              final userId = user['_id']?.toString();
                              if (userId != null) {
                                await Provider.of<ApiService>(context, listen: false)
                                    .deleteUser(userId, authService.token!);
                                setState(() {}); // Refresh user list
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.location_on),
                            onPressed: () {
                              final userId = user['_id']?.toString();
                              if (userId != null) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        UserTrackingScreen(userId: userId),
                                  ),
                                );
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.pin_drop),
                            onPressed: () {
                              final userId = user['_id']?.toString();
                              if (userId != null) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        AssignDestinationScreen(userId: userId),
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'addUser',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AddUserScreen(isAdmin: false)),
              );
            },
            child: const Icon(Icons.person_add),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: 'addAdmin',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AddUserScreen(isAdmin: true)),
              );
            },
            child: const Icon(Icons.admin_panel_settings),
          ),
        ],
      ),
    );
  }
}

class AddUserScreen extends StatefulWidget {
  final bool isAdmin;

  const AddUserScreen({super.key, required this.isAdmin});

  @override
  _AddUserScreenState createState() => _AddUserScreenState();
}

class _AddUserScreenState extends State<AddUserScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    return Scaffold(
      appBar: AppBar(title: Text(widget.isAdmin ? 'Add Admin' : 'Add User')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _fullNameController,
                decoration: const InputDecoration(labelText: 'Full Name'),
                validator: (value) => value == null || value.isEmpty ? 'Required' : null,
              ),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (value) =>
                value == null || !value.contains('@') ? 'Invalid email' : null,
              ),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'Phone Number'),
                validator: (value) => value == null || value.isEmpty ? 'Required' : null,
              ),
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(labelText: 'Username'),
                validator: (value) => value == null || value.isEmpty ? 'Required' : null,
              ),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
                validator: (value) =>
                value == null || value.length < 6 ? 'Minimum 6 characters' : null,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  if (_formKey.currentState!.validate()) {
                    await Provider.of<ApiService>(context, listen: false).addUser(
                      {
                        'fullName': _fullNameController.text,
                        'email': _emailController.text,
                        'phoneNumber': _phoneController.text,
                        'username': _usernameController.text,
                        'password': _passwordController.text,
                        'isAdmin': widget.isAdmin,
                      },
                      authService.token!,
                    );
                    Navigator.pop(context);
                  }
                },
                child: Text(widget.isAdmin ? 'Add Admin' : 'Add User'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EditUserScreen extends StatefulWidget {
  final Map<String, dynamic> user;

  const EditUserScreen({super.key, required this.user});

  @override
  _EditUserScreenState createState() => _EditUserScreenState();
}

class _EditUserScreenState extends State<EditUserScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _fullNameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;

  @override
  void initState() {
    super.initState();
    // Safe initialization with null checking
    _fullNameController = TextEditingController(text: widget.user['fullName']?.toString() ?? '');
    _emailController = TextEditingController(text: widget.user['email']?.toString() ?? '');
    _phoneController = TextEditingController(text: widget.user['phoneNumber']?.toString() ?? '');
    _usernameController = TextEditingController(text: widget.user['username']?.toString() ?? '');
    _passwordController = TextEditingController(text: widget.user['password']?.toString() ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    return Scaffold(
      appBar: AppBar(title: const Text('Edit User')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _fullNameController,
                decoration: const InputDecoration(labelText: 'Full Name'),
                validator: (value) => value == null || value.isEmpty ? 'Required' : null,
              ),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (value) =>
                value == null || !value.contains('@') ? 'Invalid email' : null,
              ),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'Phone Number'),
                validator: (value) => value == null || value.isEmpty ? 'Required' : null,
              ),
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(labelText: 'Username'),
                validator: (value) => value == null || value.isEmpty ? 'Required' : null,
              ),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
                validator: (value) =>
                value == null || value.length < 6 ? 'Minimum 6 characters' : null,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  if (_formKey.currentState!.validate()) {
                    final userId = widget.user['_id']?.toString();
                    if (userId != null) {
                      await Provider.of<ApiService>(context, listen: false).updateUser(
                        userId,
                        {
                          'fullName': _fullNameController.text,
                          'email': _emailController.text,
                          'phoneNumber': _phoneController.text,
                          'username': _usernameController.text,
                          'password': _passwordController.text,
                          'isAdmin': widget.user['isAdmin'] as bool? ?? false,
                        },
                        authService.token!,
                      );
                      Navigator.pop(context);
                    }
                  }
                },
                child: const Text('Update User'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AssignDestinationScreen extends StatefulWidget {
  final String userId;

  const AssignDestinationScreen({super.key, required this.userId});

  @override
  _AssignDestinationScreenState createState() => _AssignDestinationScreenState();
}

class _AssignDestinationScreenState extends State<AssignDestinationScreen> {
  GoogleMapController? _mapController;
  LatLng? _selectedLocation;
  final TextEditingController _addressController = TextEditingController();

  Future<void> _searchAddress(String address) async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(address)}&key=YOUR_GOOGLE_MAPS_API_KEY',
        ),
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['results'] != null && (data['results'] as List).isNotEmpty) {
        final location = data['results'][0]['geometry']['location'] as Map<String, dynamic>;
        final lat = location['lat'];
        final lng = location['lng'];
        if (lat != null && lng != null) {
          setState(() {
            _selectedLocation = LatLng(lat.toDouble(), lng.toDouble());
            _mapController?.animateCamera(
              CameraUpdate.newLatLng(_selectedLocation!),
            );
          });
        }
      }
    } catch (e) {
      // Handle error silently or show a snackbar
      print('Error searching address: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    return Scaffold(
      appBar: AppBar(title: const Text('Assign Destination')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _addressController,
                    decoration: const InputDecoration(labelText: 'Search Address'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _searchAddress(_addressController.text),
                ),
              ],
            ),
          ),
          Expanded(
            child: GoogleMap(
              initialCameraPosition: const CameraPosition(
                target: LatLng(37.7749, -122.4194), // Default: San Francisco
                zoom: 12,
              ),
              onMapCreated: (controller) {
                _mapController = controller;
              },
              onTap: (position) {
                setState(() {
                  _selectedLocation = position;
                });
              },
              markers: _selectedLocation != null
                  ? {
                Marker(
                  markerId: const MarkerId('destination'),
                  position: _selectedLocation!,
                ),
              }
                  : {},
            ),
          ),
          ElevatedButton(
            onPressed: _selectedLocation != null
                ? () async {
              await Provider.of<ApiService>(context, listen: false).assignDestination(
                widget.userId,
                {
                  'latitude': _selectedLocation!.latitude,
                  'longitude': _selectedLocation!.longitude,
                  'address': _addressController.text,
                },
                authService.token!,
              );
              Navigator.pop(context);
            }
                : null,
            child: const Text('Assign Destination'),
          ),
        ],
      ),
    );
  }
}

class UserTrackingScreen extends StatelessWidget {
  final String userId;

  const UserTrackingScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    return Scaffold(
      appBar: AppBar(title: const Text('User Tracking')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: Provider.of<ApiService>(context, listen: false)
            .getUserTrackingData(userId, authService.token!),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return const Center(child: Text('Error loading tracking data'));
          }
          final trackingData = snapshot.data!;
          final currentLocation = trackingData['currentLocation'] as Map<String, dynamic>? ?? {};
          final path = trackingData['path'] as List<dynamic>? ?? [];
          final destination = trackingData['destination'] as Map<String, dynamic>?;
          final eta = trackingData['eta']?.toString() ?? 'N/A';
          final distance = trackingData['distance']?.toString() ?? 'N/A';

          return Column(
            children: [
              Expanded(
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: LatLng(
                      (currentLocation['latitude'] as num?)?.toDouble() ?? 37.7749,
                      (currentLocation['longitude'] as num?)?.toDouble() ?? -122.4194,
                    ),
                    zoom: 14,
                  ),
                  polylines: {
                    if (path.isNotEmpty)
                      Polyline(
                        polylineId: const PolylineId('route'),
                        points: path
                            .where((point) => point != null &&
                            point['latitude'] != null &&
                            point['longitude'] != null)
                            .map((point) => LatLng(
                          (point['latitude'] as num).toDouble(),
                          (point['longitude'] as num).toDouble(),
                        ))
                            .toList(),
                        color: Colors.blue,
                        width: 5,
                      ),
                  },
                  markers: {
                    if (currentLocation.isNotEmpty &&
                        currentLocation['latitude'] != null &&
                        currentLocation['longitude'] != null)
                      Marker(
                        markerId: const MarkerId('current'),
                        position: LatLng(
                          (currentLocation['latitude'] as num).toDouble(),
                          (currentLocation['longitude'] as num).toDouble(),
                        ),
                        infoWindow: const InfoWindow(title: 'Current Location'),
                      ),
                    if (destination != null &&
                        destination['latitude'] != null &&
                        destination['longitude'] != null)
                      Marker(
                        markerId: const MarkerId('destination'),
                        position: LatLng(
                          (destination['latitude'] as num).toDouble(),
                          (destination['longitude'] as num).toDouble(),
                        ),
                        infoWindow: const InfoWindow(title: 'Destination'),
                      ),
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    Text('Speed: ${(currentLocation['speed'] as num?)?.toStringAsFixed(2) ?? 'N/A'} m/s'),
                    Text('Distance to Destination: $distance km'),
                    Text('ETA: $eta'),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => HistoryScreen(userId: userId),
                          ),
                        );
                      },
                      child: const Text('View History'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class HistoryScreen extends StatelessWidget {
  final String userId;

  const HistoryScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    return Scaffold(
      appBar: AppBar(title: const Text('User Travel History')),
      body: FutureBuilder<List<dynamic>>(
        future: Provider.of<ApiService>(context, listen: false).getUserHistory(userId, authService.token!),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return const Center(child: Text('No history available'));
          }
          final history = snapshot.data!;
          return ListView.builder(
            itemCount: history.length,
            itemBuilder: (context, index) {
              final entry = history[index] as Map<String, dynamic>;
              final date = entry['date']?.toString() ?? 'Unknown Date';
              final distance = entry['distance']?.toString() ?? 'N/A';
              final timeTaken = entry['timeTaken']?.toString() ?? 'N/A';

              return ListTile(
                title: Text(date),
                subtitle: Text('Distance: $distance km, Time: $timeTaken'),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => HistoryMapScreen(entry: entry),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class HistoryMapScreen extends StatelessWidget {
  final Map<String, dynamic> entry;

  const HistoryMapScreen({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final path = entry['path'] as List<dynamic>? ?? [];
    final date = entry['date']?.toString() ?? 'Unknown Date';

    // Check if path has valid data
    if (path.isEmpty || path.first == null ||
        path.first['latitude'] == null || path.first['longitude'] == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Route on $date')),
        body: const Center(child: Text('No route data available')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('Route on $date')),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: LatLng(
            (path[0]['latitude'] as num).toDouble(),
            (path[0]['longitude'] as num).toDouble(),
          ),
          zoom: 14,
        ),
        polylines: {
          Polyline(
            polylineId: const PolylineId('history_route'),
            points: path
                .where((point) => point != null &&
                point['latitude'] != null &&
                point['longitude'] != null)
                .map((point) => LatLng(
              (point['latitude'] as num).toDouble(),
              (point['longitude'] as num).toDouble(),
            ))
                .toList(),
            color: Colors.blue,
            width: 5,
          ),
        },
        markers: {
          if (path.isNotEmpty && path.first != null &&
              path.first['latitude'] != null && path.first['longitude'] != null)
            Marker(
              markerId: const MarkerId('start'),
              position: LatLng(
                (path[0]['latitude'] as num).toDouble(),
                (path[0]['longitude'] as num).toDouble(),
              ),
              infoWindow: const InfoWindow(title: 'Start'),
            ),
          if (path.isNotEmpty && path.last != null &&
              path.last['latitude'] != null && path.last['longitude'] != null)
            Marker(
              markerId: const MarkerId('end'),
              position: LatLng(
                (path.last['latitude'] as num).toDouble(),
                (path.last['longitude'] as num).toDouble(),
              ),
              infoWindow: const InfoWindow(title: 'End'),
            ),
        },
      ),
    );
  }
}