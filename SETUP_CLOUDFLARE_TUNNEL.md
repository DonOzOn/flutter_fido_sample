# Setup Keycloak with Cloudflare Tunnel

## Why Cloudflare Tunnel?
- ✅ Free and permanent
- ✅ Automatic HTTPS
- ✅ No need to open ports on your router
- ✅ Works from anywhere (not just local network)
- ✅ Stable domain name
- ✅ Perfect for FIDO2/WebAuthn (requires HTTPS)

## Prerequisites
- A domain name (you can use a free subdomain from your existing domain)
- Cloudflare account (free)

## Steps

### 1. Install Cloudflare Tunnel (cloudflared)

```bash
# On macOS
brew install cloudflare/cloudflare/cloudflared

# Verify installation
cloudflared --version
```

### 2. Login to Cloudflare

```bash
cloudflared tunnel login
```

This will open a browser window. Select your domain and authorize.

### 3. Create a Tunnel

```bash
# Create a tunnel named "keycloak-fido"
cloudflared tunnel create keycloak-fido
```

This will output a Tunnel ID like: `abc12345-6789-def0-1234-567890abcdef`

Copy this Tunnel ID - you'll need it.

### 4. Create Tunnel Configuration File

Create a config file at `~/.cloudflared/config.yml`:

```bash
nano ~/.cloudflared/config.yml
```

Add this content (replace with your values):

```yaml
tunnel: abc12345-6789-def0-1234-567890abcdef  # Your Tunnel ID
credentials-file: /Users/apple/.cloudflared/abc12345-6789-def0-1234-567890abcdef.json

ingress:
  # Route keycloak.yourdomain.com to local Keycloak
  - hostname: keycloak.yourdomain.com
    service: http://localhost:8080

  # Catch-all rule (required)
  - service: http_status:404
```

Replace:
- `abc12345-6789-def0-1234-567890abcdef` with your actual Tunnel ID
- `keycloak.yourdomain.com` with your desired subdomain

### 5. Create DNS Record

```bash
# Route your subdomain to the tunnel
cloudflared tunnel route dns keycloak-fido keycloak.yourdomain.com
```

Replace `keycloak.yourdomain.com` with your subdomain.

### 6. Start Keycloak Docker

```bash
cd /Users/apple/Documents/NCB/fido_demo/keycloak_server
docker-compose up -d
```

Verify Keycloak is running at http://localhost:8080

### 7. Start Cloudflare Tunnel

```bash
cloudflared tunnel run keycloak-fido
```

Or run in background:
```bash
cloudflared tunnel run keycloak-fido &
```

### 8. Test Access

Open browser and go to: `https://keycloak.yourdomain.com`

You should see the Keycloak login page with HTTPS! 🎉

### 9. Configure Keycloak

#### A. Update Keycloak Realm Settings
1. Go to `https://keycloak.yourdomain.com`
2. Login to Admin Console (admin/admin)
3. Select realm: **fido-demo**
4. Go to **Realm Settings** → **General**
5. Set **Frontend URL**: `https://keycloak.yourdomain.com`
6. Click **Save**

#### B. Update Keycloak Client
1. Go to **Clients** → **flutter-app** → **Settings**
2. Update **Valid Redirect URIs**:
   ```
   com.example.fidodemo://oauth2redirect
   com.example.fidodemo://*
   https://keycloak.yourdomain.com/*
   http://localhost:*
   ```
3. Update **Valid Post Logout Redirect URIs**:
   ```
   com.example.fidodemo://oauth2redirect
   +
   ```
4. Update **Web Origins**: `*`
5. Click **Save**

### 10. Update Flutter App

Edit `/Users/apple/Documents/NCB/fido_demo/flutter_app/lib/services/keycloak_service.dart`:

```dart
class KeycloakService {
  // Keycloak Configuration
  static const String keycloakUrl = 'https://keycloak.yourdomain.com';  // ← Update this
  static const String realm = 'fido-demo';
  static const String clientId = 'flutter-app';
  static const String redirectUri = 'com.example.fidodemo://oauth2redirect';

  // ... rest of the code
}
```

### 11. Rebuild and Test

```bash
cd /Users/apple/Documents/NCB/fido_demo/flutter_app
flutter clean
flutter pub get
flutter run
```

## Run Tunnel as a Service (Optional)

To keep the tunnel running automatically:

### On macOS (using launchd)

```bash
# Install as a service
sudo cloudflared service install
```

This will:
- Start tunnel on boot
- Restart if it crashes
- Run in background

### Manual start/stop
```bash
# Start
sudo launchctl start com.cloudflare.cloudflared

# Stop
sudo launchctl stop com.cloudflare.cloudflared

# Check status
sudo launchctl list | grep cloudflare
```

## Managing Tunnels

```bash
# List all tunnels
cloudflared tunnel list

# Get tunnel info
cloudflared tunnel info keycloak-fido

# Delete a tunnel (when no longer needed)
cloudflared tunnel delete keycloak-fido
```

## Troubleshooting

### Tunnel not connecting
```bash
# Check tunnel status
cloudflared tunnel info keycloak-fido

# Test tunnel with verbose output
cloudflared tunnel --loglevel debug run keycloak-fido
```

### Keycloak not accessible
1. Verify Keycloak is running: `docker ps`
2. Test local access: `curl http://localhost:8080`
3. Check tunnel config: `cat ~/.cloudflared/config.yml`

### DNS not resolving
- DNS propagation can take a few minutes
- Check DNS: `nslookup keycloak.yourdomain.com`
- Verify in Cloudflare Dashboard: DNS → Records

## Complete Docker Setup (Optional)

You can also run Cloudflare Tunnel in Docker alongside Keycloak:

Create `/Users/apple/Documents/NCB/fido_demo/keycloak_server/docker-compose.yml`:

```yaml
version: '3.8'

services:
  keycloak:
    image: quay.io/keycloak/keycloak:23.0
    container_name: keycloak-fido2
    environment:
      KEYCLOAK_ADMIN: admin
      KEYCLOAK_ADMIN_PASSWORD: admin
      KC_HTTP_ENABLED: "true"
      KC_HOSTNAME_STRICT: "false"
      KC_HOSTNAME_STRICT_HTTPS: "false"
      KC_PROXY: edge
      KC_HTTP_RELATIVE_PATH: /
    ports:
      - "8080:8080"
    command:
      - start-dev
      - --features=preview
    volumes:
      - keycloak_data:/opt/keycloak/data
    networks:
      - keycloak-network

  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflare-tunnel
    command: tunnel --no-autoupdate run
    environment:
      - TUNNEL_TOKEN=YOUR_TUNNEL_TOKEN_HERE  # Get from Cloudflare Dashboard
    depends_on:
      - keycloak
    networks:
      - keycloak-network
    restart: unless-stopped

networks:
  keycloak-network:
    driver: bridge

volumes:
  keycloak_data:
```

To get the TUNNEL_TOKEN:
1. Go to https://dash.cloudflare.com
2. Zero Trust → Access → Tunnels
3. Create a tunnel via dashboard
4. Copy the token from the installation command

## Benefits Summary

✅ **HTTPS automatically** - No SSL certificate management
✅ **Permanent URL** - Unlike ngrok free tier
✅ **No firewall changes** - Works through NAT
✅ **Free forever** - No usage limits
✅ **Fast and reliable** - Cloudflare's global network
✅ **Perfect for FIDO2** - WebAuthn requires HTTPS

## Next Steps

1. Install cloudflared: `brew install cloudflare/cloudflare/cloudflared`
2. Login: `cloudflared tunnel login`
3. Create tunnel: `cloudflared tunnel create keycloak-fido`
4. Configure and run!

Need help? Check the logs:
```bash
cloudflared tunnel --loglevel debug run keycloak-fido
```
