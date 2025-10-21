import 'package:flutter/material.dart';
import 'sign_in_screen.dart';
import 'sign_up_screen.dart';

class AuthScreen extends StatelessWidget {
  const AuthScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FIDO2 Authentication'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SignInScreen(
          onNavigateToSignUp: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => Scaffold(
                  appBar: AppBar(
                    title: const Text('Sign Up'),
                  ),
                  body: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SignUpScreen(),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
