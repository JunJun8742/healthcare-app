# สรุปงานและแผนทำต่อสำหรับโปรเจกต์ Healthcare App

เอกสารนี้ใช้สำหรับส่งต่อบริบทก่อน/หลังเปลี่ยนชื่อโฟลเดอร์ทำงาน

## 1. สถานะโปรเจกต์ตอนนี้

โปรเจกต์คือ Flutter app สำหรับจองคิวโรงพยาบาล ใช้ Firebase Auth และ Cloud Firestore

โครงสร้างหลัก:

```text
healthcare-app/
  lib/
    main.dart
    firebase_options.dart
  assets/
  android/
  ios/
  web/
  pubspec.yaml
  firebase.json
  AGENTS.md
  CLAUDE.md
  CLAUDE_CODE_PRODUCTIVITY_GUIDE.md
```

ไฟล์หลักของแอปคือ:

```text
healthcare-app/lib/main.dart
```

แอปส่วนใหญ่ยังอยู่ในไฟล์เดียว ไม่ได้แยก screens/models/services ชัดเจน

## 2. สิ่งที่ทำไปแล้ว

### 2.1 สร้างไฟล์ guidance สำหรับ agent

สร้างไฟล์:

```text
healthcare-app/AGENTS.md
```

ใช้เป็นคู่มือให้ Codex/Claude เข้าใจโปรเจกต์ เช่น:

- โครงสร้างแอป
- command ที่ใช้
- role ของผู้ใช้
- Firestore collections
- queue status
- ข้อควรระวังเวลาแก้โค้ด

### 2.2 ตรวจระบบทั้งแอปแบบ code review

ตรวจประเด็นหลัก:

- logic จองคิว
- duplicate booking
- queue number
- staff workflow
- Firestore structure
- security
- UX/UI
- elderly user
- SOS
- admin
- release/security risk

ข้อค้นพบสำคัญ:

- ยังไม่มี Firestore Security Rules ใน repo
- role ยังพึ่งข้อมูลฝั่ง client มากเกินไป
- staff invite code ถูกอ่านจาก client
- ระบบจองคิวยังไม่ใช้ transaction
- queue number อาจซ้ำได้
- ไม่มี capacity ต่อวัน/ต่อ slot
- staff อ่าน appointment ทั้งหมด
- admin delete ยังไม่ลบ Firebase Auth account
- `release.keystore` ถูก track ใน git
- รูป profile เก็บ base64 ใน Firestore
- ไม่มี audit log
- ไม่มี automated tests

### 2.3 สร้างไฟล์ productivity guide สำหรับ Claude Code

สร้างไฟล์:

```text
healthcare-app/CLAUDE_CODE_PRODUCTIVITY_GUIDE.md
```

เนื้อหาหลัก:

- วิธีประหยัด token
- แนะนำ slash commands
- แนะนำ subagents
- แนะนำ MCP
- แนะนำ hooks
- แนวคิดทำ plugin ส่วนตัว
- checklist สำหรับแอปโรงพยาบาล

ไฟล์นี้มีไว้ให้ Claude Code อ่านแล้วจัดระบบต่อได้

### 2.4 เริ่มแผนการสอน

วางแผนการเรียนรู้ทีละบทเพื่อให้เจ้าของโปรเจกต์เข้าใจแอปตัวเอง

เริ่มบทที่ 1 แล้ว:

```text
บทที่ 1: ภาพรวมแอปทั้งระบบ
```

สิ่งที่เรียนไป:

- แอปมีผู้ใช้ 3 ประเภท
  - ผู้ป่วย / patient
  - เจ้าหน้าที่ / staff
  - แอดมิน / admin
- ผู้ป่วยสมัครบัญชี login และจองคิว
- เจ้าหน้าที่เรียกคิว เปลี่ยนสถานะ ดู SOS ตั้งเวลาว่าง
- role เป็นหัวใจของการพาผู้ใช้ไปหน้าที่ถูกต้อง

การบ้านล่าสุด:

```text
หลังจากผู้ป่วยจองคิวสำเร็จ ผู้ป่วยควรเห็นข้อมูลอะไรบ้างบนหน้าจอ?
```

## 3. งานสำคัญที่ควรทำต่อ

## 3.1 งานเร่งด่วนด้าน Security

### งาน 1: เพิ่ม Firestore Security Rules

เหตุผล:

- ป้องกันผู้ใช้เห็นข้อมูลคนอื่น
- ป้องกันผู้ป่วยแก้ role ตัวเอง
- ป้องกัน staff/admin action ที่ไม่ได้รับอนุญาต

สิ่งที่ควรทำ:

- เพิ่มไฟล์ `firestore.rules`
- เพิ่มไฟล์ `firestore.indexes.json`
- rules ต้องแยกสิทธิ์ patient/staff/admin
- ห้าม delete ข้อมูลสำคัญจาก client โดยตรง

### งาน 2: ย้าย role สำคัญไป server-side

เหตุผล:

- ถ้า role อยู่แค่ใน Firestore client อาจเสี่ยงถูกแก้ไข

สิ่งที่ควรทำ:

- ใช้ Firebase custom claims
- ใช้ Cloud Functions สำหรับตั้ง role
- ห้ามให้ client ตั้งตัวเองเป็น staff/admin

### งาน 3: แก้ระบบ staff invite

ปัญหาปัจจุบัน:

- client อ่าน `settings/staff_invite`
- ถ้า rules เปิด ใครก็อ่าน code แล้วสมัคร staff ได้

สิ่งที่ควรทำ:

- ใช้ one-time invite token
- verify token ผ่าน Cloud Function
- token ควรมีวันหมดอายุ
- token ควรใช้ได้ครั้งเดียว

### งาน 4: เอา `release.keystore` ออกจาก git

เหตุผล:

- signing key ไม่ควรอยู่ใน repo

สิ่งที่ควรทำ:

- เพิ่ม `.gitignore`
  - `*.keystore`
  - `*.jks`
  - `key.properties`
  - `.env`
- rotate key ถ้าเคย push ไปแล้ว

## 3.2 งานเร่งด่วนด้านระบบจองคิว

### งาน 5: ใช้ transaction ตอนจองคิว

ปัญหาปัจจุบัน:

- ผู้ป่วยสองคนอาจจองเวลาเดียวกันพร้อมกัน
- queue number อาจซ้ำได้

สิ่งที่ควรทำ:

- สร้าง collection สำหรับ slot เช่น `appointment_slots`
- ใช้ Firestore transaction
- ตรวจ capacity ก่อนจอง
- เพิ่ม counter เลขคิวรายวัน

### งาน 6: เพิ่ม capacity ต่อวัน/ต่อช่วงเวลา

สิ่งที่ควรมี:

- จำนวนคิวสูงสุดต่อวัน
- จำนวนคิวสูงสุดต่อ time slot
- จำนวนคิวต่อเจ้าหน้าที่
- ข้อความแจ้ง “คิวเต็ม”

### งาน 7: เพิ่มหน้าสรุปก่อนยืนยันจอง

ควรแสดง:

- ชื่อผู้ป่วย
- วัน
- เวลา
- เจ้าหน้าที่/นักกายภาพ
- เครื่อง
- แผนกหรือบริการ
- ปุ่มยืนยัน

### งาน 8: เพิ่ม success screen หลังจองสำเร็จ

ควรแสดง:

- เลขคิว
- วันที่
- เวลา
- เจ้าหน้าที่
- สถานะเริ่มต้น
- ปุ่มไปหน้าคิวของฉัน

## 3.3 งานด้าน UX/UI

### งาน 9: ปรับ UI สำหรับผู้สูงอายุ

สิ่งที่ควรทำ:

- เพิ่มขนาด font
- เพิ่มขนาดปุ่ม
- เพิ่ม contrast
- ลดข้อความยาว
- ลดจำนวนขั้นตอนที่สับสน
- เพิ่ม confirmation ก่อน action สำคัญ

### งาน 10: ปรับ SOS ให้เหมาะกับผู้ป่วยเร่งด่วน

ปัญหาปัจจุบัน:

- SOS เป็นเพียงการบันทึก Firestore

สิ่งที่ควรเพิ่ม:

- ปุ่มโทรฉุกเฉิน
- คำเตือนชัดเจนว่าถ้าอันตรายให้ติดต่อเจ้าหน้าที่ทันที
- แจ้งเตือนเสียง/real-time ให้ staff
- บันทึกเวลาและผู้รับเรื่อง
- audit log

### งาน 11: รองรับญาติผู้ป่วย

สิ่งที่ควรเพิ่ม:

- ผู้จองกับผู้ป่วยต้องแยกกัน
- เพิ่ม patient profile หลายคนในบัญชีเดียว
- เพิ่มความสัมพันธ์ เช่น ลูก หลาน ผู้ดูแล
- เพิ่ม consent

## 3.4 งานด้าน Staff/Admin

### งาน 12: เพิ่ม filter/search ในหน้าคิว staff

ควรค้นหาได้จาก:

- เลขคิว
- ชื่อผู้ป่วย
- วันที่
- สถานะ
- เจ้าหน้าที่

### งาน 13: เพิ่ม audit log ทุกการเปลี่ยนสถานะ

ควรบันทึก:

- appointment id
- สถานะเดิม
- สถานะใหม่
- actor uid
- actor role
- createdAt

### งาน 14: แก้ admin delete user

ปัญหาปัจจุบัน:

- ลบ Firestore doc แต่ไม่ลบ Firebase Auth account

ควรทำ:

- ใช้ soft delete
- ใช้ Cloud Function
- disable account แทนลบจริง
- ห้ามลบประวัติการรักษาทิ้งถ้าเป็นข้อมูลทางการแพทย์

## 3.5 งานด้านโครงสร้างโค้ด

### งาน 15: แยก `main.dart`

ตอนนี้ `main.dart` ใหญ่มาก

แนะนำแยกเป็น:

```text
lib/
  main.dart
  theme/
  screens/
    auth/
    patient/
    staff/
    admin/
  services/
    auth_service.dart
    appointment_service.dart
    user_service.dart
  models/
    user_profile.dart
    appointment.dart
    staff_availability.dart
  widgets/
```

### งาน 16: เพิ่ม models

ควรมี model สำหรับ:

- UserProfile
- Appointment
- StaffAvailability
- SOSAlert
- MachineStatus

### งาน 17: เพิ่ม service layer

ควรแยก Firestore logic ออกจาก UI

เช่น:

- `AppointmentService.createAppointment()`
- `AppointmentService.cancelAppointment()`
- `StaffService.loadAvailability()`
- `SosService.sendAlert()`

## 3.6 งานด้าน Testing

### งาน 18: เพิ่ม test directory

ตอนนี้ยังไม่มี test ที่ชัดเจน

ควรเพิ่ม:

- unit test สำหรับ booking logic
- widget test สำหรับหน้า booking
- Firebase Emulator test สำหรับ Firestore Rules
- integration test สำหรับ flow ผู้ป่วยจองคิว

### งาน 19: ทำ checklist ทดสอบ

ควรทดสอบ:

- สมัครสมาชิก
- login
- จองคิว
- จองคิวซ้ำ
- คิวเต็ม
- ยกเลิกคิว
- staff เรียกคิว
- staff เปลี่ยนสถานะ
- SOS
- admin disable user

## 4. งานด้าน Claude Code Productivity

### งาน 20: สร้าง `.claude/commands/`

ไฟล์ที่ควรสร้าง:

```text
.claude/commands/audit-healthcare-app.md
.claude/commands/review-booking-flow.md
.claude/commands/review-firestore-security.md
.claude/commands/elderly-ui-check.md
.claude/commands/make-ipad-report.md
```

### งาน 21: สร้าง `.claude/agents/`

ไฟล์ที่ควรสร้าง:

```text
.claude/agents/healthcare-security-reviewer.md
.claude/agents/booking-system-reviewer.md
.claude/agents/flutter-ux-reviewer.md
.claude/agents/firebase-architect.md
.claude/agents/report-writer.md
```

### งาน 22: ค่อยพิจารณา hooks

ควรใช้เมื่อพร้อม:

- format Dart
- run analyze
- block secret files

ยังไม่ควรให้ hook deploy หรือแก้ rules เอง

### งาน 23: ค่อยพิจารณา MCP

ใช้เฉพาะที่จำเป็น:

- GitHub MCP
- Figma MCP
- Sentry MCP
- Notion/Drive MCP
- Firebase MCP แบบ read-only

## 5. งานด้านการเรียนรู้

แผนเรียนที่วางไว้:

1. ภาพรวมแอปทั้งระบบ
2. โครงสร้าง Flutter
3. Navigation
4. Firebase Auth
5. Role ผู้ใช้
6. Firestore Database
7. ระบบจองคิว
8. สถานะคิว
9. ระบบเจ้าหน้าที่
10. UX/UI ผู้ใช้จริง
11. ความปลอดภัย
12. กรณีผิดพลาด
13. Testing
14. Refactor
15. Roadmap

บทที่เริ่มแล้ว:

```text
บทที่ 1: ภาพรวมแอปทั้งระบบ
```

การบ้านที่ยังตอบต่อได้:

```text
หลังจากผู้ป่วยจองคิวสำเร็จ ผู้ป่วยควรเห็นข้อมูลอะไรบ้างบนหน้าจอ?
```

## 6. Checklist ก่อนเปลี่ยนชื่อ Folder

ก่อนเปลี่ยนชื่อ folder ให้ทำสิ่งนี้:

1. ปิด terminal/dev server ที่เปิดอยู่
2. ปิด editor หรือ IDE ที่กำลังจับ path เดิม
3. ตรวจว่า folder มี `.git`
4. จด path เดิมและ path ใหม่
5. อย่าแยก `healthcare-app` ออกจาก `.git` ถ้ายังต้องใช้ git history เดิม
6. ตรวจว่ามีไฟล์สำคัญ:
   - `AGENTS.md`
   - `CLAUDE.md`
   - `CLAUDE_CODE_PRODUCTIVITY_GUIDE.md`
   - `WORK_HANDOFF_SUMMARY.md`
   - `lib/main.dart`
   - `pubspec.yaml`

## 7. Checklist หลังเปลี่ยนชื่อ Folder

หลังเปลี่ยนชื่อ folder ให้ทำ:

1. เปิด workspace ใหม่ให้ชี้ path ใหม่
2. เช็กว่า terminal อยู่ใน folder ถูกต้อง
3. รัน:

```bash
git status --short --branch
```

4. รัน:

```bash
flutter pub get
```

5. ถ้า Flutter พร้อม ให้รัน:

```bash
flutter analyze
```

6. ตรวจว่าไฟล์ Markdown ยังเปิดได้ใน Obsidian/iPad
7. ถ้าใช้ Claude/Codex ให้เริ่มด้วยคำว่า:

```text
อ่าน AGENTS.md และ WORK_HANDOFF_SUMMARY.md ก่อน แล้วทำงานต่อจากบริบทนี้
```

## 8. Prompt สำหรับใช้หลังเปลี่ยนชื่อ Folder

ใช้ prompt นี้กับ Claude/Codex หลังย้าย folder:

```text
โปรเจกต์นี้คือ Flutter/Firebase healthcare queue app
กรุณาอ่าน AGENTS.md และ WORK_HANDOFF_SUMMARY.md ก่อน
จากนั้นช่วยทำงานต่อโดยรักษาบริบทเดิม:
- ตรวจ/แก้ระบบจองคิว
- เพิ่ม Firestore security
- ปรับ UX สำหรับผู้สูงอายุ
- สร้าง slash commands/subagents สำหรับ Claude Code
อย่า refactor ใหญ่ถ้ายังไม่ได้รับคำสั่ง
```

## 9. ลำดับงานที่แนะนำหลัง rename เสร็จ

แนะนำทำตามนี้:

1. ยืนยัน path ใหม่และเปิด workspace ใหม่
2. อ่าน `AGENTS.md`
3. อ่าน `WORK_HANDOFF_SUMMARY.md`
4. เช็ก `git status`
5. สร้าง/ตรวจ `.claude/commands`
6. สร้าง/ตรวจ `.claude/agents`
7. เพิ่ม `.gitignore` กัน secret
8. เริ่มแก้ Firestore Rules
9. เริ่มแก้ booking transaction
10. เรียนบทที่ 2 ต่อ: โครงสร้าง Flutter

