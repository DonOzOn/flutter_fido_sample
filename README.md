# FIDO2 Authentication Demo

Một project demo hoàn chỉnh về FIDO2/WebAuthn authentication với Flutter app và Node.js server.

## Cài đặt và Chạy

### 1. Setup Node.js Server

```bash
cd nodejs_server
npm install
npm start
```

Server sẽ chạy trên: http://localhost:3000

### 2. Setup Flutter App

```bash
cd flutter_app
flutter pub get
flutter run
```

## API Endpoints

### Authentication Routes

#### POST /api/auth/register/begin
Bắt đầu quá trình registration
```json
{
  "email": "user@example.com",
  "name": "User Name"
}
```

#### POST /api/auth/register/complete
Hoàn thành registration với passkey data

#### POST /api/auth/signin/begin
Bắt đầu quá trình authentication
```json
{
  "email": "user@example.com"
}
```

#### POST /api/auth/signin/complete
Hoàn thành authentication với passkey verification

#### GET /api/profile (Protected)
Lấy thông tin user profile (cần JWT token)

#### GET /health
Health check endpoint

## Luồng Authentication Chi Tiết

### 📝 Registration Flow (Đăng ký với Passkey)

#### Bước 1: User Nhập Thông Tin
- User nhập **email** và **tên** vào form đăng ký
- App validate input cơ bản (email format, không để trống)

#### Bước 2: App Gọi `/api/auth/register/begin`
**Request:**
```json
POST /api/auth/register/begin
{
  "email": "user@example.com",
  "name": "Nguyễn Văn A"
}
```

**Server xử lý:**
- Kiểm tra email đã tồn tại chưa (nếu có → trả lỗi)
- Tạo **userId** ngẫu nhiên (UUID)
- Tạo **challenge** ngẫu nhiên (chuỗi Base64URL, 32 bytes)
- Lưu challenge vào database với thời hạn 5 phút
- Tạo **PublicKeyCredentialCreationOptions** theo FIDO2 spec

**Response trả về:**
```json
{
  "challenge": "random_base64url_string",
  "rp": {
    "id": "localhost",
    "name": "FIDO2 Demo"
  },
  "user": {
    "id": "base64url_user_id",
    "name": "user@example.com",
    "displayName": "Nguyễn Văn A"
  },
  "pubKeyCredParams": [
    { "type": "public-key", "alg": -7 },   // ES256
    { "type": "public-key", "alg": -257 }  // RS256
  ],
  "timeout": 60000,
  "attestation": "none",
  "excludeCredentials": []
}
```

#### Bước 3: App Tạo Passkey
**Flutter app (auth_service.dart):**
```dart
// Parse challenge data từ server
final registrationRequest = RegisterRequestType(
  challenge: challengeData['challenge'],  // Base64URL string
  relyingParty: RelyingPartyType(
    id: "localhost",           // Domain của app/server
    name: "FIDO2 Demo"
  ),
  user: UserType(
    id: challengeData['user']['id'],      // Base64URL userId
    name: email,                           // Email
    displayName: name                      // Tên hiển thị
  ),
  excludeCredentials: []  // Danh sách credentials cần loại trừ
);

// Gọi platform authenticator (Face ID, Touch ID, Fingerprint)
final registrationResult = await _authenticator.register(registrationRequest);
```

**Điều gì xảy ra trên device:**
- iOS: Hiện Face ID / Touch ID prompt
- Android: Hiện Fingerprint / Face Unlock prompt
- User xác thực sinh trắc học
- Device tạo cặp **public/private key** mới
- Private key được lưu an toàn trong **Secure Enclave** (iOS) hoặc **TEE/StrongBox** (Android)
- Public key và attestation data được trả về cho app

**Registration Result:**
```dart
RegisterResponseType {
  id: "credential_id",                    // Base64URL credential ID
  rawId: "credential_id",                 // Giống id
  clientDataJSON: "base64url_string",    // JSON chứa challenge, origin
  attestationObject: "base64url_string", // Chứa authData + public key
  transports: ["internal"]               // Loại authenticator
}
```

#### Bước 4: App Gửi Credential → Server `/api/auth/register/complete`
**Request:**
```json
POST /api/auth/register/complete
{
  "email": "user@example.com",
  "id": "credential_id",
  "rawId": "credential_id",
  "response": {
    "clientDataJSON": "base64url_client_data",
    "attestationObject": "base64url_attestation"
  },
  "type": "public-key"
}
```

**Server verify (sử dụng @simplewebauthn/server):**
1. Lấy challenge đã lưu từ database (theo email)
2. Verify **clientDataJSON**:
   - Challenge khớp với challenge đã tạo
   - Origin khớp với expected origin
   - Type = "webauthn.create"
3. Parse **attestationObject**:
   - Extract **authenticatorData**
   - Extract **public key** (COSE format)
   - Verify signature (nếu có attestation)
4. Kiểm tra flags trong authenticatorData:
   - User Present (UP) = true
   - User Verified (UV) = true (optional)
   - Attested Credential Data flag = true

**Server lưu data:**
```javascript
// Lưu user vào database
users.insert({
  id: userId,
  email: email,
  name: name,
  created_at: new Date()
});

// Lưu credential
credentials.insert({
  user_id: userId,
  credential_id: credentialId,        // ID của passkey
  public_key: publicKeyBytes,         // Public key để verify
  counter: 0,                         // Signature counter
  transports: ['internal'],           // Loại transport
  created_at: new Date()
});

// Xóa challenge đã dùng
challenges.delete(challengeId);
```

#### Bước 5: Server Trả JWT Token
```json
{
  "success": true,
  "user": {
    "id": "user_id",
    "email": "user@example.com",
    "name": "Nguyễn Văn A",
    "createdAt": "2025-01-21T..."
  },
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**JWT payload:**
```json
{
  "userId": "user_id",
  "email": "user@example.com",
  "iat": 1234567890,  // Issued at
  "exp": 1234654290   // Expires (7 days)
}
```

**App lưu local:**
- Save JWT token vào **FlutterSecureStorage** (encrypted)
- Save user data vào SharedPreferences
- Navigate đến Home Screen

---

### 🔐 Sign In Flow (Đăng nhập với Passkey)

#### Bước 1: User Nhập Email
- User nhập **email** vào form đăng nhập
- App validate email format

#### Bước 2: App Gọi `/api/auth/signin/begin`
**Request:**
```json
POST /api/auth/signin/begin
{
  "email": "user@example.com"
}
```

**Server xử lý:**
- Tìm user theo email trong database
- Nếu không tìm thấy → trả lỗi "User not found"
- Lấy danh sách **credentials** của user (credential IDs)
- Tạo **challenge** mới (32 bytes random)
- Lưu challenge vào database với timeout 5 phút
- Tạo **PublicKeyCredentialRequestOptions**

**Response:**
```json
{
  "challenge": "random_base64url_string",
  "rpId": "localhost",
  "timeout": 60000,
  "userVerification": "preferred",
  "allowCredentials": [
    {
      "type": "public-key",
      "id": "credential_id_base64url",
      "transports": ["internal"]
    }
  ]
}
```

**Giải thích các field:**
- `challenge`: Random string để prevent replay attacks
- `rpId`: Domain của relying party (server)
- `allowCredentials`: Danh sách passkeys mà user có thể dùng để authenticate
- `userVerification`: "preferred" = yêu cầu biometric nếu có thể

#### Bước 3: App Xác Thực với Passkey
**Flutter app:**
```dart
final authRequest = AuthenticateRequestType(
  relyingPartyId: "localhost",
  challenge: challengeData['challenge'],
  mediation: MediationType.Optional,
  preferImmediatelyAvailableCredentials: false,
  allowCredentials: [
    CredentialType(
      type: "public-key",
      id: "credential_id",
      transports: ["internal"]
    )
  ]
);

// Gọi platform authenticator
final authResult = await _authenticator.authenticate(authRequest);
```

**Điều gì xảy ra trên device:**
- Device tìm passkey matching với `allowCredentials`
- Hiện biometric prompt (Face ID / Touch ID / Fingerprint)
- User xác thực sinh trắc học
- Device lấy **private key** từ Secure Enclave/TEE
- Device **ký (sign)** challenge bằng private key
- Trả về assertion data

**Authentication Result:**
```dart
AuthenticateResponseType {
  id: "credential_id",
  rawId: "credential_id",
  clientDataJSON: "base64url_string",    // Chứa challenge, origin
  authenticatorData: "base64url_string", // Chứa rpIdHash, flags, counter
  signature: "base64url_string",         // Signature của challenge
  userHandle: "base64url_user_id"        // User ID
}
```

#### Bước 4: App Gửi Assertion → Server `/api/auth/signin/complete`
**Request:**
```json
POST /api/auth/signin/complete
{
  "email": "user@example.com",
  "id": "credential_id",
  "rawId": "credential_id",
  "response": {
    "clientDataJSON": "base64url_client_data",
    "authenticatorData": "base64url_auth_data",
    "signature": "base64url_signature",
    "userHandle": "base64url_user_id"
  },
  "type": "public-key"
}
```

**Server verify (quan trọng nhất):**

1. **Tìm credential trong database:**
```javascript
const credential = db.getCredentialById(credentialId);
const user = db.getUserById(credential.user_id);
```

2. **Verify clientDataJSON:**
- Parse JSON từ Base64URL
- Kiểm tra `challenge` khớp với challenge đã lưu
- Kiểm tra `origin` khớp với expected origin
- Kiểm tra `type` = "webauthn.get"

3. **Parse authenticatorData:**
```
Authenticator Data Structure (variable length):
- rpIdHash (32 bytes): SHA256 của rpId
- flags (1 byte): UP, UV, BE, BS bits
- signCount (4 bytes): Signature counter
```

4. **Verify signature (QUAN TRỌNG):**
```javascript
// Tạo data cần verify
const dataToVerify = Buffer.concat([
  authenticatorData,           // Raw bytes
  sha256(clientDataJSON)       // Hash của clientDataJSON
]);

// Verify signature bằng public key đã lưu
const isValid = crypto.verify(
  algorithm,        // ES256 hoặc RS256
  dataToVerify,
  publicKey,        // Lấy từ database
  signature         // Signature từ client
);
```

5. **Kiểm tra signature counter:**
```javascript
// Counter phải tăng lên (prevent replay attacks)
if (newCounter <= storedCounter) {
  throw new Error('Invalid counter - possible replay attack');
}

// Update counter
db.updateCredentialCounter(credentialId, newCounter);
```

6. **Verify flags:**
- User Present (UP) flag = 1 (bit 0)
- User Verified (UV) flag = 1 (bit 2) - optional

#### Bước 5: Server Trả JWT Token
**Response:**
```json
{
  "success": true,
  "user": {
    "id": "user_id",
    "email": "user@example.com",
    "name": "Nguyễn Văn A",
    "createdAt": "2025-01-21T..."
  },
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**App lưu local:**
- Save JWT token vào **FlutterSecureStorage** (encrypted)
- Save user data vào SharedPreferences
- Navigate đến Home Screen

---

### 🔒 Các Khái Niệm Quan Trọng

#### Challenge
- Random string (32 bytes) được tạo mỗi lần authentication
- Prevent **replay attacks** (không thể dùng lại response cũ)
- Chỉ có hiệu lực 5 phút
- Mỗi challenge chỉ dùng được 1 lần

#### Public/Private Key Pair
- **Private Key**:
  - Được tạo và lưu trong **Secure Enclave** (iOS) / **Trusted Execution Environment** (Android)
  - KHÔNG BAO GIỜ rời khỏi device
  - Dùng để ký (sign) challenge khi authenticate
- **Public Key**:
  - Được gửi lên server khi registration
  - Server lưu trong database
  - Dùng để verify signature khi user sign in

#### Signature Verification
```
Client                          Server
------                          ------
1. Nhận challenge          →    Tạo challenge
2. Ký bằng private key     →    Lưu challenge
3. Gửi signature           →    Lấy public key
                                Verify signature
                                ✓ Nếu đúng → authenticate thành công
                                ✗ Nếu sai → reject
```

#### Attestation vs Assertion
- **Attestation** (Registration): Chứng thực rằng passkey được tạo bởi authenticator hợp lệ
- **Assertion** (Authentication): Chứng minh user sở hữu private key tương ứng

#### Signature Counter
- Số đếm tăng dần mỗi lần authenticate
- Giúp phát hiện **cloned authenticators**
- Nếu counter không tăng hoặc giảm → có thể bị tấn công

---

### 🛡️ Bảo Mật

#### Tại sao Passkey an toàn hơn password?

1. **Không thể phishing:**
   - Passkey được bind với domain cụ thể (rpId)
   - Không thể dùng trên domain giả mạo

2. **Không thể brute force:**
   - Không có password để đoán
   - Private key không bao giờ rời khỏi device

3. **Không thể database breach:**
   - Server chỉ lưu public key (vô dụng với attacker)
   - Private key trong Secure Enclave không thể extract

4. **Biometric authentication:**
   - Yêu cầu sinh trắc học (Face ID / Fingerprint)
   - Không thể replay hoặc fake

5. **Challenge-response:**
   - Mỗi lần login dùng challenge mới
   - Prevent replay attacks

6. **Secure token storage:**
   - JWT token được lưu trong **FlutterSecureStorage**
   - iOS: Sử dụng Keychain (encrypted)
   - Android: Sử dụng EncryptedSharedPreferences với AES encryption
   - Không thể truy cập token từ bên ngoài app

## Dependencies

### Flutter
- `passkeys: ^2.15.1` - FIDO2/WebAuthn support
- `http: ^1.1.0` - HTTP requests
- `shared_preferences: ^2.2.2` - Local storage for user data
- `flutter_secure_storage: ^9.0.0` - Secure storage for JWT tokens

### Node.js
- `@simplewebauthn/server: ^8.3.6` - FIDO2 server implementation
- `express: ^4.18.2` - Web framework
- `sqlite3: ^5.1.6` - Database
- `jsonwebtoken: ^9.0.2` - JWT tokens

## Bảo mật

- ✅ FIDO2/WebAuthn passwordless authentication
- ✅ JWT token với expiration (7 days)
- ✅ Secure token storage với FlutterSecureStorage (Keychain/EncryptedSharedPreferences)
- ✅ Challenge-based verification (prevent replay attacks)
- ✅ Proper credential storage (private keys in Secure Enclave/TEE)
- ✅ CORS và Helmet security headers
- ✅ Input validation và error handling

## Testing

1. Chạy server: `cd nodejs_server && npm start`
2. Chạy Flutter app trên device/simulator có hỗ trợ biometric
3. Test registration với email mới
4. Test sign in với account đã tạo
5. Verify logout functionality

## Lưu ý

- Passkey cần device hỗ trợ biometric authentication
- iOS Simulator cần enable Touch ID/Face ID
- Android emulator cần setup fingerprint
- Production cần thay đổi JWT_SECRET và domain configuration

