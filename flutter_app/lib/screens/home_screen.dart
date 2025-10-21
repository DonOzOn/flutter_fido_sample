import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../models/user.dart';
import 'auth_screen.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  User? _currentUser;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final user = await AuthService.getCurrentUser();
      setState(() {
        _currentUser = user;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Logout'),
        content: Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await AuthService.logout();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => AuthScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Welcome'),
        actions: [
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: _handleLogout,
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.verified_user,
                size: 100,
                color: Colors.green,
              ),
              SizedBox(height: 32),
              Text(
                'Authentication Successful!',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 16),
              if (_currentUser != null) ...[
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'User Information',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        SizedBox(height: 16),
                        ListTile(
                          leading: Icon(Icons.person),
                          title: Text('Name'),
                          subtitle: Text(_currentUser!.name),
                        ),
                        ListTile(
                          leading: Icon(Icons.email),
                          title: Text('Email'),
                          subtitle: Text(_currentUser!.email),
                        ),
                        ListTile(
                          leading: Icon(Icons.calendar_today),
                          title: Text('Member Since'),
                          subtitle: Text(
                            '${_currentUser!.createdAt.day}/${_currentUser!.createdAt.month}/${_currentUser!.createdAt.year}',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              SizedBox(height: 32),
              Text(
                'You have successfully authenticated using FIDO2 passkeys!',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
