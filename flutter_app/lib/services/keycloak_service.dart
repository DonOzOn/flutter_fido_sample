import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import '../models/user.dart';

class KeycloakService {
  // Keycloak Configuration
  static const String keycloakUrl = 'http://192.168.1.6:8080';
  static const String realm = 'fido-demo';
  static const String clientId = 'flutter-app';
  static const String redirectUri = 'com.example.fidodemo://oauth2redirect';

  // Storage keys
  static const String tokenKey = 'keycloak_access_token';
  static const String refreshTokenKey = 'keycloak_refresh_token';
  static const String userKey = 'keycloak_user_data';

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static final FlutterAppAuth _appAuth = FlutterAppAuth();
  // Keycloak endpoints
  static String get _issuer => '$keycloakUrl/realms/$realm';
  static String get _authorizationEndpoint =>
      '$_issuer/protocol/openid-connect/auth';
  static String get _tokenEndpoint => '$_issuer/protocol/openid-connect/token';
  static String get _endSessionEndpoint =>
      '$_issuer/protocol/openid-connect/logout';

  // Check if user is logged in
  static Future<bool> isLoggedIn() async {
    final token = await _secureStorage.read(key: tokenKey);
    return token != null && token.isNotEmpty;
  }

  // Get stored user data
  static Future<User?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString(userKey);
    if (userJson != null) {
      return User.fromJson(json.decode(userJson));
    }
    return null;
  }

  // Store user data and tokens
  static Future<void> _storeAuthData(
    String accessToken,
    String? refreshToken,
    Map<String, dynamic> userInfo,
  ) async {
    // Store tokens securely
    await _secureStorage.write(key: tokenKey, value: accessToken);
    if (refreshToken != null) {
      await _secureStorage.write(key: refreshTokenKey, value: refreshToken);
    }

    // Store user data
    final prefs = await SharedPreferences.getInstance();
    final user = User(
      id: userInfo['sub'] ?? '',
      email: userInfo['email'] ?? '',
      name: userInfo['name'] ?? userInfo['preferred_username'] ?? '',
      createdAt: DateTime.now(),
    );
    await prefs.setString(userKey, json.encode(user.toJson()));
  }

  // Clear stored auth data
  static Future<void> logout() async {
    final accessToken = await _secureStorage.read(key: tokenKey);
    final refreshToken = await _secureStorage.read(key: refreshTokenKey);

    if (accessToken != null) {
      try {
        // Use flutter_appauth to handle logout
        await _appAuth.endSession(EndSessionRequest(
          idTokenHint: accessToken,
          postLogoutRedirectUrl: redirectUri,
          serviceConfiguration: AuthorizationServiceConfiguration(
            authorizationEndpoint: _authorizationEndpoint,
            tokenEndpoint: _tokenEndpoint,
            endSessionEndpoint: _endSessionEndpoint,
          ),
        ));
      } catch (e) {
        if (kDebugMode) {
          print('Logout error: $e');
        }
      }
    }

    // Clear stored data
    await _secureStorage.delete(key: tokenKey);
    await _secureStorage.delete(key: refreshTokenKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(userKey);
  }

  // Get auth token
  static Future<String?> getToken() async {
    return await _secureStorage.read(key: tokenKey);
  }

  // Start OAuth2 + WebAuthn login flow
  static Future<AuthResponse> startLogin() async {
    return _startAuthFlow(isRegistration: false);
  }

  // Start OAuth2 + WebAuthn registration/sign up flow
  static Future<AuthResponse> startSignUp() async {
    return _startAuthFlow(isRegistration: true);
  }

  // Internal method to handle auth flow
  static Future<AuthResponse> _startAuthFlow(
      {required bool isRegistration}) async {
    try {
      final serviceConfiguration = AuthorizationServiceConfiguration(
        authorizationEndpoint: isRegistration
            ? '$_issuer/protocol/openid-connect/registrations'
            : _authorizationEndpoint,
        tokenEndpoint: _tokenEndpoint,
      );

      if (kDebugMode) {
        print('=== Keycloak Auth Flow Debug ===');
        print(
            'Authorization Endpoint: ${serviceConfiguration.authorizationEndpoint}');
        print('Token Endpoint: ${serviceConfiguration.tokenEndpoint}');
        print('Client ID: $clientId');
        print('Redirect URI: $redirectUri');
        print('Scopes: openid, profile, email');
        print('Is Registration: $isRegistration');
      }

      // Authorize and exchange code for token
      final AuthorizationTokenResponse? result =
          await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          clientId,
          redirectUri,
          serviceConfiguration: serviceConfiguration,
          scopes: ['openid'],
          promptValues: isRegistration ? ['create'] : null,
        ),
      );
      if (result == null) {
        return AuthResponse(
          success: false,
          message: 'Authentication cancelled',
        );
      }

      if (result.accessToken == null) {
        return AuthResponse(
          success: false,
          message: 'No access token received',
        );
      }

      // Get user info
      final userInfoUrl = '$_issuer/protocol/openid-connect/userinfo';
      final userInfoResponse = await http.get(
        Uri.parse(userInfoUrl),
        headers: {'Authorization': 'Bearer ${result.accessToken}'},
      );

      if (userInfoResponse.statusCode != 200) {
        return AuthResponse(
          success: false,
          message: 'Failed to get user info',
        );
      }

      final userInfo = json.decode(userInfoResponse.body);

      // Store auth data
      await _storeAuthData(
        result.accessToken!,
        result.refreshToken,
        userInfo,
      );

      final user = await getCurrentUser();
      return AuthResponse(
        success: true,
        message:
            isRegistration ? 'Registration successful' : 'Login successful',
        user: user,
        token: result.accessToken,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Auth flow error: $e');
      }
      return AuthResponse(
        success: false,
        message: 'Failed to ${isRegistration ? 'register' : 'login'}: $e',
      );
    }
  }

  // Refresh access token
  static Future<bool> refreshAccessToken() async {
    try {
      final refreshToken = await _secureStorage.read(key: refreshTokenKey);
      if (refreshToken == null) {
        return false;
      }

      final TokenResponse? result = await _appAuth.token(
        TokenRequest(
          clientId,
          redirectUri,
          refreshToken: refreshToken,
          serviceConfiguration: AuthorizationServiceConfiguration(
            authorizationEndpoint: _authorizationEndpoint,
            tokenEndpoint: _tokenEndpoint,
          ),
        ),
      );

      if (result == null || result.accessToken == null) {
        return false;
      }

      await _secureStorage.write(key: tokenKey, value: result.accessToken!);
      if (result.refreshToken != null) {
        await _secureStorage.write(
            key: refreshTokenKey, value: result.refreshToken!);
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Refresh token error: $e');
      }
      return false;
    }
  }
}
