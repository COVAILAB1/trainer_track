
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../user/user_login.dart';


class AuthService with ChangeNotifier {
String? _userId;
String? _userName;
bool _isAdminLoggedIn = false;
String? _token;
final String _baseUrl ='https://trainer-backend-soj9.onrender.com';

String? get userId => _userId;
String? get userName => _userName;
bool get isAdminLoggedIn => _isAdminLoggedIn;
bool get isUserLoggedIn => _token != null && !_isAdminLoggedIn;
String? get token => _token;

Future<void> login(String username, String password) async {
try {
final response = await http.post(
Uri.parse('$_baseUrl/login'),
headers: {'Content-Type': 'application/json'},
body: jsonEncode({
'username': username,
'password': password,
}),
);
if (response.statusCode == 200) {
final data = jsonDecode(response.body) as Map<String, dynamic>;
_userId = data['userId'] as String?;
_userName = username;
_isAdminLoggedIn = data['isAdmin'] as bool? ?? false;
_token = data['token'] as String?;
if (_userId == null || _token == null) {
throw Exception('Invalid response: missing userId or token');
}
notifyListeners();
} else {
throw Exception('Login failed: ${response.statusCode}');
}
} catch (e) {
throw Exception('Login error: $e');
}
}

Future<void> logout() async {
  await UserLoginScreen.logout();
_userId = null;
_userName = null;
_isAdminLoggedIn = false;
_token = null;
notifyListeners();
}
}
