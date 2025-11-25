import 'package:flutter/material.dart';
import 'screens/auth_method_screen.dart';
import 'screens/home_screen.dart';
import 'services/auth_service.dart';
import 'services/keycloak_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FIDO2 Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: FutureBuilder<bool>(
        future: _checkLogin(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          if (snapshot.data == true) {
            return HomeScreen();
          } else {
            return const AuthMethodScreen();
          }
        },
      ),
    );
  }

  Future<bool> _checkLogin() async {
    // Check both auth services
    final nodeJsLoggedIn = await AuthService.isLoggedIn();
    final keycloakLoggedIn = await KeycloakService.isLoggedIn();
    return nodeJsLoggedIn || keycloakLoggedIn;
  }
}
