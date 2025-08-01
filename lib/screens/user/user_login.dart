
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:trainer_track_2/screens/services/auth_service.dart';
import 'user_dashboard.dart';

class UserLoginScreen extends StatefulWidget {
const UserLoginScreen({super.key});

@override
_UserLoginScreenState createState() => _UserLoginScreenState();
}

class _UserLoginScreenState extends State<UserLoginScreen> {
final _formKey = GlobalKey<FormState>();
final _usernameController = TextEditingController();
final _passwordController = TextEditingController();
String? _errorMessage;

@override
Widget build(BuildContext context) {
final authService = Provider.of<AuthService>(context);

return Scaffold(
appBar: AppBar(title: const Text('User Login')),
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
await authService.userLogin(
_usernameController.text,
_passwordController.text,
);
Navigator.pushReplacement(
context,
MaterialPageRoute(
builder: (context) => UserDashboardScreen(authService: authService),
),
);
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
Navigator.pushNamed(context, '/admin/login');
},
child: const Text('Switch to Admin Login'),
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
