import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:passkeys/authenticator.dart';
import 'package:passkeys/types.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user.dart';

class AuthService {
  static const String baseUrl =
      'https://recordings-dealtime-sort-ray.trycloudflare.com/api';
  static const String tokenKey = 'auth_token';
  static const String userKey = 'user_data';
  static final PasskeyAuthenticator _authenticator = PasskeyAuthenticator();
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

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

  // Store user data and token
  static Future<void> _storeAuthData(String token, User user) async {
    // Store token securely
    await _secureStorage.write(key: tokenKey, value: token);

    // Store user data in SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(userKey, json.encode(user.toJson()));
  }

  // Clear stored auth data
  static Future<void> logout() async {
    // Clear secure token
    await _secureStorage.delete(key: tokenKey);

    // Clear user data
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(userKey);
  }

  // Get auth token
  static Future<String?> getToken() async {
    return await _secureStorage.read(key: tokenKey);
  }

  // Check if device supports passkeys
  static Future<bool> isPasskeySupported() async {
    try {
      if (kIsWeb) {
        final availability = await _authenticator.getAvailability().web();
        return availability.hasPasskeySupport;
      } else if (Platform.isIOS) {
        final availability = await _authenticator.getAvailability().iOS();
        return availability.hasPasskeySupport;
      } else if (Platform.isAndroid) {
        final availability = await _authenticator.getAvailability().android();
        return availability.hasPasskeySupport;
      }
      return false;
    } catch (e) {
      print('Error checking passkey support: $e');
      return false;
    }
  }

  // Register new user with passkey
  static Future<AuthResponse> register(String email, String name) async {
    try {
      // Step 1: Get registration challenge from server
      final challengeResponse = await http.post(
        Uri.parse('$baseUrl/auth/register/begin'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email, 'name': name}),
      );

      if (challengeResponse.statusCode != 200) {
        final error = json.decode(challengeResponse.body);
        return AuthResponse(success: false, message: error['message']);
      }

      final challengeData = json.decode(challengeResponse.body);

      // Debug: Log what we received from server
      print('Registration challenge received:');
      print(
          '- authenticatorSelection: ${challengeData['authenticatorSelection']}');
      if (challengeData['authenticatorSelection'] != null) {
        print(
            '  - residentKey: ${challengeData['authenticatorSelection']['residentKey']}');
        print(
            '  - requireResidentKey: ${challengeData['authenticatorSelection']['requireResidentKey']}');
        print(
            '  - userVerification: ${challengeData['authenticatorSelection']['userVerification']}');
      }

      // Helper function to convert Buffer object to Base64URL string
      String convertToBase64Url(dynamic value) {
        if (value is String) {
          return value;
        } else if (value is Map && value.containsKey('data')) {
          // Convert byte array to Base64URL
          final bytes = List<int>.from(value['data'] as List);
          return base64Url.encode(bytes).replaceAll('=', '');
        }
        throw Exception('Invalid format for Base64URL conversion');
      }

      // Step 2: Create passkey using Flutter passkeys package
      final registrationRequest = RegisterRequestType(
        challenge: challengeData['challenge'] as String,
        relyingParty: RelyingPartyType(
          id: challengeData['rp']['id'] as String,
          name: challengeData['rp']['name'] as String,
        ),
        user: UserType(
          id: convertToBase64Url(challengeData['user']['id']),
          name: email,
          displayName: name,
        ),
        pubKeyCredParams: (challengeData['pubKeyCredParams'] as List?)
                ?.map((param) => PubKeyCredParamType(
                      type: param['type'] as String,
                      alg: param['alg'] as int,
                    ))
                .toList() ??
            [
              PubKeyCredParamType(type: 'public-key', alg: -7), // ES256
              PubKeyCredParamType(type: 'public-key', alg: -257), // RS256
            ],
        excludeCredentials: (challengeData['excludeCredentials'] as List?)
                ?.map((cred) => CredentialType(
                      type: cred['type'] as String,
                      id: convertToBase64Url(cred['id']),
                      transports: List<String>.from(cred['transports'] ?? []),
                    ))
                .toList() ??
            [],
        // CRITICAL: Pass authSelectionType to ensure resident key is created
        authSelectionType: challengeData['authenticatorSelection'] != null
            ? AuthenticatorSelectionType(
                residentKey: (challengeData['authenticatorSelection']
                        ['residentKey'] as String?) ??
                    'required',
                requireResidentKey: challengeData['authenticatorSelection']
                        ['requireResidentKey'] as bool? ??
                    false,
                userVerification: (challengeData['authenticatorSelection']
                        ['userVerification'] as String?) ??
                    'preferred',
              )
            : AuthenticatorSelectionType(
                residentKey: 'required',
                requireResidentKey: true,
                userVerification: 'preferred',
              ),
      );

      final registrationResult = await _authenticator.register(
        registrationRequest,
      );

      // Step 3: Send registration result to server
      final registerResponse = await http.post(
        Uri.parse('$baseUrl/auth/register/complete'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email,
          'id': registrationResult.id,
          'rawId': registrationResult.rawId,
          'response': {
            'clientDataJSON': registrationResult.clientDataJSON,
            'attestationObject': registrationResult.attestationObject,
          },
          'type': 'public-key',
          'challengeId': challengeData['challengeId'],
        }),
      );

      if (registerResponse.statusCode == 201) {
        final responseData = json.decode(registerResponse.body);
        final user = User.fromJson(responseData['user']);
        await _storeAuthData(responseData['token'], user);
        return AuthResponse(
            success: true, user: user, token: responseData['token']);
      } else {
        final error = json.decode(registerResponse.body);
        return AuthResponse(success: false, message: error['message']);
      }
    } catch (e) {
      print('Registration error: $e');
      return AuthResponse(success: false, message: 'Registration failed: $e');
    }
  }

  // Sign in with passkey
  static Future<AuthResponse> signIn(String email) async {
    try {
      // Step 1: Get authentication challenge from server with email
      final challengeResponse = await http.post(
        Uri.parse('$baseUrl/auth/signin/begin'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email}),
      );

      if (challengeResponse.statusCode != 200) {
        final error = json.decode(challengeResponse.body);
        return AuthResponse(success: false, message: error['message']);
      }

      final challengeData = json.decode(challengeResponse.body);

      // Step 2: Authenticate using passkey
      // Use allowCredentials from server to help Android find the specific passkey
      final authRequest = AuthenticateRequestType(
        relyingPartyId: challengeData['rpId'],
        challenge: challengeData['challenge'],
        mediation: MediationType.Optional,
        preferImmediatelyAvailableCredentials: true,
        allowCredentials: (challengeData['allowCredentials'] as List?)
            ?.map((cred) => CredentialType(
                  type: cred['type'] as String,
                  id: cred['id'] as String,
                  transports: (cred['transports'] as List?)
                          ?.map((t) => t as String)
                          .toList() ??
                      [],
                ))
            .toList(),
      );

      final authResult = await _authenticator.authenticate(
        authRequest,
      );

      // Step 3: Send authentication result to server
      final signInResponse = await http.post(
        Uri.parse('$baseUrl/auth/signin/complete'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'id': authResult.id,
          'rawId': authResult.rawId,
          'response': {
            'clientDataJSON': authResult.clientDataJSON,
            'authenticatorData': authResult.authenticatorData,
            'signature': authResult.signature,
            'userHandle': authResult.userHandle,
          },
          'type': 'public-key',
          'challengeId': challengeData['challengeId'],
        }),
      );

      if (signInResponse.statusCode == 200) {
        final responseData = json.decode(signInResponse.body);
        final user = User.fromJson(responseData['user']);
        await _storeAuthData(responseData['token'], user);
        return AuthResponse(
            success: true, user: user, token: responseData['token']);
      } else {
        final error = json.decode(signInResponse.body);
        return AuthResponse(success: false, message: error['message']);
      }
    } catch (e) {
      print('Sign in error: $e');
      return AuthResponse(success: false, message: 'Sign in failed: $e');
    }
  }
}
