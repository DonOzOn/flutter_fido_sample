# 🔐 Keycloak FIDO2 Integration Guide

## ✅ Đã hoàn thành:

1. ✅ Keycloak server chạy tại: http://localhost:8080
2. ✅ Realm: `fido-demo`
3. ✅ Client: `flutter-app`
4. ✅ WebAuthn Passwordless đã được cấu hình
5. ✅ Flutter app có 2 options: Keycloak SSO & Direct FIDO2

---

## 🚀 Cách chạy:

### **1. Start Keycloak Server:**
```bash
cd /Users/apple/Documents/NCB/fido_demo/keycloak_server
docker-compose up -d

# Check logs
docker logs -f keycloak-fido2
```

### **2. Start Node.js Backend (Optional - cho Direct FIDO2):**
```bash
cd /Users/apple/Documents/NCB/fido_demo/nodejs_server
npm start

# Terminal khác - Start Cloudflare Tunnel
cloudflared tunnel --url http://localhost:3000
```

### **3. Run Flutter App:**
```bash
cd /Users/apple/Documents/NCB/fido_demo/flutter_app
flutter run
```

---

## 📱 Sử dụng App:

### **Màn hình chọn (Auth Method Screen):**

Bạn sẽ thấy 2 options:

#### **Option 1: Keycloak SSO** 🔵
- **Browser-based OAuth2 flow**
- Click "Login with Keycloak"
- App mở browser → http://localhost:8080
- Login với:
  - Username: `testuser`
  - Password: `password123`
- Keycloak sẽ prompt WebAuthn (Face ID/Touch ID)
- Sau khi xác thực → quay về app với token

**⚠️ Lưu ý về Keycloak:**
- WebAuthn chỉ hoạt động trong browser context
- User phải rời app để login
- Cần setup WebAuthn credential trên browser trước

#### **Option 2: Direct FIDO2** 🟢 (Khuyến nghị)
- **Native passkey experience**
- Không cần browser
- WebAuthn prompt ngay trong app
- Face ID / Touch ID native
- Trải nghiệm tốt hơn

---

## 🔧 Cấu hình Keycloak:

### **WebAuthn Policy đã set:**
```
User Verification Requirement: required ⚠️
```
→ Bắt buộc biometric, không có PIN fallback

### **Test User:**
- Username: `testuser`
- Password: `password123`

---

## 🎯 Disable PIN Fallback:

### **Với Keycloak:**
Đã set `User Verification: required` trong WebAuthn Policy
→ Nếu biometric fail → authentication fail (không fallback PIN)

### **Với Node.js Backend:**
Cần update [routes/auth.js](nodejs_server/routes/auth.js):
```javascript
// Dòng 43 và 196
userVerification: 'required', // thay vì 'preferred'
```

---

## 📊 So sánh 2 phương án:

| Feature | Keycloak SSO | Direct FIDO2 |
|---------|-------------|--------------|
| User Experience | Browser redirect | Native in-app |
| Setup | Phức tạp | Đơn giản |
| Enterprise SSO | ✅ Yes | ❌ No |
| Native biometric | ❌ Browser only | ✅ Yes |
| Khuyến nghị | Enterprise | Mobile app |

---

## 🐛 Troubleshooting:

### **Keycloak không chạy:**
```bash
docker ps  # Check container
docker logs keycloak-fido2  # Xem logs
docker-compose restart  # Restart
```

### **Deep linking không hoạt động:**
- Check AndroidManifest.xml có intent-filter cho `com.example.fidodemo://oauth2redirect`
- Rebuild app: `flutter clean && flutter run`

### **WebAuthn không prompt:**
- Keycloak: Phải setup WebAuthn credential trên browser trước
- Direct FIDO2: Check device có hỗ trợ biometric không

---

## 🎓 Kiến trúc:

### **Keycloak Flow:**
```
Flutter App
    ↓ Open browser
Browser → Keycloak Login
    ↓ WebAuthn prompt (in browser)
User → Face ID / Touch ID
    ↓ Success
Keycloak → OAuth callback: com.example.fidodemo://oauth2redirect?code=xxx
    ↓ Deep link
Flutter App → Exchange code for token
    ↓
App authenticated ✅
```

### **Direct FIDO2 Flow:**
```
Flutter App → Node.js Backend
    ↓ Get challenge
Flutter passkeys package → Native WebAuthn
    ↓ Prompt Face ID/Touch ID (in-app)
User → Authenticate
    ↓ Success
Send credential → Node.js Backend
    ↓ Verify
Backend → Return JWT token
    ↓
App authenticated ✅
```

---

## 📝 Kết luận:

**Keycloak SSO:**
- ✅ Tốt cho enterprise với existing Keycloak infrastructure
- ❌ UX không tốt cho mobile (phải mở browser)
- ❌ Phức tạp hơn

**Direct FIDO2 (Node.js):**
- ✅ UX tốt nhất cho mobile app
- ✅ Native biometric experience
- ✅ Đơn giản hơn
- ✅ **Khuyến nghị cho bạn!**

---

## 🎉 Hoàn thành!

Bạn đã có:
1. ✅ Keycloak server với WebAuthn
2. ✅ Node.js FIDO2 backend
3. ✅ Flutter app với cả 2 options
4. ✅ Deep linking setup
5. ✅ Biometric authentication

**Bây giờ bạn có thể test cả 2 phương án và chọn cái phù hợp nhất!** 🚀
