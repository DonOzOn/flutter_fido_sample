# Keycloak FIDO2 Authentication Setup

## Quick Start

### 1. Start Keycloak Server
```bash
cd /Users/apple/Documents/NCB/fido_demo/keycloak_server
docker-compose up -d
```

### 2. Access Keycloak Admin Console
- URL: http://localhost:8080
- Username: `admin`
- Password: `admin`

### 3. Configure FIDO2/WebAuthn

#### Create Realm
1. Click "Create Realm"
2. Name: `fido-demo`
3. Click "Create"

#### Enable WebAuthn
1. Go to Realm Settings → Security Defenses
2. Enable "WebAuthn Passwordless"
3. Configure:
   - Relying Party ID: `localhost` (hoặc domain của bạn)
   - Relying Party Name: `FIDO2 Demo`
   - User Verification: `required` (bắt buộc Face ID/Touch ID)
   - Authenticator Attachment: `platform` (dùng thiết bị)

#### Create Client for Flutter App
1. Go to Clients → Create Client
2. Client type: `OpenID Connect`
3. Client ID: `flutter-app`
4. Client authentication: OFF (public client)
5. Valid redirect URIs:
   - `com.example.fidodemo://oauth2redirect`
   - `http://localhost:*`
6. Web origins: `*`
7. Save

#### Configure Authentication Flow
1. Go to Authentication → Flows
2. Create new flow: `WebAuthn Passwordless Flow`
3. Add executions:
   - Username Form
   - WebAuthn Passwordless Authenticator
4. Set as default for Browser flow

#### Create Test User
1. Go to Users → Add User
2. Username: `testuser@example.com`
3. Save
4. Go to Credentials tab
5. Click "Set up WebAuthn Passwordless"

## Flutter App Configuration

Update `auth_service.dart`:
```dart
static const String keycloakUrl = 'http://localhost:8080';
static const String realm = 'fido-demo';
static const String clientId = 'flutter-app';
```

## Architecture

```
Flutter App
    ↓ OAuth2/OIDC Authorization Code Flow
Keycloak
    ↓ WebAuthn Challenge
Device Biometrics (Face ID/Touch ID)
```

## API Endpoints

- Authorization: `http://localhost:8080/realms/fido-demo/protocol/openid-connect/auth`
- Token: `http://localhost:8080/realms/fido-demo/protocol/openid-connect/token`
- UserInfo: `http://localhost:8080/realms/fido-demo/protocol/openid-connect/userinfo`
- Logout: `http://localhost:8080/realms/fido-demo/protocol/openid-connect/logout`

## Troubleshooting

### Keycloak not starting
```bash
docker-compose logs -f keycloak
```

### Reset Keycloak data
```bash
docker-compose down -v
docker-compose up -d
```
