import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';

class SignUpScreen extends StatefulWidget {
  @override
  _SignUpScreenState createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isLoading = false;
  bool _passkeySupported = false;

  @override
  void initState() {
    super.initState();
    _checkPasskeySupport();
  }

  Future<void> _checkPasskeySupport() async {
    final supported = await AuthService.isPasskeySupported();
    setState(() {
      _passkeySupported = supported;
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleSignUp() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_passkeySupported) {
      _showErrorDialog('Passkeys are not supported on this device');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await AuthService.register(
        _emailController.text.trim(),
        _nameController.text.trim(),
      );

      if (result.success) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => HomeScreen()),
          );
        }
      } else {
        _showErrorDialog(result.message ?? 'Sign up failed');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.person_add,
            size: 80,
            color: Theme.of(context).primaryColor,
          ),
          SizedBox(height: 32),
          Text(
            'Create your account',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 32),
          TextFormField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: 'Full Name',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your name';
              }
              return null;
            },
          ),
          SizedBox(height: 16),
          TextFormField(
            controller: _emailController,
            decoration: InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.email),
            ),
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your email';
              }
              if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                return 'Please enter a valid email';
              }
              return null;
            },
          ),
          SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleSignUp,
              child: _isLoading
                  ? CircularProgressIndicator(color: Colors.white)
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.fingerprint),
                        SizedBox(width: 8),
                        Text('Sign Up with Passkey'),
                      ],
                    ),
            ),
          ),
          if (!_passkeySupported)
            Container(
              margin: EdgeInsets.only(top: 16),
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Passkeys are not supported on this device',
                      style: TextStyle(color: Colors.orange.shade800),
                    ),
                  ),
                ],
              ),
            ),
          SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Already have an account? ',
                style: TextStyle(fontSize: 16),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text(
                  'Sign In',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
