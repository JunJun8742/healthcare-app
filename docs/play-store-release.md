# ขั้นตอนปล่อยแอปขึ้น Google Play

package name: `th.ac.acat.healthcarestation` (เปลี่ยนไม่ได้หลังเผยแพร่)

ทำตามลำดับ — ขั้น 1–2 ต้องเสร็จก่อน ไม่งั้น build ไม่ผ่าน

---

## 1. ลงทะเบียน package ใหม่ใน Firebase (ต้องทำก่อน build)

`google-services.json` / `lib/firebase_options.dart` ยังผูกกับ `com.example.flutter_application_1`
ถ้าไม่ทำขั้นนี้ build จะล้มด้วย `No matching client found for package name`

1. Firebase Console → โปรเจกต์ `heal-a49e3` → Project settings → **Add app → Android**
2. Package name: `th.ac.acat.healthcarestation`
3. รันจากโฟลเดอร์โปรเจกต์ (Git Bash) แล้วเลือก Android:

```bash
flutterfire configure --project=heal-a49e3
```

คำสั่งนี้จะอัปเดตทั้ง `android/app/google-services.json` และ `lib/firebase_options.dart`

## 2. สร้าง upload key (ทำครั้งเดียว — เก็บไฟล์ให้ดี หายแล้วอัปเดตแอปลำบาก)

```bash
keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

สร้างไฟล์ `android/key.properties` (ถูก gitignore แล้ว — **ห้าม commit**):

```properties
storePassword=รหัสที่ตั้งตอน keytool
keyPassword=รหัสที่ตั้งตอน keytool
keyAlias=upload
storeFile=C:/Users/<ชื่อผู้ใช้>/upload-keystore.jks
```

สำรอง `upload-keystore.jks` + รหัสผ่านไว้ที่อื่น (เช่น Drive ส่วนตัว) ด้วย

> ถ้าไม่มี `key.properties` → release build จะ error ทันที (ตั้งใจ — เดิมแอบใช้ debug key)

## 3. Build

```bash
flutter clean
```

```bash
flutter build appbundle --release
```

ไฟล์ที่ได้: `build/app/outputs/bundle/release/app-release.aab` ← อัปโหลดอันนี้ขึ้น Play

## 4. ใส่ข้อมูลติดต่อ แล้ว deploy หน้าเว็บ

แก้ `[ชื่อหน่วยงาน/ผู้พัฒนา]` และ `[อีเมลติดต่อ]` ใน `public/privacy.html` และ `public/delete-account.html` แล้ว:

```bash
firebase deploy --only hosting
```

- Privacy policy: https://heal-a49e3.web.app/privacy.html
- ขอลบบัญชี: https://heal-a49e3.web.app/delete-account.html

## 5. Play Console

1. สร้างแอป → อัปโหลด `.aab` ไปที่ **Closed testing** → เปิดใช้ **Play App Signing**
2. บัญชีส่วนตัว: ต้องมีผู้ทดสอบ opt-in **อย่างน้อย 12 คน ต่อเนื่อง 14 วัน** ก่อนขอ Production
3. App content: Privacy policy URL, **Delete account URL**, Data safety, **Health apps declaration**, Content rating, Target audience
4. Store listing: ไอคอน 512×512, feature graphic 1024×500, screenshots ≥ 2 รูป, คำอธิบายสั้น/ยาว

## 6. App Check (สำคัญ — ไม่ทำแล้ว callable ทุกตัวพัง)

Play App Signing เซ็นแอปใหม่ด้วย key ของ Google:

1. Play Console → Test and release → **App integrity** → คัดลอก **SHA-256 ของ App signing key** (และ Upload key)
2. Firebase Console → Project settings → แอป Android ตัวใหม่ → **Add fingerprint** ใส่ทั้งสองค่า
3. Firebase Console → App Check → ลงทะเบียนแอปตัวใหม่กับ **Play Integrity**
4. Play Console → App integrity → เชื่อม Google Cloud project `heal-a49e3`

## หมายเหตุ

- คนที่ติดตั้ง APK จาก QR เดิมไปแล้ว ต้อง**ถอนแอปเก่าก่อน** (package/key ไม่ตรงกัน)
- ทุกครั้งที่อัปโหลดเวอร์ชันใหม่ ต้องเพิ่มเลขหลัง `+` ใน `pubspec.yaml` (`version: 1.0.0+1` → `1.0.1+2`)
