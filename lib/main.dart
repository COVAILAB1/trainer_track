import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/admin/admin_login.dart';
import 'screens/user/user_login.dart';
import 'screens/services/auth_service.dart';
import 'screens/services/location_service.dart';
import 'screens/services/api_service.dart';

void main() async {
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
        title: 'Location Tracking App',
        initialRoute: '/',
        routes: {
          '/': (context) => Consumer<AuthService>(
            builder: (context, auth, _) =>
            auth.isAdminLoggedIn ? const AdminLoginScreen() : const UserLoginScreen(),
          ),
          '/admin/login': (context) => const AdminLoginScreen(),
          '/user/login': (context) => const UserLoginScreen(),
        },
      ),
    );
  }
}