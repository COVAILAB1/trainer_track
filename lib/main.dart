import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/admin/admin_login.dart';
import 'screens/user/user_login.dart';
import 'screens/admin/admin_dashboard.dart';
import 'screens/user/user_dashboard.dart';
import 'screens/services/auth_service.dart';
import 'screens/services/location_service.dart';
import 'screens/services/api_service.dart';

Future<void> main() async {
WidgetsFlutterBinding.ensureInitialized();
await LocationService.initializeBackgroundService();
runApp(const MyApp());
}

class MyApp extends StatelessWidget {
const MyApp({super.key});

@override
Widget build(BuildContext context) {
return MultiProvider(
providers: [
ChangeNotifierProvider(create: (_) => AuthService()),
ChangeNotifierProvider(create: (_) => LocationService()),
ChangeNotifierProvider(create: (_) => ApiService()),
],
child: MaterialApp(
  debugShowCheckedModeBanner: false,
title: 'Location Tracking App',
initialRoute: '/',
routes: {
'/': (context) => Consumer<AuthService>(
builder: (context, auth, _) => auth.isAdminLoggedIn
? AdminDashboardScreen(authService: auth)
    : auth.isUserLoggedIn
? UserDashboardScreen(authService: auth)
    : const UserLoginScreen(),
),
'/admin/login': (context) => const AdminLoginScreen(),
'/user/login': (context) => const UserLoginScreen(),
'/admin/dashboard': (context) => AdminDashboardScreen(authService: Provider.of<AuthService>(context)),
},
),
);
}
}
