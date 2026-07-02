# UX/UI Improvement Design — Healthcare Queue App

Date: 2026-07-02
Scope: `lib/main.dart` (single-file app per CLAUDE.md; no file splitting)
Visual identity: **kept** — primaryGreen `#186B44`, Noto Sans Thai / Playfair Display / Prompt, gradient 3D icons. This is a refinement pass, not a redesign.

## Context

A 2026-07-01 audit (`รีวิวสิ่งที่ควรปรับ.md`) flagged UX gaps: no booking confirmation, no success screen with the queue number, small text for elderly users, conflated empty/error states, raw `e.toString()` errors, and no search/filter or call-next on staff screens. The user chose a full UX pass across four areas (booking flow, elderly accessibility, visual polish, staff screens) using **Approach A**: keep the one-page booking form, add a confirmation bottom sheet and a success screen.

**Sequencing constraint:** a security PR (from the approved Ultraplan cloud session) is landing changes to `lib/main.dart` — transaction-based booking (`queue_days` counter), `FieldValue.serverTimestamp()`, Firestore rules. **Implementation of this design starts only after that PR merges**, and the confirmation sheet must call the new transactional booking function. All Thai status strings and Firestore field names remain exactly as-is.

## 1. Patient booking flow (Approach A)

- **Booking page (same single page).** Numbered Thai section headers ("1. เลือกเจ้าหน้าที่", "2. เลือกวันที่", "3. เลือกเวลา", "4. หมายเหตุ (ถ้ามี)"), generous spacing between sections, selection chips ≥48px tall with selected state = primaryGreen fill + white text. Full-width 56px submit button pinned at bottom; while requirements are incomplete it is disabled **with hint text** stating what's missing (e.g. "กรุณาเลือกเวลา").
- **Confirmation bottom sheet.** จองคิว opens a modal bottom sheet summarizing in large text: staff name + photo, Thai Buddhist date ("ศุกร์ 4 ก.ค. 2569"), time, notes. Buttons: big green ยืนยันการจอง (56px) + plain ยกเลิก. The Firestore write (the new transaction) fires only from this sheet; confirm button shows spinner and disables while in flight.
- **Success screen.** Full screen after success: green check, "จองคิวสำเร็จ", queue number huge in Prompt font (e.g. 015), card with date/time/staff/machine, buttons "ดูคิวของฉัน" (jump to คิวของฉัน tab) and "กลับหน้าแรก".
- **Failure handling.** If the transaction fails (slot taken/full), the sheet shows a friendly Thai error with a "เลือกเวลาใหม่" action. No raw exception text.

## 2. Elderly-friendly accessibility

- **Text scaling:** MediaQuery wrapper respecting system text scale clamped to 1.0–1.4; no user-facing body text below 14; key info (queue number, date/time, button labels) 16–20+.
- **Touch targets:** every tappable control ≥48×48 via `minimumSize`/`visualDensity`/padding. Bottom-nav labels always visible.
- **Contrast:** secondary text ≥ `textDark.withValues(alpha: 0.65)`; status chips always white-on-dark or dark-on-light.
- **Language clarity:** actionable empty states (e.g. "ยังไม่มีคิว — กดปุ่มด้านล่างเพื่อจองคิวแรกของคุณ"); all user-facing errors mapped to plain Thai with a retry button.

## 3. Visual polish + shared helpers (in main.dart)

- **Design tokens:** constants near the existing colors — `kRadius = 16`, `kCardPadding = 16`, gap steps 8/12/16/24, shared Noto Sans Thai `TextStyle` getters (title/body/caption). Screens use these instead of magic numbers.
- **`statusInfo(String status)` helper:** returns `(color, icon, label)` for กำลังรอ (amber), เรียกคิว (blue), กำลังรักษา (primaryGreen), เสร็จสิ้น (grey-green), ยกเลิก (red). Replaces duplicated mappings in HomeScreen, ActiveQueueScreen, StaffQueueScreen, history screens.
- **Card consistency:** one radius, one padding, one soft shadow everywhere.
- **Home screen hierarchy:** greeting + tagline "จองคิวกายภาพบำบัด" (states the app's purpose), current-queue card most prominent, then actions, then machine status.
- **Reusable state widget:** icon + one-line Thai message + optional retry, used by every StreamBuilder/FutureBuilder; distinguishes "ไม่มีข้อมูล" (empty) from "โหลดไม่สำเร็จ ลองอีกครั้ง" (error).

## 4. Staff screens

- **StaffQueueScreen:** date selector defaulting to today (chips: วันนี้ / พรุ่งนี้ / เลือกวัน) so the query is per-day (fewer reads); search field filtering the day's list client-side by patient name or queue number; status filter chips (ทั้งหมด / กำลังรอ / เรียกคิว / กำลังรักษา / เสร็จสิ้น).
- **เรียกคิวถัดไป button:** pinned; finds lowest-numbered กำลังรอ appointment for the selected day, confirms ("เรียกคิวหมายเลข 015 — คุณสมชาย?"), then sets status เรียกคิว.
- **Status change safety:** every status change confirms; cancel/complete shows a ~5s undo snackbar that reverts. (Full audit log stays out of scope.)
- **StaffSOSScreen:** pending alerts in red high-attention cards, newest first, one-tap "รับเรื่องแล้ว" with confirmation. Escalation/calling out of scope.

## Out of scope

Departments/patients/caregivers data model, notifications, Cloud Functions, audit logs, photo storage migration, multi-step wizard, automated tests (verification is `flutter analyze` + manual run per CLAUDE.md).

## Error handling

All Firestore/network failures surface via the reusable error-state widget or a mapped Thai snackbar with retry; exceptions are never shown raw. Booking failures are handled in the confirmation sheet as described above.

## Verification

1. `flutter analyze` clean after each change set.
2. Run the app (`flutter run`): book a queue end-to-end — hint text on incomplete form → confirmation sheet → success screen with correct queue number → visible in คิวของฉัน.
3. Set device text scale to max: booking page, home, and queue cards remain usable/unclipped.
4. As staff: today filter default, search by name, status chips, call-next flow with confirmation, undo after cancel.
5. Simulate a booking failure (airplane mode mid-confirm): friendly Thai error, retry works.
