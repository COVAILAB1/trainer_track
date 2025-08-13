import 'dart:async';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'api_service.dart';

class LocationService with ChangeNotifier {
  bool isTracking = false;
  Position? currentPosition;
  List<Position> path = [];
  Position? startPosition;
  String? _userId;
  String? _token;
  StreamSubscription<Position>? _positionStreamSubscription;
  DateTime _lastUpdate = DateTime.now();
  final Duration _updateInterval = const Duration(seconds: 3); // Throttle UI updates

  static const String notificationChannelId = 'location_channel';
  static const int notificationId = 888;

  static Future<void> initializeBackgroundService() async {
    final service = FlutterBackgroundService();

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      notificationChannelId,
      'Location Tracking Service',
      description: 'This channel is used for location tracking notifications.',
      importance: Importance.low,
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: notificationChannelId,
        initialNotificationTitle: 'Location Tracking',
        initialNotificationContent: 'Tracking your location in the background',
        foregroundServiceNotificationId: notificationId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  static Future<bool> onIosBackground(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();
    return true;
  }

  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();
    String? userId;
    String? token;
    Position? startPos;
    bool isFirstUpdate = true;

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

    if (service is AndroidServiceInstance) {
      service.on('updateUserId').listen((event) {
        userId = event?['userId'] as String?;
        token = event?['token'] as String?;
        final startLat = event?['startLatitude'] as double?;
        final startLng = event?['startLongitude'] as double?;
        if (startLat != null && startLng != null) {
          startPos = Position(
            latitude: startLat,
            longitude: startLng,
            timestamp: DateTime.now(),
            accuracy: 0,
            altitude: 0,
            altitudeAccuracy: 0,
            heading: 0,
            headingAccuracy: 0,
            speed: 0,
            speedAccuracy: 0,
          );
        }
        isFirstUpdate = true;
      });

      service.on('stopService').listen((event) {
        service.stopSelf();
      });
    }

    final positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update every 10 meters
      ),
    );

    await for (final position in positionStream) {
      if (!await Geolocator.isLocationServiceEnabled()) {
        continue;
      }

      try {
        if (userId != null && token != null) {
          final locationData = {
            'userId': userId,
            'latitude': position.latitude,
            'longitude': position.longitude,
            'speed': position.speed ?? 0.0,
            'accuracy': position.accuracy,
            'timestamp': DateTime.now().toIso8601String(),
            'date': DateTime.now().toIso8601String().split('T')[0],
            'isStartLocation': false,
          };

          if (isFirstUpdate && startPos != null) {
            locationData['startLatitude'] = startPos!.latitude;
            locationData['startLongitude'] = startPos!.longitude;
            locationData['isStartLocation'] = true;
            isFirstUpdate = false;
          }

          await ApiService().sendLocationData(locationData, token!);

          if (service is AndroidServiceInstance && await service.isForegroundService()) {
            flutterLocalNotificationsPlugin.show(
              notificationId,
              'Location Tracking',
              'Speed: ${(position.speed * 3.6).toStringAsFixed(1)} km/h',
              const NotificationDetails(
                android: AndroidNotificationDetails(
                  notificationChannelId,
                  'Location Tracking Service',
                  importance: Importance.low,
                  ongoing: true,
                ),
              ),
            );
          }
        }
      } catch (e) {
        print('Error sending location in background: $e');
      }
    }
  }
  static Future<void> _sendTrackingStartedNotification(String userId) async {
    const String apiUrl = 'https://trainer-backend-soj9.onrender.com/api/tracking-started';

    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'userId': userId,
          'message': 'Tracking started',
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode == 200) {
        print('Tracking started notification sent successfully');
      }
    } catch (e) {
      print('Error sending tracking notification: $e');
    }
  }

  void startTracking(String userId, String token, {LatLng? startLocation}) async {
    if (isTracking) return;
    await _sendTrackingStartedNotification(userId);
    isTracking = true;
    _userId = userId;
    _token = token;
    path.clear();

    if (startLocation != null) {
      startPosition = Position(
        latitude: startLocation.latitude,
        longitude: startLocation.longitude,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
    } else {
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        startPosition = position;
      } catch (e) {
        print('Error setting start position: $e');
      }
    }

    final service = FlutterBackgroundService();
    await service.startService();

    final serviceData = {
      'userId': userId,
      'token': token,
      if (startPosition != null) 'startLatitude': startPosition!.latitude,
      if (startPosition != null) 'startLongitude': startPosition!.longitude,
    };

    service.invoke('updateUserId', serviceData);

    // Start foreground tracking with a single stream
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update every 10 meters
      ),
    ).listen(
          (Position position) {
        if (!isTracking) return;
        if (!shouldUpdate()) return; // Throttle UI updates

        currentPosition = position;
        path.add(position);
        print('Foreground location updated: ${position.latitude}, ${position.longitude}, Speed: ${position.speed}');
        notifyListeners();
      },
      onError: (e) {
        print('Foreground stream error: $e');
      },
    );

    notifyListeners();
  }

  void stopTracking(userId) {

    if (!isTracking) return;

    isTracking = false;
    _userId = null;
    _token = null;
    startPosition = null;
    path.clear();
    currentPosition = null;
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    _sendTrackingStopNotification(userId);
    final service = FlutterBackgroundService();
    service.invoke('stopService');

    notifyListeners();
  }

  bool shouldUpdate() {
    final now = DateTime.now();
    if (now.difference(_lastUpdate) >= _updateInterval) {
      _lastUpdate = now;
      return true;
    }
    return false;
  }

  Future<void> getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      currentPosition = position;
      notifyListeners();
    } catch (e) {
      print('Error getting current location: $e');
    }
  }

  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  Future<LocationPermission> checkLocationPermission() async {
    return await Geolocator.checkPermission();
  }

  Future<LocationPermission> requestLocationPermission() async {
    return await Geolocator.requestPermission();
  }

  LatLng? get startLocationLatLng {
    return startPosition != null
        ? LatLng(startPosition!.latitude, startPosition!.longitude)
        : null;
  }

  LatLng? get currentLocationLatLng {
    return currentPosition != null
        ? LatLng(currentPosition!.latitude, currentPosition!.longitude)
        : null;
  }

  List<LatLng> get travelPathLatLng {
    return path.map((pos) => LatLng(pos.latitude, pos.longitude)).toList();
  }

  double get distanceTraveled {
    if (startPosition == null || currentPosition == null) return 0.0;

    return Geolocator.distanceBetween(
      startPosition!.latitude,
      startPosition!.longitude,
      currentPosition!.latitude,
      currentPosition!.longitude,
    ) / 1000.0;
  }

  double get totalPathDistance {
    if (path.length < 2) return 0.0;

    double totalDistance = 0.0;
    for (int i = 1; i < path.length; i++) {
      totalDistance += Geolocator.distanceBetween(
        path[i - 1].latitude,
        path[i - 1].longitude,
        path[i].latitude,
        path[i].longitude,
      );
    }
    return totalDistance / 1000.0;
  }

  Future<void> _sendTrackingStopNotification(String? userId) async {
    const String apiUrl = 'https://trainer-backend-soj9.onrender.com/api/tracking-stopped';

    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'userId': userId,
          'message': 'Tracking stopped',
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );

    } catch (e) {
      print('Error sending tracking notification: $e');
    }
  }
}