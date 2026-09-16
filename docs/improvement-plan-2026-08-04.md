# แผนการปรับปรุง Healthcare Station — Todo List

> จัดทำ 4 ส.ค. 2569 · จากการวิเคราะห์ `README.md`, `firestore.rules`, `functions/src/index.ts`, `lib/`
> ระดับความสำคัญ: 🔴 Must fix (ก่อนให้ผู้ป่วยจริงใช้) · 🟠 Should fix (ก่อนขยายเกิน pilot) · 🟢 Nice to have

## Jira: [Healthcare-Station (KAN)](https://healthcarestation.atlassian.net/browse/KAN-7)

| Epic | Jira | งานย่อย |
|---|---|---|
| A · ความปลอดภัยและการปฏิบัติตามกฎหมาย | KAN-7 | KAN-13 (M1), KAN-30 (M7), KAN-31 (M5), KAN-14 (M6), KAN-15 (M8), KAN-16 (S4), KAN-35 (S7) |
| B · การแจ้งเตือนและ SOS | KAN-8 | KAN-17 (M2), KAN-18 (M3), KAN-19 (S9) |
| C · ความถูกต้องของระบบคิว | KAN-9 | KAN-20 (M4), KAN-21 (S3), KAN-22 (S11), KAN-23 (S13) |
| D · Data model และความเป็นส่วนตัว | KAN-10 | KAN-24 (S1), KAN-25 (S2), KAN-26 (S5), KAN-27 (S6), KAN-28 (S12), KAN-29 (N3) |
| E · คุณภาพ การทดสอบ การส่งมอบ | KAN-11 | KAN-32 (M9), KAN-33 (S10), KAN-34 (S8) |
| F · UX และการขยายผล | KAN-12 | KAN-36 (N1), KAN-37 (N2), KAN-38 (N4), KAN-39 (N5), KAN-40 (N6), KAN-41 (N7) |

*(KAN-6 "เปลี่ยนจาก SOS เป็นแจ้งเหตุฉุกเฉินภายในสถานี" ที่มีอยู่เดิม ทับซ้อนกับ KAN-18 — พิจารณารวมเข้าด้วยกัน)*

---

## 🔴 Must fix — ห้ามให้ผู้ป่วยจริงใช้ก่อนแก้ครบ

- [ ] **M1 · ปิด public read ของ `settings/staff_invite` + ทำ one-time invite token**
  ปัจจุบัน `allow read: if true` → ใครก็อ่าน invite code ได้โดยไม่ต้องล็อกอิน → สมัครเป็น staff → เข้าถึงข้อมูลผู้ป่วยทั้งระบบ
  - [ ] แก้เป็น `allow read: if false` เป็นการหยุดเลือดทันที (1 บรรทัด)
  - [ ] Cloud Function ออก token แบบใช้ครั้งเดียว + มีวันหมดอายุ
  - [ ] ปรับ `staff_register_screen.dart` ให้เรียก function แทนอ่าน Firestore ตรง
  - [ ] แก้ rule `users/{uid}` create ให้ตรวจ token แทน `invite_code`

- [ ] **M2 · Deploy Cloud Functions ให้ push ทำงานจริง**
  ฟีเจอร์แจ้งเตือน + SOS ยัง inert อยู่ทั้งหมด
  - [ ] อัปเกรดโปรเจกต์ `heal-a49e3` เป็น Blaze plan
  - [ ] ยืนยัน Firestore region ตรงกับ `REGION = 'asia-southeast1'`
  - [ ] `firebase deploy --only functions,firestore:rules`
  - [ ] เปิด Firestore TTL บน `notifications.expiresAt` (30 วัน)
  - [ ] ทดสอบบนเครื่องจริง: booking→เรียกคิว→push, SOS→staff push, ยกเลิกสองทาง, tap routing

- [ ] **M3 · SOS: ปุ่มโทร 1669 + คำเตือน + สถานะ "เจ้าหน้าที่เห็นแล้ว"**
  ป้องกันผู้ป่วยนั่งรอ SOS แทนการโทรฉุกเฉิน — งานเล็กที่สุดที่ลดความเสี่ยงมากที่สุด
  - [ ] หน้าถามก่อนส่ง: "อันตรายถึงชีวิตหรือไม่?" → ใช่ = ปุ่มโทร 1669 เด่นที่สุด
  - [ ] แสดงสถานะสดให้ผู้ป่วย: ส่งแล้ว → เจ้าหน้าที่เห็นแล้ว → กำลังดำเนินการ
  - [ ] แจ้งผู้ใช้ล่วงหน้าเมื่ออยู่นอกเวลาทำการ

- [ ] **M4 · ย้าย booking transaction ไป Cloud Function + ปิด client write**
  ตอนนี้ผู้ใช้ที่ล็อกอินคนไหนก็เขียน `queue_days` / `queue_slots` ได้ → ยิง `count + 1` รัว ๆ หรือ flip slot ของคนอื่นได้ = DoS ระบบคิวทั้งสถานี
  - [ ] callable function `createBooking` / `cancelBooking`
  - [ ] `queue_days`, `queue_slots` → `allow write: if false`
  - [ ] `appointments.status` เปลี่ยนผ่าน function เท่านั้น
  - [ ] ⚠️ ทำ **หลัง** M7 เท่านั้น (ต้องมี rules test รองก่อน)

- [ ] **M5 · PDPA: หน้า consent + privacy policy + ระบุผู้ควบคุมข้อมูล**
  ข้อมูลสุขภาพ = ข้อมูลอ่อนไหวตาม ม.26 ต้องมีความยินยอมโดยชัดแจ้ง แยกจาก T&C
  - [ ] ร่างนโยบายความเป็นส่วนตัว + โฮสต์บน Firebase Hosting
  - [ ] หน้า consent ตอนสมัคร (แยก checkbox ข้อมูลสุขภาพออกจาก T&C)
  - [ ] เก็บ `consentVersion` + `consentedAt` ใน `users/{uid}`

- [ ] **M6 · บังคับ email verification ก่อนจองคิว**
  ตอนนี้สมัครด้วยอีเมลอะไรก็ได้ → บัญชีปลอมไม่จำกัด → ขยายผลทุกช่องโหว่ข้างบน

- [ ] **M7 · Firestore Rules test ด้วย Firebase Emulator**
  rules 151 บรรทัดคือ security boundary เดียวของระบบ แต่มีเทสต์ 0 ตัว
  - [ ] ตั้ง `@firebase/rules-unit-testing` + emulator config
  - [ ] patient แก้ `role` ตัวเองไม่ได้
  - [ ] ยกเลิกได้เฉพาะคิวตัวเองที่สถานะ `กำลังรอ` และแตะได้แค่ 3 ฟิลด์
  - [ ] staff/admin scope, invite code, `queue_days` count +1, `queue_slots` add-only

- [ ] **M8 · Rotate signing key + ยืนยัน Firestore region**
  - [ ] สร้าง keystore ใหม่ (ตัวเก่าเคยอยู่ใน git history = ถือว่ารั่ว)
  - [ ] `gcloud firestore databases describe` — ถ้าไม่ใช่ asia-southeast1 ต้องวางแผนย้าย

- [ ] **M9 · Crashlytics + Firestore scheduled backup**
  แจก APK ให้ผู้สูงอายุใช้ ถ้าแอปพังจะไม่มีทางรู้ / Spark plan ไม่มี backup อัตโนมัติ

---

## 🟠 Should fix — ก่อนขยายเกิน pilot

- [ ] **S1 · `audit_logs` (บันทึกทั้งการแก้และการอ่าน) + soft delete แทน hard delete**
  ระบบเวชระเบียนต้องตอบได้ว่า "ใครเปิดดูประวัติใครเมื่อไร" · `admin` ต้องลบข้อมูลจริงไม่ได้
- [ ] **S2 · แยก `staff_public` (ชื่อ + รูปย่อ) ออกจาก `users`**
  ตอนนี้ผู้ป่วยคนไหนก็อ่าน `users` doc ของ staff ได้ทั้งก้อน = ได้อีเมล + รูปหน้าไปด้วย
- [ ] **S3 · Capacity ต่อวัน/ต่อ slot + สถานะ no-show + auto-expire**
  ไม่มีเพดาน = จองเกินกำลังเจ้าหน้าที่ · คิวค้าง `กำลังรอ` ตลอดไป slot ไม่ถูกคืน
- [ ] **S4 · ย้าย `role` ไป custom claims**
  ลด `get()` reads ทุก request + ปิด race ตอนสมัคร
- [ ] **S5 · `photoBase64` → Firebase Storage**
  resize 512×512 q80 ก่อนอัป + dual-read ระหว่าง migrate + rules จำกัดขนาด/content-type
- [ ] **S6 · `dateIso` เป็น source of truth (เลิกใช้ พ.ศ. เป็น doc ID)**
  ปัจจุบันต้อง byte-match ข้าม Dart/TS, sort/query ช่วงวันไม่ได้, เคยเป็น bug จริงจาก `/`
- [ ] **S7 · เปิด Firebase App Check**
  บล็อก client ที่ไม่ใช่แอปจริง (API key อยู่ใน APK ที่แจกผ่าน Line อยู่แล้ว)
- [ ] **S8 · ขึ้น Play Store internal testing track**
  แก้ปัญหา APK ค้างเวอร์ชันถาวร — ตอนนี้ rules ต้อง backward-compatible ตลอดกาล
- [ ] **S9 · SOS re-escalation (timeout → ส่งต่อ)**
  scheduled function: ไม่มีคนรับ 3 นาที → แจ้งซ้ำ + admin · 6 นาที → on-call + เตือนผู้ป่วยให้โทร 1669
- [ ] **S10 · CI (analyze + test) + unit/service/widget test**
  `core/` pure functions, `BookingOutcome` ทุกกรณี, `AuthGate` routing 3 roles
  ⚠️ `thaiBuddhistDate` ต้อง byte-match กับ `bangkokThaiDateString` ฝั่ง TS
- [ ] **S11 · เวลารอโดยประมาณ + แจ้งเตือนล่วงหน้า**
  "อีกประมาณ 25 นาที" มีความหมายกว่า "คิวที่ 12" · เตือนคืนก่อนนัด + ก่อนถึงคิว 3 คิว
- [ ] **S12 · `statusCode` enum แทนข้อความไทยใน Firestore**
  ตอนนี้แก้ค่าไม่ได้ตลอดกาล, พิมพ์ผิด = สถานะใหม่เงียบ ๆ, i18n ไม่ได้
- [ ] **S13 · Flow เลื่อนนัด (reschedule)**
  ตอนนี้ต้องยกเลิกแล้วจองใหม่ = เสี่ยงเสีย slot ให้คนอื่นระหว่างทาง

---

## 🟢 Nice to have

- [ ] **N1 · `departments` / `doctors` เป็น collection จริง** (ตอนนี้ `doctor` เป็น string ลอย ๆ ไม่ผูก uid)
- [ ] **N2 · Caregiver / ญาติจองแทน** — แยก `patients` ออกจาก `users` + ตาราง `patient_access` (ต้องมี S1 ก่อน)
- [ ] **N3 · Export ข้อมูลตัวเอง + retention policy อัตโนมัติ** (สิทธิเจ้าของข้อมูลตาม PDPA)
- [ ] **N4 · Admin dashboard** — วันนี้กี่คิว เสร็จเท่าไร SOS ค้างกี่เคส + หน้าดู audit log
- [ ] **N5 · QR เช็คอินที่สถานี + ผูก ESP32 เข้ากับสถานะคิว** (เครื่องออฟไลน์ตอนมีคิวรอ → ต้องแจ้งเตือน)
- [ ] **N6 · UX ผู้สูงอายุเพิ่มเติม** — onboarding 3 หน้าจอ, ปรับขนาดตัวอักษรในแอป, สั่น/เสียงยืนยันตอนกด SOS
- [ ] **N7 · เชื่อม HIS / เวชระเบียนเดิม** (ต้องรู้ก่อนว่าใช้ HN อยู่แล้วหรือไม่)

---

## ลำดับการทำงานที่แนะนำ

| ช่วง | งาน | หมายเหตุ |
|---|---|---|
| **วันนี้** | M1 (หยุดเลือด 1 บรรทัด), M3 | ลดความเสี่ยงมากที่สุดต่อแรงที่ลง |
| **สัปดาห์ 1** | M8 → M2 → M9 | M2 ติดที่การเปิด Blaze |
| **สัปดาห์ 2–3** | **M7 → M4** → M6 → M5 → M1 (ส่วน token) | M7 ต้องมาก่อน M4 เสมอ |
| **เดือน 1–3** | S1 → S4 → S2 → S3 → (S5 + S6 + S12 รอบเดียว) → S10 → S7 → S8 → S9 → S11 → S13 | S1 มาก่อน เพราะทุกอย่างหลังจากนี้ควรถูก log |
| **เดือน 3–12** | N1 → N2 → N3 → N5 → N4 → N6 → N7 | |

## คำถามที่ต้องได้คำตอบก่อนวางแผนละเอียด

1. ใช้กับผู้ป่วยจริงกี่คน สถานีเดียวหรือหลายแห่ง เมื่อไร
2. ใครคือผู้ควบคุมข้อมูลส่วนบุคคลตาม PDPA · ต้องเก็บเวชระเบียนกี่ปี
3. เป็นโปรเจกต์การศึกษา หรือใช้จริงในหน่วยบริการ
4. SOS มีคนเฝ้า 24 ชม. หรือเฉพาะเวลาราชการ
5. ผู้ป่วยใช้มือถือเอง หรือญาติเป็นคนใช้
6. มี HIS / HN เดิมที่ต้องเชื่อมหรือไม่
7. ใครรับผิดชอบค่าใช้จ่าย Firebase Blaze
8. จะขึ้น Play Store หรือแจก APK ต่อไป
9. ESP32 วัดอะไร (ถ้าเป็นสัญญาณชีพ = ข้อมูลสุขภาพเพิ่มอีกชุดใต้ PDPA)
10. มีใครดูแลระบบต่อหลังจากนี้
