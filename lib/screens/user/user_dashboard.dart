import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;
import 'dart:async'; // Add this import for Timer
import '../services/auth_service.dart';
import '../services/fcm_service.dart';
import '../services/location_service.dart';
import '../services/api_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
class UserDashboardScreen extends StatefulWidget {
  final AuthService authService;
  const UserDashboardScreen({super.key, required this.authService});

  @override
  State<UserDashboardScreen> createState() => _UserDashboardScreenState();
}

class _UserDashboardScreenState extends State<UserDashboardScreen> with WidgetsBindingObserver{
  GoogleMapController? _mapController;
  LatLng? _currentPosition;
  LatLng? _destination;
  LatLng? _startLocation;
  List<LatLng> _travelPath = [];
  Set<Polyline> _polylines = {};
  bool _permissionsGranted = false;
  bool _isTracking = false;
  double? _speed;
  String? _distanceToDestination;
  String? _etaToDestination;
  LocationService? _locationService;
  double _currentZoom = 14.0; // Track current zoom level

  // Add Timer for periodic location sending
  Timer? _locationSendTimer;
  static const Duration _locationSendInterval = Duration(seconds: 10);
  DateTime? _lastLocationSent;
  bool _locationSendingActive = false;
  String _appStatus = 'foreground';
  List<Map<String, dynamic>> _trackingNotifications = [];
  bool _destinationProximityNotified = false; // Add this to the class variables
  Map<Permission, PermissionStatus> _permissionStatuses = {};
  List<Permission> _requiredPermissions = [
    Permission.location,
    Permission.locationAlways,
    Permission.notification,
  ];

  @override
  void initState() {
    super.initState();
    _requestAllPermissions();
    FCMService.initialize();
    _initializeAdminFCM();
    _initializeAutoFCM();

    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _locationService = Provider.of<LocationService>(context, listen: false);
    _locationService!.addListener(_handleLocationUpdate);
  }

  @override
  void dispose() {
    // Remove the lifecycle observer first to prevent further callbacks
    WidgetsBinding.instance.removeObserver(this);

    // Send offline status BEFORE cleaning up other resources
    if (_currentPosition != null && mounted) {
      // Use a synchronous approach for dispose
      _sendOfflineStatusSync();
    }

    // Clean up other resources
    _locationService?.removeListener(_handleLocationUpdate);
    _locationService?.stopTracking(widget.authService.userId);
    _stopPeriodicLocationSending();
    _mapController?.dispose();

    super.dispose();
  }
  Future<void> _initializeAdminFCM() async {


    // Subscribe to admin topic to receive notifications[7]
    await FCMService.subscribeToTopic('destination_${widget.authService.userId}');

    // Handle foreground messages specifically for admin
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      setState(() {
        _trackingNotifications.add({
          'title': message.notification?.title ?? 'Tracking Update',
          'body': message.notification?.body ?? 'User tracking activity',
          'data': message.data,
          'timestamp': DateTime.now(),
        });
      });
    });
  }

  Future<void> _initializeAutoFCM() async {


    // Subscribe to admin topic to receive notifications[7]
    await FCMService.subscribeToTopic('user_${widget.authService.userId}');

    // Handle foreground messages specifically for admin
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      setState(() {
        _trackingNotifications.add({
          'title': message.notification?.title ?? 'Tracking Update',
          'body': message.notification?.body ?? 'User tracking activity',
          'data': message.data,
          'timestamp': DateTime.now(),
        });
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    print('App lifecycle state changed to: $state');

    String newStatus;
    switch (state) {
      case AppLifecycleState.resumed:
        newStatus = 'foreground';
        break;
      case AppLifecycleState.inactive:
        newStatus = 'background';
        break;
      case AppLifecycleState.paused:
        newStatus = 'background';
        break;
      case AppLifecycleState.detached:
        newStatus = 'offline';
        // Send offline status when app is detached (app is closing)
        print('App detached - sending offline status immediately...');
        if (mounted && _currentPosition != null && _isTracking) {
          _sendOfflineStatusImmediate();
        }
        break;
      default:
        newStatus = 'foreground';
    }

    // Update _appStatus
    String oldStatus = _appStatus;
    _appStatus = newStatus;

    // Only call setState if the widget is still mounted and active
    if (mounted) {
      setState(() {
        // _appStatus is already updated above
      });

      // Send status update to backend for any status changes while tracking
      if (_isTracking && _currentPosition != null && oldStatus != newStatus) {
        print('Sending status update from $oldStatus to $newStatus');
        _sendCurrentStatusToBackend(newStatus);
      }
    }

    print('App status changed from $oldStatus to: $newStatus');
  }
  Future<void> _sendCurrentStatusToBackend(String status) async {
    if (_currentPosition == null) return;

    final locationData = {
      'userId': widget.authService.userId ?? '',
      'latitude': _currentPosition!.latitude,
      'longitude': _currentPosition!.longitude,
      'speed': _speed ?? 0.0,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'appStatus': status,
    };

    try {
      await Provider.of<ApiService>(context, listen: false)
          .sendLocationData(locationData, widget.authService.token ?? '');
      print('Status update sent to backend: $status at ${DateTime.now()}');
    } catch (e) {
      print('Error sending status update to backend: $e');
    }
  }
  void _sendOfflineStatusSync() {
    if (_currentPosition == null || !mounted) return;

    final locationData = {
      'userId': widget.authService.userId ?? '',
      'latitude': _currentPosition!.latitude,
      'longitude': _currentPosition!.longitude,
      'speed': _speed ?? 0.0,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'appStatus': 'offline',
    };

    try {
      // Fire and forget - send offline status without waiting
      Provider.of<ApiService>(context, listen: false)
          .sendLocationData(locationData, widget.authService.token ?? '');
      print('Offline status sent synchronously at ${DateTime.now()}: $_currentPosition');
    } catch (e) {
      print('Error sending offline status synchronously: $e');
    }
  }

  // Modified _sendOfflineStatus to handle cases where widget is not mounted
  Future<void> _sendOfflineStatus() async {
    // Check if we have current position, if not, don't send
    if (_currentPosition == null) {
      print('Cannot send offline status: current position is null');
      return;
    }

    final locationData = {
      'userId': widget.authService.userId ?? '',
      'latitude': _currentPosition!.latitude,
      'longitude': _currentPosition!.longitude,
      'speed': _speed ?? 0.0,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'appStatus': 'offline',
    };

    try {
      // Use context if mounted, otherwise get ApiService instance differently
      ApiService apiService;
      if (mounted) {
        apiService = Provider.of<ApiService>(context, listen: false);
      } else {
        // If not mounted, we need to handle this differently
        print('Widget not mounted, cannot send offline status through Provider');
        return;
      }

      await apiService.sendLocationData(locationData, widget.authService.token ?? '');
      print('Offline status sent to backend at ${DateTime.now()}: $_currentPosition');
    } catch (e) {
      print('Error sending offline status to backend: $e');
      // Avoid showing SnackBar if not mounted
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send offline status: $e'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  void _sendOfflineStatusImmediate() {
    if (_currentPosition == null || !mounted) return;

    final locationData = {
      'userId': widget.authService.userId ?? '',
      'latitude': _currentPosition!.latitude,
      'longitude': _currentPosition!.longitude,
      'speed': _speed ?? 0.0,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'appStatus': 'offline',
    };

    print('Sending immediate offline status: $locationData');

    try {
      // Get ApiService and send immediately
      final apiService = Provider.of<ApiService>(context, listen: false);
      apiService.sendLocationData(locationData, widget.authService.token ?? '').then((_) {
        print('Immediate offline status sent successfully at ${DateTime.now()}');
      }).catchError((error) {
        print('Error sending immediate offline status: $error');
      });
    } catch (e) {
      print('Error getting ApiService for immediate offline status: $e');
    }
  }
  void _handleLocationUpdate() {
    if (!mounted) return;

    final newPosition = _locationService!.currentLocationLatLng;
    final newSpeed = _locationService!.currentPosition?.speed != null &&
        _locationService!.currentPosition!.speed >= 0
        ? (_locationService!.currentPosition!.speed * 3.6).toDouble()
        : null;

    setState(() {
      _currentPosition = newPosition;
      _speed = newSpeed;

      if (_isTracking && newPosition != null) {
        if (_travelPath.isEmpty ||
            (_travelPath.last.latitude != newPosition.latitude ||
                _travelPath.last.longitude != newPosition.longitude)) {
          _travelPath.add(newPosition);
        }
        if (_travelPath.length > 1) {
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('travel_path'),
              points: _travelPath,
              color: Colors.green,
              width: 5,
            ),
          );
        }
      }
    });

    if (newPosition != null && _mapController != null && _isTracking) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLng(newPosition),
      );
    }

    if (_isTracking && _destination != null && newPosition != null) {
      _updateRoute();
    }
  }

  // New method to start periodic location sending
  void _startPeriodicLocationSending() {
    _locationSendTimer?.cancel(); // Cancel existing timer if any

    setState(() {
      _locationSendingActive = true;
    });

    _locationSendTimer = Timer.periodic(_locationSendInterval, (timer) async {
      if (!_isTracking || _currentPosition == null) {
        return;
      }

      try {
        // Send current location to backend every 5 seconds
        if(_currentPosition !=null) {
          await _sendLocationToBackend();
          setState(() {
            _lastLocationSent = DateTime.now();
          });
          print(
              'Location sent to backend at ${_lastLocationSent}: $_currentPosition');
        }
      } catch (e) {
        print('Error sending location to backend: $e');
        // Optionally show a snackbar or handle the error
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to send location: $e'),
              duration: const Duration(seconds: 2),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    });
  }

  // New method to stop periodic location sending
  void _stopPeriodicLocationSending() {
    _locationSendTimer?.cancel();
    _locationSendTimer = null;
    setState(() {
      _locationSendingActive = false;
      _lastLocationSent = null;
    });
  }

  // New method to send location data to backend
  Future<void> _sendLocationToBackend() async {
    if (_currentPosition == null || !_isTracking) return;

    final locationData = {
      'userId': widget.authService.userId ?? '',
      'latitude': _currentPosition!.latitude,
      'longitude': _currentPosition!.longitude,
      'speed': _speed ?? 0.0,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'appStatus':_appStatus
    };

    // Send to backend via ApiService
    await Provider.of<ApiService>(context, listen: false)
        .sendLocationData(locationData, widget.authService.token ?? '');
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
      if (permissions.contains(Permission.location)) {
        final locationStatus = await Permission.location.request();
        _permissionStatuses[Permission.location] = locationStatus;
        if (locationStatus.isGranted && permissions.contains(Permission.locationAlways)) {
          final alwaysStatus = await Permission.locationAlways.request();
          _permissionStatuses[Permission.locationAlways] = alwaysStatus;
        }
      }
      if (permissions.contains(Permission.notification)) {
        final notificationStatus = await Permission.notification.request();
        _permissionStatuses[Permission.notification] = notificationStatus;
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
              const Text('This app requires permissions to function properly:'),
              _buildPermissionStatusItem('Location', Permission.location, Icons.location_on),
              _buildPermissionStatusItem('Background Location', Permission.locationAlways, Icons.my_location),
              _buildPermissionStatusItem('Notifications', Permission.notification, Icons.notifications),
              const SizedBox(height: 10),
              const Text('Location permissions are essential for tracking.', style: TextStyle(fontSize: 12, color: Colors.grey)),
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
          Icon(icon, size: 16, color: isGranted ? Colors.green : Colors.red),
          const SizedBox(width: 8),
          Expanded(child: Text(name, style: const TextStyle(fontSize: 14))),
          Icon(isGranted ? Icons.check_circle : Icons.cancel, size: 16, color: isGranted ? Colors.green : Colors.red),
        ],
      ),
    );
  }

  Future<void> _checkDestination() async {
    try {
      final destinationData = await Provider.of<ApiService>(context, listen: false)
          .getUserDestination(widget.authService.userId ?? '', widget.authService.token ?? '');
      print('Destination fetched: $destinationData');
      setState(() {
        _destination = LatLng(
          destinationData['latitude'] as double? ?? 0.0,
          destinationData['longitude'] as double? ?? 0.0,
        );
      });
      if (_currentPosition != null && _isTracking) {
        _updateRoute();
      }
    } catch (e) {
      print('Error fetching destination: $e');
      setState(() {
        _destination = null;
        _etaToDestination = null;
        _distanceToDestination = null;
        _polylines = _travelPath.length > 1
            ? {
          Polyline(
            polylineId: const PolylineId('travel_path'),
            points: _travelPath,
            color: Colors.green,
            width: 5,
          ),
        }
            : {};
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No destination assigned for today: $e')),
      );
    }
  }

  Future<void> _updateRoute() async {
    if (_currentPosition == null || _destination == null || _mapController == null) {
      print('Cannot update route: missing currentPosition, destination, or mapController');
      setState(() {
        _etaToDestination = 'N/A';
        _distanceToDestination = 'N/A';
        _polylines = _travelPath.length > 1
            ? {
          Polyline(
            polylineId: const PolylineId('travel_path'),
            points: _travelPath,
            color: Colors.green,
            width: 5,
          ),
        }
            : {};
      });
      return;
    }

    try {
      print('Fetching route from $_currentPosition to $_destination');
      final currentToDestResult = await Provider.of<ApiService>(context, listen: false)
          .getRoute(_currentPosition!, _destination!);

      if (currentToDestResult['points'] == null || currentToDestResult['points'].isEmpty) {
        print('No route points returned from ApiService');
        throw Exception('Empty route points');
      }

      Set<Polyline> polylines = {};

      if (_isTracking && _startLocation != null) {
        print('Fetching planned route from $_startLocation to $_destination');
        final plannedRouteResult = await Provider.of<ApiService>(context, listen: false)
            .getRoute(_startLocation!, _destination!);
        polylines.add(
          Polyline(
            polylineId: const PolylineId('planned_route'),
            points: plannedRouteResult['points']?.cast<LatLng>() ?? [],
            color: Colors.blue.withOpacity(0.5),
            width: 3,
            patterns: [PatternItem.dash(20), PatternItem.gap(10)],
          ),
        );
      }

      polylines.add(
        Polyline(
          polylineId: const PolylineId('current_route'),
          points: currentToDestResult['points']?.cast<LatLng>() ?? [],
          color: Colors.blue,
          width: 4,
        ),
      );

      if (_isTracking && _travelPath.length > 1) {
        polylines.add(
          Polyline(
            polylineId: const PolylineId('travel_path'),
            points: _travelPath,
            color: Colors.green,
            width: 5,
          ),
        );
      }
      final distanceInKm = currentToDestResult['distance']?.toDouble() ?? double.infinity;
      final distanceInMeters = distanceInKm * 1000;
      setState(() {
        _polylines = polylines;
        _etaToDestination = currentToDestResult['duration']?.toString() ?? 'N/A';
        _distanceToDestination = currentToDestResult['distance'] != null
            ? '${currentToDestResult['distance'].toStringAsFixed(1)} km'
            : 'N/A';
      });
      if (distanceInMeters <= 250 && !_destinationProximityNotified && _isTracking) {
        try {
          final notificationData = {
            'userId': widget.authService.userId ?? '',
            'userName': widget.authService.userName ?? 'Unknown User',
            'distanceToDestination': distanceInMeters,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          };

          // Call the backend API to trigger the FCM notification
          await Provider.of<ApiService>(context, listen: false).sendProximityNotification(
            notificationData,
            widget.authService.token ?? '',
          );

          print('Proximity notification request sent to backend: User within 250m of destination');
          setState(() {
            _destinationProximityNotified = true; // Prevent further notifications
          });
        } catch (e) {
          print('Error sending proximity notification request to backend: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to send proximity notification: $e'),
                duration: const Duration(seconds: 2),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } else if (distanceInMeters > 250 && _destinationProximityNotified) {
        // Reset the flag if user moves out of the 250m radius
        setState(() {
          _destinationProximityNotified = false;
        });
      }



      // Adjust camera bounds only on first route load
      if (_polylines.length == 2) { // Initial route load (planned_route + current_route)
        List<LatLng> allPoints = [_currentPosition!, _destination!];
        if (_startLocation != null) {
          allPoints.insert(0, _startLocation!);
        }
        _adjustCameraToShowAllPoints(allPoints);
      }
    } catch (e) {
      print('Error updating route: $e');
      setState(() {
        _etaToDestination = 'N/A';
        _distanceToDestination = 'N/A';
        _polylines = _travelPath.length > 1
            ? {
          Polyline(
            polylineId: const PolylineId('travel_path'),
            points: _travelPath,
            color: Colors.green,
            width: 5,
          ),
        }
            : {};
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load route: $e')),
      );
    }
  }

  void _adjustCameraToShowAllPoints(List<LatLng> points) {
    if (points.isEmpty || _mapController == null) return;

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (LatLng point in points) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        100.0,
      ),
    );
    _currentZoom = 14.0; // Reset zoom after bounds adjustment
  }

  double _calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371000;
    double lat1Rad = point1.latitude * (math.pi / 180);
    double lat2Rad = point2.latitude * (math.pi / 180);
    double deltaLat = (point2.latitude - point1.latitude) * (math.pi / 180);
    double deltaLng = (point2.longitude - point1.longitude) * (math.pi / 180);

    double a = math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1Rad) * math.cos(lat2Rad) * math.sin(deltaLng / 2) * math.sin(deltaLng / 2);
    double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }
// Corrected _handleTrackingToggle method
  void _handleTrackingToggle() async {
    if (!_isTracking) {
      // Starting tracking - check destination first
      await _checkDestination();
      if (_destination == null) {
        return;
      }

      // Update state to tracking
      setState(() {
        _isTracking = true;
        _appStatus = 'foreground';
        _startLocation = _currentPosition;
        _travelPath.clear();
        if (_currentPosition != null) {
          _travelPath.add(_currentPosition!);
        }
      });

      // Start location service tracking
      _locationService!.startTracking(
        widget.authService.userId ?? '',
        widget.authService.token ?? '',
        startLocation: _startLocation,
      );

      // Start periodic location sending (sends online/active status every 5 seconds)
      _startPeriodicLocationSending();

      if (_destination != null) {
        _updateRoute();
      }

      print('Tracking started - status: ${_appStatus}');

    } else {
      // Stopping tracking - send offline status FIRST while still tracking
      print('Stopping tracking - sending offline status...');

      if (_currentPosition != null) {
        try {
          // Send offline status immediately before stopping anything
          await _sendOfflineStatus();
          print('Offline status sent successfully');
        } catch (e) {
          print('Error sending offline status: $e');
        }
      }

      // Now stop all tracking services
      _locationService!.stopTracking(widget.authService.userId);
      _stopPeriodicLocationSending();

      // Update state to stopped
      setState(() {
        _isTracking = false;
        _appStatus = 'offline';
        _startLocation = null;
        _travelPath.clear();
        _destination = null;
        _etaToDestination = null;
        _distanceToDestination = null;
        _polylines = {};
      });

      // Reset map view
      if (_mapController != null && _currentPosition != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(_currentPosition!, 14),
        );
      }

      print('Tracking stopped - status: ${_appStatus}');
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Welcome, ${widget.authService.userName ?? "User"}',
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
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
          // Add a status indicator for location sending
          if (_isTracking)
            Container(
              margin: const EdgeInsets.only(right: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _locationSendingActive ? Colors.green : Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Live',
                    style: TextStyle(fontSize: 12, color: Colors.white),
                  ),
                ],
              ),
            ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              // Stop all tracking services first
              _locationService?.stopTracking(widget.authService.userId);
              _stopPeriodicLocationSending();

              // Send offline status before logout if we have current position
              if (_currentPosition != null) {
                await _sendOfflineStatus();
              }

              // Then logout

              widget.authService.logout();

              Navigator.pushReplacementNamed(context, '/user/login');
            },
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
        child: Column(
          children: [
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

            // Add status info about location sending
            if (_isTracking)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                color: _locationSendingActive ? Colors.green.shade100 : Colors.red.shade100,
                child: Row(
                  children: [
                    Icon(
                      _locationSendingActive ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: _locationSendingActive ? Colors.green : Colors.red,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _locationSendingActive
                          ? 'Sending location every 5 seconds'
                          : 'Location sending stopped',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                    const Spacer(),
                    if (_lastLocationSent != null)
                      Text(
                        'Last: ${_lastLocationSent!.toString().substring(11, 19)}',
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                  ],
                ),
              ),

            Expanded(
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: _currentPosition ?? const LatLng(13.0827, 80.2707), // Chennai
                  zoom: 14,
                ),
                markers: {
                  if (_startLocation != null && _isTracking)
                    Marker(
                      markerId: const MarkerId('start'),
                      position: _startLocation!,
                      infoWindow: const InfoWindow(title: 'Start Location'),
                      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                    ),
                  if (_currentPosition != null)
                    Marker(
                      markerId: const MarkerId('current'),
                      position: _currentPosition!,
                      infoWindow: InfoWindow(
                        title: 'Current Location',
                        snippet: _speed != null
                            ? 'Speed: ${_speed!.toStringAsFixed(1)} km/h'
                            : 'Speed: Unavailable',
                      ),
                      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
                    ),
                  if (_destination != null)
                    Marker(
                      markerId: const MarkerId('destination'),
                      position: _destination!,
                      infoWindow: InfoWindow(
                        title: 'Destination',
                        snippet: _etaToDestination != null && _distanceToDestination != null
                            ? 'Distance: $_distanceToDestination, ETA: $_etaToDestination'
                            : 'Distance and ETA: Unavailable',
                      ),
                      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                    ),
                },
                polylines: _polylines,
                onMapCreated: (controller) {
                  _mapController = controller;
                  if (_currentPosition != null) {
                    controller.animateCamera(CameraUpdate.newLatLngZoom(_currentPosition!, 14));
                  }
                },
                myLocationEnabled: _permissionsGranted,
                myLocationButtonEnabled: _permissionsGranted,
                onCameraMove: (position) {
                  _currentZoom = position.zoom; // Update zoom level
                },
              ),
            ),
            Card(
              margin: const EdgeInsets.all(8.0),
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.speed, size: 20, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text(
                          _speed != null
                              ? 'Current Speed: ${_speed!.toStringAsFixed(1)} km/h'
                              : 'Current Speed: Unavailable',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Location sending status
                    if (_isTracking)
                      Container(
                        padding: const EdgeInsets.all(8),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: _locationSendingActive ? Colors.green.shade50 : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _locationSendingActive ? Colors.green.shade200 : Colors.red.shade200,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _locationSendingActive ? Icons.cloud_upload : Icons.cloud_off,
                              size: 16,
                              color: _locationSendingActive ? Colors.green : Colors.red,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _locationSendingActive
                                  ? 'Location streaming active'
                                  : 'Location streaming inactive',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: _locationSendingActive ? Colors.green.shade700 : Colors.red.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),

                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.route, size: 18, color: Colors.blue),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Distance: ${_distanceToDestination ?? 'N/A'}',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  const Icon(Icons.access_time, size: 18, color: Colors.green),
                                  const SizedBox(width: 8),
                                  Text(
                                    'ETA: ${_etaToDestination ?? 'N/A'}',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _permissionsGranted
                                ? _handleTrackingToggle
                                : _requestAllPermissions,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isTracking ? Colors.red : Colors.green,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: Text(_isTracking ? 'Stop Tracking' : 'Start Tracking'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => HistoryScreen(userId: widget.authService.userId ?? ''),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('View History'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
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
      appBar: AppBar(
        title: const Text('Travel History'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue, Colors.purple],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: FutureBuilder<List<dynamic>>(
        future: Provider.of<ApiService>(context, listen: false)
            .getUserHistory(userId, authService.token ?? ''),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No history available'));
          }
          final history = snapshot.data!;
          return ListView.builder(
            itemCount: history.length,
            itemBuilder: (context, index) {
              final entry = history[index] as Map<String, dynamic>;
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  title: Text(entry['date'] ?? 'Unknown Date'),
                  subtitle: Text(
                    'Distance: ${entry['distance'] ?? 'N/A'} km, Time: ${entry['timeTaken'] ?? 'N/A'}',
                  ),
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
    return Scaffold(
      appBar: AppBar(
        title: Text('Route on ${entry['date'] ?? 'Unknown Date'}'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue, Colors.purple],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: path.isEmpty
          ? const Center(child: Text('No route data available'))
          : GoogleMap(
        initialCameraPosition: CameraPosition(
          target: path.isNotEmpty
              ? LatLng(
            (path[0]['latitude'] as num?)?.toDouble() ?? 13.0827,
            (path[0]['longitude'] as num?)?.toDouble() ?? 80.2707,
          )
              : const LatLng(13.0827, 80.2707),
          zoom: 14,
        ),
        polylines: {
          Polyline(
            polylineId: const PolylineId('history_route'),
            points: path
                .where((point) => point != null && point['latitude'] != null && point['longitude'] != null)
                .map((point) => LatLng(
              (point['latitude'] as num?)?.toDouble() ?? 0.0,
              (point['longitude'] as num?)?.toDouble() ?? 0.0,
            ))
                .toList(),
            color: Colors.blue,
            width: 5,
          ),
        },
        markers: {
          if (path.isNotEmpty && path[0]['latitude'] != null && path[0]['longitude'] != null)
            Marker(
              markerId: const MarkerId('start'),
              position: LatLng(
                (path[0]['latitude'] as num?)?.toDouble() ?? 0.0,
                (path[0]['longitude'] as num?)?.toDouble() ?? 0.0,
              ),
              infoWindow: const InfoWindow(title: 'Start'),
            ),
          if (path.isNotEmpty && path.last['latitude'] != null && path.last['longitude'] != null)
            Marker(
              markerId: const MarkerId('end'),
              position: LatLng(
                (path.last['latitude'] as num?)?.toDouble() ?? 0.0,
                (path.last['longitude'] as num?)?.toDouble() ?? 0.0,
              ),
              infoWindow: const InfoWindow(title: 'End'),
            ),
        },
      ),
    );
  }
}