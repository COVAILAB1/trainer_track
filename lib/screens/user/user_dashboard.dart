import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/api_service.dart';

class UserDashboardScreen extends StatefulWidget {
  final AuthService authService;
  const UserDashboardScreen({super.key, required this.authService});

  @override
  State<UserDashboardScreen> createState() => _UserDashboardScreenState();
}

class _UserDashboardScreenState extends State<UserDashboardScreen> {
  GoogleMapController? _mapController;
  LatLng? _currentPosition;
  LatLng? _destination;
  Set<Polyline> _polylines = {};
  bool _permissionsGranted = false;
  bool _isTracking = false;

  // Permission status tracking
  Map<Permission, PermissionStatus> _permissionStatuses = {};
  List<Permission> _requiredPermissions = [
    Permission.location,
    Permission.locationAlways,
    Permission.locationWhenInUse,
    Permission.notification,
    Permission.bluetooth,
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.nearbyWifiDevices,
  ];

  @override
  void initState() {
    super.initState();
    _requestAllPermissions();
    _checkDestination();
  }

  Future<void> _requestAllPermissions() async {
    await _checkCurrentPermissionStatuses();
    await _requestMissingPermissions();
  }

  Future<void> _checkCurrentPermissionStatuses() async {
    for (Permission permission in _requiredPermissions) {
      try {
        final status = await permission.status;
        _permissionStatuses[permission] = status;
      } catch (e) {
        // Some permissions might not be available on all platforms
        print('Error checking permission $permission: $e');
      }
    }
  }

  Future<void> _requestMissingPermissions() async {
    List<Permission> permissionsToRequest = [];

    for (Permission permission in _requiredPermissions) {
      final status = _permissionStatuses[permission];
      if (status != null && !status.isGranted) {
        permissionsToRequest.add(permission);
      }
    }

    if (permissionsToRequest.isNotEmpty) {
      await _requestPermissions(permissionsToRequest);
    }

    _updatePermissionStatus();
  }

  Future<void> _requestPermissions(List<Permission> permissions) async {
    try {
      // Request location permissions first (most critical)
      if (permissions.contains(Permission.location)) {
        final locationStatus = await Permission.location.request();
        _permissionStatuses[Permission.location] = locationStatus;

        if (locationStatus.isGranted) {
          // If basic location is granted, request always location
          if (permissions.contains(Permission.locationAlways)) {
            final alwaysStatus = await Permission.locationAlways.request();
            _permissionStatuses[Permission.locationAlways] = alwaysStatus;
          }
        }
      }

      // Request notification permission
      if (permissions.contains(Permission.notification)) {
        final notificationStatus = await Permission.notification.request();
        _permissionStatuses[Permission.notification] = notificationStatus;
      }

      // Request Bluetooth permissions (for nearby devices)
      final bluetoothPermissions = [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ];

      for (Permission bluetoothPerm in bluetoothPermissions) {
        if (permissions.contains(bluetoothPerm)) {
          try {
            final status = await bluetoothPerm.request();
            _permissionStatuses[bluetoothPerm] = status;
          } catch (e) {
            print('Bluetooth permission $bluetoothPerm not available: $e');
          }
        }
      }

      // Request nearby WiFi devices permission
      if (permissions.contains(Permission.nearbyWifiDevices)) {
        try {
          final wifiStatus = await Permission.nearbyWifiDevices.request();
          _permissionStatuses[Permission.nearbyWifiDevices] = wifiStatus;
        } catch (e) {
          print('Nearby WiFi devices permission not available: $e');
        }
      }

    } catch (e) {
      print('Error requesting permissions: $e');
    }
  }

  void _updatePermissionStatus() {
    final locationGranted = _permissionStatuses[Permission.location]?.isGranted ?? false;
    final locationAlwaysGranted = _permissionStatuses[Permission.locationAlways]?.isGranted ?? false;

    setState(() {
      _permissionsGranted = locationGranted || locationAlwaysGranted;
    });

    if (!_permissionsGranted) {
      _showPermissionDeniedDialog();
    }
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Permissions Required'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This app requires several permissions to function properly:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              _buildPermissionStatusItem('Location', Permission.location, Icons.location_on),
              _buildPermissionStatusItem('Background Location', Permission.locationAlways, Icons.my_location),
              _buildPermissionStatusItem('Notifications', Permission.notification, Icons.notifications),
              _buildPermissionStatusItem('Bluetooth', Permission.bluetooth, Icons.bluetooth),
              _buildPermissionStatusItem('Nearby Devices', Permission.nearbyWifiDevices, Icons.devices),
              const SizedBox(height: 10),
              const Text(
                'Location permissions are essential for tracking functionality.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _requestAllPermissions();
            },
            child: const Text('Try Again'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionStatusItem(String name, Permission permission, IconData icon) {
    final status = _permissionStatuses[permission];
    final isGranted = status?.isGranted ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: isGranted ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(name, style: const TextStyle(fontSize: 14))),
          Icon(
            isGranted ? Icons.check_circle : Icons.cancel,
            size: 16,
            color: isGranted ? Colors.green : Colors.red,
          ),
        ],
      ),
    );
  }

  Future<void> _checkDestination() async {
    try {
      final destinationData = await Provider.of<ApiService>(context, listen: false)
          .getUserDestination(widget.authService.userId!, widget.authService.token!);
      setState(() {
        _destination = LatLng(
          destinationData['latitude'] as double,
          destinationData['longitude'] as double,
        );
        _updateRoute();
      });
    } catch (e) {
      // No destination assigned
      print('No destination found: $e');
    }
  }

  Future<void> _updateRoute() async {
    if (_currentPosition != null && _destination != null) {
      try {
        final routePoints = await Provider.of<ApiService>(context, listen: false)
            .getRoute(_currentPosition!, _destination!);
        setState(() {
          _polylines = {
            Polyline(
              polylineId: const PolylineId('route'),
              points: routePoints,
              color: Colors.blue,
              width: 5,
            ),
          };
        });
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load route: $e')),
        );
      }
    }
  }

  void _showPermissionStatusDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permission Status'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPermissionStatusItem('Location', Permission.location, Icons.location_on),
              _buildPermissionStatusItem('Background Location', Permission.locationAlways, Icons.my_location),
              _buildPermissionStatusItem('Location When In Use', Permission.locationWhenInUse, Icons.near_me),
              _buildPermissionStatusItem('Notifications', Permission.notification, Icons.notifications),
              _buildPermissionStatusItem('Bluetooth', Permission.bluetooth, Icons.bluetooth),
              _buildPermissionStatusItem('Bluetooth Scan', Permission.bluetoothScan, Icons.bluetooth_searching),
              _buildPermissionStatusItem('Bluetooth Connect', Permission.bluetoothConnect, Icons.bluetooth_connected),
              _buildPermissionStatusItem('Nearby WiFi Devices', Permission.nearbyWifiDevices, Icons.wifi),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _requestAllPermissions();
            },
            child: const Text('Refresh Permissions'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Welcome, ${widget.authService.userName ?? "User"}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showPermissionStatusDialog,
            tooltip: 'Permission Status',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              widget.authService.logout();
              Navigator.pushReplacementNamed(context, '/user/login');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Permission status banner
          if (!_permissionsGranted)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: Colors.orange.shade100,
              child: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.orange),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Some permissions are missing. Tap to grant permissions.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: _requestAllPermissions,
                    child: const Text('Grant'),
                  ),
                ],
              ),
            ),

          Expanded(
            child: Consumer<LocationService>(
              builder: (context, locationService, child) {
                _currentPosition = locationService.currentPosition != null
                    ? LatLng(
                  locationService.currentPosition!.latitude,
                  locationService.currentPosition!.longitude,
                )
                    : null;

                if (_currentPosition != null && _isTracking) {
                  _updateRoute();
                }

                return GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _currentPosition ?? const LatLng(37.7749, -122.4194), // Default: San Francisco
                    zoom: 14,
                  ),
                  markers: {
                    if (_currentPosition != null)
                      Marker(
                        markerId: const MarkerId('current'),
                        position: _currentPosition!,
                        infoWindow: const InfoWindow(title: 'Current Location'),
                        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
                      ),
                    if (_destination != null)
                      Marker(
                        markerId: const MarkerId('destination'),
                        position: _destination!,
                        infoWindow: const InfoWindow(title: 'Destination'),
                        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                      ),
                  },
                  polylines: _polylines,
                  onMapCreated: (controller) {
                    _mapController = controller;
                    // Auto-focus on current location if available
                    if (_currentPosition != null) {
                      controller.animateCamera(
                        CameraUpdate.newLatLng(_currentPosition!),
                      );
                    }
                  },
                  myLocationEnabled: _permissionsGranted,
                  myLocationButtonEnabled: _permissionsGranted,
                );
              },
            ),
          ),

          // Control panel
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.3),
                  spreadRadius: 1,
                  blurRadius: 5,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              children: [
                // Status indicators
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatusIndicator(
                      'Location',
                      _permissionStatuses[Permission.location]?.isGranted ?? false,
                      Icons.location_on,
                    ),
                    _buildStatusIndicator(
                      'Notifications',
                      _permissionStatuses[Permission.notification]?.isGranted ?? false,
                      Icons.notifications,
                    ),
                    _buildStatusIndicator(
                      'Bluetooth',
                      _permissionStatuses[Permission.bluetooth]?.isGranted ?? false,
                      Icons.bluetooth,
                    ),
                    _buildStatusIndicator(
                      'Tracking',
                      _isTracking,
                      Icons.my_location,
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _permissionsGranted
                            ? () {
                          setState(() {
                            _isTracking = !_isTracking;
                            if (_isTracking) {
                              Provider.of<LocationService>(context, listen: false)
                                  .startTracking(widget.authService.userId!, widget.authService.token!);
                            } else {
                              Provider.of<LocationService>(context, listen: false).stopTracking();
                            }
                          });
                        }
                            : _requestAllPermissions,
                        icon: Icon(_isTracking ? Icons.stop : Icons.play_arrow),
                        label: Text(_isTracking ? 'Stop Tracking' : 'Start Tracking'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isTracking ? Colors.red : Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => HistoryScreen(userId: widget.authService.userId!),
                          ),
                        );
                      },
                      icon: const Icon(Icons.history),
                      label: const Text('History'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(String label, bool isActive, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isActive ? Colors.green.shade100 : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: isActive ? Colors.green : Colors.grey,
            size: 20,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isActive ? Colors.green : Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
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
      appBar: AppBar(title: const Text('Travel History')),
      body: FutureBuilder<List<dynamic>>(
        future: Provider.of<ApiService>(context, listen: false).getUserHistory(userId, authService.token!),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No history available',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Start tracking to see your travel history',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            );
          }
          final history = snapshot.data!;
          return ListView.builder(
            itemCount: history.length,
            itemBuilder: (context, index) {
              final entry = history[index] as Map<String, dynamic>;
              final date = entry['date']?.toString() ?? 'Unknown Date';
              final distance = entry['distance']?.toString() ?? 'N/A';
              final timeTaken = entry['timeTaken']?.toString() ?? 'N/A';

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.blue,
                    child: Icon(Icons.route, color: Colors.white),
                  ),
                  title: Text(date),
                  subtitle: Text('Distance: $distance km • Time: $timeTaken'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => HistoryMapScreen(entry: entry),
                      ),
                    );
                  },
                ),
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
    final distance = entry['distance']?.toString() ?? 'N/A';
    final timeTaken = entry['timeTaken']?.toString() ?? 'N/A';

    // Check if path has valid data
    if (path.isEmpty || path.first == null ||
        path.first['latitude'] == null || path.first['longitude'] == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Route on $date')),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.map, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'No route data available',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Route on $date'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Trip Details'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Date: $date'),
                      Text('Distance: $distance km'),
                      Text('Duration: $timeTaken'),
                      Text('Points: ${path.length}'),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
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
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
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
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            ),
        },
      ),
    );
  }
}