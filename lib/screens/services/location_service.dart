
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'api_service.dart';

class LocationService with ChangeNotifier {
bool isTracking = false;
Position? currentPosition;
List<Position> path = [];
String? _userId;
String? _token;

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

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

if (service is AndroidServiceInstance) {
service.on('updateUserId').listen((event) {
userId = event?['userId'] as String?;
token = event?['token'] as String?;
});
service.on('stopService').listen((event) {
service.stopSelf();
});
}

while (true) {
if (!await Geolocator.isLocationServiceEnabled()) {
await Future.delayed(const Duration(seconds: 30));
continue;
}
final position = await Geolocator.getCurrentPosition(
desiredAccuracy: LocationAccuracy.high,
);

if (userId != null && token != null) {
await ApiService().sendLocationData(
{
'userId': userId,
'latitude': position.latitude,
'longitude': position.longitude,
'speed': position.speed,
'timestamp': DateTime.now().toIso8601String(),
},
token!,
);

if (service is AndroidServiceInstance && await service.isForegroundService()) {
flutterLocalNotificationsPlugin.show(
notificationId,
'Location Tracking',
'Tracking at ${DateTime.now()}',
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
await Future.delayed(const Duration(seconds: 10));
}
}

void startTracking(String userId, String token) async {
if (!isTracking) {
isTracking = true;
_userId = userId;
_token = token;
path.clear();
final service = FlutterBackgroundService();
await service.startService();
service.invoke('updateUserId', {'userId': userId, 'token': token});
_startForegroundTracking(userId, token);
notifyListeners();
}
}

void stopTracking() async {
if (isTracking) {
isTracking = false;
_userId = null;
_token = null;
final service = FlutterBackgroundService();
service.invoke('stopService');
notifyListeners();
}
}

void _startForegroundTracking(String userId, String token) async {
while (isTracking) {
final position = await Geolocator.getCurrentPosition(
desiredAccuracy: LocationAccuracy.high,
);
currentPosition = position;
path.add(position);
await ApiService().sendLocationData(
{
'userId': userId,
'latitude': position.latitude,
'longitude': position.longitude,
'speed': position.speed,
'timestamp': DateTime.now().toIso8601String(),
},
token,
);
notifyListeners();
await Future.delayed(const Duration(seconds: 10));
}
}
}