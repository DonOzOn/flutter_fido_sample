# Setup Keycloak with ngrok for Mobile Testing

## Why ngrok?
- WebAuthn/FIDO2 requires HTTPS in production
- Mobile devices can't access localhost
- ngrok provides a public HTTPS URL that tunnels to your local Keycloak

## Steps

### 1. Install ngrok
```bash
# On macOS
brew install ngrok

# Or download from https://ngrok.com/download
```

### 2. Start Keycloak (if not running)
```bash
cd /Users/apple/Documents/NCB/fido_demo/keycloak_server
docker-compose up -d
```

### 3. Start ngrok tunnel
```bash
ngrok http 8080
```

You'll see output like:
```
Forwarding    https://abc123.ngrok.io -> http://localhost:8080
```

Copy that HTTPS URL (e.g., `https://abc123.ngrok.io`)

### 4. Update Keycloak Configuration

#### A. Update Flutter App
Edit `flutter_app/lib/services/keycloak_service.dart`:
```dart
static const String keycloakUrl = 'https://abc123.ngrok.io'; // Replace with your ngrok URL
static const String realm = 'fido-demo';
static const String clientId = 'flutter-app';
static const String redirectUri = 'com.example.fidodemo://oauth2redirect';
```

#### B. Update Keycloak Admin Console
1. Go to `https://abc123.ngrok.io` (your ngrok URL)
2. Login to Admin Console (admin/admin)
3. Select realm: **fido-demo**
4. Go to **Clients** → **flutter-app** → **Settings**
5. Update **Valid Redirect URIs**:
   ```
   com.example.fidodemo://oauth2redirect
   com.example.fidodemo://*
   https://abc123.ngrok.io/*
   http://localhost:*
   ```
6. Update **Web Origins**: `*`
7. Click **Save**

#### C. Update Keycloak Realm Settings (Important!)
1. Go to **Realm Settings** → **General**
2. Set **Frontend URL**: `https://abc123.ngrok.io`
3. Click **Save**

### 5. Rebuild and test Flutter app
```bash
cd /Users/apple/Documents/NCB/fido_demo/flutter_app
flutter clean
flutter pub get
flutter run
```

## Important Notes

- ngrok free tier URLs change each time you restart ngrok
- You'll need to update the Flutter app and Keycloak config each time
- For permanent solution, use a real domain or ngrok paid plan (static domain)

## Alternative: Use ngrok with fixed domain (Paid)
If you have ngrok paid plan:
```bash
ngrok http 8080 --domain=your-domain.ngrok-free.app
```

Then you only need to configure once.
