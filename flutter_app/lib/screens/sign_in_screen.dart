import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';

class SignInScreen extends StatefulWidget {
  final VoidCallback? onNavigateToSignUp;

  const SignInScreen({Key? key, this.onNavigateToSignUp}) : super(key: key);

  @override
  _SignInScreenState createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
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
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_passkeySupported) {
      _showErrorDialog('Passkeys are not supported on this device');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await AuthService.signIn(_emailController.text.trim());

      if (result.success) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => HomeScreen()),
          );
        }
      } else {
        _showErrorDialog(result.message ?? 'Sign in failed');
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
            Icons.fingerprint,
            size: 80,
            color: Theme.of(context).primaryColor,
          ),
          SizedBox(height: 32),
          Text(
            'Sign in with your passkey',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 32),
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
              onPressed: _isLoading ? null : _handleSignIn,
              child: _isLoading
                  ? CircularProgressIndicator(color: Colors.white)
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.fingerprint),
                        SizedBox(width: 8),
                        Text('Sign In with Passkey'),
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
          if (widget.onNavigateToSignUp != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "Don't have an account? ",
                  style: TextStyle(fontSize: 16),
                ),
                TextButton(
                  onPressed: widget.onNavigateToSignUp,
                  child: Text(
                    'Sign Up',
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
