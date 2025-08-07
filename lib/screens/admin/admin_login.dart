
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:trainer_track_2/screens/services/auth_service.dart';
import 'admin_dashboard.dart';

class AdminLoginScreen extends StatefulWidget {
const AdminLoginScreen({super.key});

@override
_AdminLoginScreenState createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
final _formKey = GlobalKey<FormState>();
final _usernameController = TextEditingController();
final _passwordController = TextEditingController();
String? _errorMessage;

@override
Widget build(BuildContext context) {
final authService = Provider.of<AuthService>(context);

return Scaffold(
appBar: AppBar(title: const Text('Admin Login')),
body: Padding(
padding: const EdgeInsets.all(16.0),
child: Form(
key: _formKey,
child: Column(
children: [
TextFormField(
controller: _usernameController,
decoration: const InputDecoration(labelText: 'Username'),
validator: (value) => value == null || value.isEmpty ? 'Required' : null,
),
TextFormField(
controller: _passwordController,
decoration: const InputDecoration(labelText: 'Password'),
obscureText: true,
validator: (value) => value == null || value.isEmpty ? 'Required' : null,
),
if (_errorMessage != null)
Padding(
padding: const EdgeInsets.symmetric(vertical: 8.0),
child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
),
const SizedBox(height: 20),
ElevatedButton(
onPressed: () async {
if (_formKey.currentState!.validate()) {
try {
await authService.login(
_usernameController.text,
_passwordController.text,
);
if (authService.isAdminLoggedIn) {
Navigator.pushReplacement(
context,
MaterialPageRoute(
builder: (context) => AdminDashboardScreen(authService: authService),
),
);
} else {
setState(() {
_errorMessage = 'Admin access required';
});
}
} catch (e) {
setState(() {
_errorMessage = e.toString().replaceFirst('Exception: ', '');
});
}
}
},
child: const Text('Login'),
),
TextButton(
onPressed: () {
Navigator.pushNamed(context, '/user/login');
},
child: const Text('Switch to User Login'),
),
],
),
),
),
);
}

@override
void dispose() {
_usernameController.dispose();
_passwordController.dispose();
super.dispose();
}
}
