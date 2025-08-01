import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'api_service.dart';

class AuthService with ChangeNotifier {
  String? _userId;
  String? _userName;
  bool _isAdminLoggedIn = false;
  String? _token;

  String? get userId => _userId;
  String? get userName => _userName;
  bool get isAdminLoggedIn => _isAdminLoggedIn;
  String? get token => _token;

  Future<bool> adminLogin(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('http://10.105.76.61:3000/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
          'isAdmin': true,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _userId = data['userId'] as String?;
        _userName = data['name'] as String?;
        _isAdminLoggedIn = true;
        _token = data['token'] as String?;
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> userLogin(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('http://10.105.76.61:3000/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
          'isAdmin': false,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _userId = data['userId'] as String?;
        _userName = data['name'] as String?;
        _isAdminLoggedIn = false;
        _token = data['token'] as String?;
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  void logout() {
    _userId = null;
    _userName = null;
    _isAdminLoggedIn = false;
    _token = null;
    notifyListeners();
  }
}