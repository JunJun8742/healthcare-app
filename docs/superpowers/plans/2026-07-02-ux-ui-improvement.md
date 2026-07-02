# UX/UI Improvement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the approved UX/UI spec (`docs/superpowers/specs/2026-07-02-ux-ui-improvement-design.md`): refined booking flow with confirmation sheet + success screen, elderly-friendly accessibility, shared design tokens/status helper, and staff queue filters/call-next/undo.

**Architecture:** All changes live in `lib/main.dart` (single-file app per CLAUDE.md — do NOT split files). New shared helpers go near the existing color constants at the top; new screens/widgets are added as top-level classes following the existing section-comment style (`// ===== ... =====`).

**Tech Stack:** Flutter (Material 3), Firebase Auth, Cloud Firestore, google_fonts (Noto Sans Thai / Prompt).

## Global Constraints

- **PREREQUISITE: the security PR (Firestore transaction booking via `queue_days` counter, `FieldValue.serverTimestamp()`, firestore.rules) must be merged before starting.** Task 4 calls the transactional booking function that PR introduces; before Task 1, run `git log --oneline -10` and confirm that PR's commit is present. If not, STOP and report.
- Line numbers below are pre-PR anchors — locate code by class/method name, not line number.
- All Thai status strings stored in Firestore stay byte-identical: `กำลังรอ`, `เรียกคิว`, `กำลังรักษา`, `เสร็จสิ้น`, `ยกเลิก`.
- All Firestore field names stay unchanged (`patientUid`, `queueNo`, `doctor`, `staffUid`, `date`, `time`, `status`, `machineId`, `machineName`, `notes`).
- Use `.withValues(alpha: ...)`, never `.withOpacity(...)`.
- Keep visual identity: primaryGreen `#186B44`, existing gradient `[Color(0xff1b4332), Color(0xff52b788)]`, Noto Sans Thai body, Prompt for queue numbers.
- No `test/` directory exists; verification for every task = `flutter analyze` (must be clean) + the manual check listed in the task. Do not create a test directory.
- All user-facing strings in Thai. Never show `e.toString()` to users.
- Commit after each task with the trailer `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 1: Design tokens, text styles, statusInfo helper, StateMessage widget

**Files:**
- Modify: `lib/main.dart` — insert immediately after the color constants (`const Color textDark = ...`, ~line 23).

**Interfaces:**
- Produces (used by all later tasks):
  - `const double kRadius = 16;`, `const double kCardPadding = 16;`, `const double kGapS = 8;`, `kGapM = 12;`, `kGapL = 16;`, `kGapXL = 24;`
  - `TextStyle tTitle([Color? c])`, `TextStyle tBody([Color? c])`, `TextStyle tCaption([Color? c])`
  - `({Color color, IconData icon, String label}) statusInfo(String status)`
  - `class StateMessage extends StatelessWidget` — `StateMessage({required IconData icon, required String message, VoidCallback? onRetry})`

- [ ] **Step 1: Add tokens and helpers**

Insert after the color constants:

```dart
// ===== Design tokens =====
const double kRadius = 16;
const double kCardPadding = 16;
const double kGapS = 8;
const double kGapM = 12;
const double kGapL = 16;
const double kGapXL = 24;
const Color textSecondary = Color(0xa62d312f); // textDark @ 65%

TextStyle tTitle([Color? c]) => GoogleFonts.notoSansThai(fontSize: 18, fontWeight: FontWeight.bold, color: c ?? textDark);
TextStyle tBody([Color? c]) => GoogleFonts.notoSansThai(fontSize: 15, color: c ?? textDark);
TextStyle tCaption([Color? c]) => GoogleFonts.notoSansThai(fontSize: 14, color: c ?? textSecondary);

// ===== สถานะคิว: สี/ไอคอน/ป้ายชื่อ ใช้ร่วมกันทุกหน้า =====
({Color color, IconData icon, String label}) statusInfo(String status) {
  switch (status) {
    case 'กำลังรอ':
      return (color: const Color(0xffB7791F), icon: Icons.hourglass_top_rounded, label: 'กำลังรอ');
    case 'เรียกคิว':
      return (color: const Color(0xff1D4ED8), icon: Icons.campaign_rounded, label: 'เรียกคิว');
    case 'กำลังรักษา':
      return (color: primaryGreen, icon: Icons.healing_rounded, label: 'กำลังรักษา');
    case 'เสร็จสิ้น':
      return (color: const Color(0xff4B6358), icon: Icons.check_circle_rounded, label: 'เสร็จสิ้น');
    case 'ยกเลิก':
      return (color: const Color(0xffB91C1C), icon: Icons.cancel_rounded, label: 'ยกเลิก');
    default:
      return (color: textSecondary, icon: Icons.help_outline_rounded, label: status);
  }
}

// ===== Empty/Error state ที่ใช้ร่วมกัน =====
class StateMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  final VoidCallback? onRetry;
  const StateMessage({super.key, required this.icon, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(kGapXL),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: textSecondary),
          const SizedBox(height: kGapM),
          Text(message, style: tBody(textSecondary), textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: kGapL),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryGreen, foregroundColor: Colors.white,
                minimumSize: const Size(160, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
              ),
              onPressed: onRetry,
              child: Text('ลองอีกครั้ง', style: GoogleFonts.notoSansThai(fontWeight: FontWeight.w600)),
            ),
          ],
        ]),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify** — Run `flutter analyze`. Expected: no errors (unused-element warnings for not-yet-used helpers are acceptable this task only).

- [ ] **Step 3: Commit** — `git add lib/main.dart && git commit -m "feat: add design tokens, statusInfo helper, StateMessage widget"`

---

### Task 2: Text scaling clamp + minimum touch-target theme

**Files:**
- Modify: `lib/main.dart` — `HealthcareStation` widget (~line 27), its `MaterialApp`.

**Interfaces:**
- Consumes: nothing new. Produces: app-wide `MediaQuery` clamp; later tasks assume text scale 1.0–1.4 works.

- [ ] **Step 1: Wrap MaterialApp builder with clamped text scaling**

In `HealthcareStation.build`, add a `builder` to the existing `MaterialApp` (keep all existing properties):

```dart
builder: (context, child) {
  final mq = MediaQuery.of(context);
  final clamped = mq.textScaler.clamp(minScaleFactor: 1.0, maxScaleFactor: 1.4);
  return MediaQuery(data: mq.copyWith(textScaler: clamped), child: child!);
},
```

- [ ] **Step 2: Raise minimum interactive sizes in theme** — In the `ThemeData` of the same `MaterialApp`, add (merging with existing theme properties, do not delete existing ones):

```dart
materialTapTargetSize: MaterialTapTargetSize.padded,
```

- [ ] **Step 3: Verify** — `flutter analyze` clean. Manual: `flutter run`, set device font size to largest — login and home screens render without clipped text.

- [ ] **Step 4: Commit** — `git commit -am "feat: clamp text scaling 1.0-1.4 and pad tap targets"`

---

### Task 3: Booking page refinements (headers, chips, submit hint)

**Files:**
- Modify: `lib/main.dart` — `_BookingScreenState.build` (~line 1408 onward) and its `_bookingCard` helper.

**Interfaces:**
- Consumes: tokens from Task 1. Produces: `bool get _canSubmit` and `String get _missingHint` on `_BookingScreenState`, used by Task 4.

- [ ] **Step 1: Add readiness getters** to `_BookingScreenState`:

```dart
bool get _canSubmit => staffList.isNotEmpty && availableTimes.isNotEmpty && !loadingTimes && !loadingStaff;

String get _missingHint {
  if (loadingStaff || loadingTimes) return 'กำลังโหลดข้อมูล...';
  if (staffList.isEmpty) return 'ยังไม่มีเจ้าหน้าที่ให้เลือก';
  if (availableTimes.isEmpty) return 'ไม่มีเวลาว่างในวันนี้ กรุณาเลือกวันอื่น';
  return '';
}
```

- [ ] **Step 2: Update section headers** — In the `_bookingCard` calls, change titles to numbered form: `'1. เลือกวันที่นัดหมาย'`, `'2. เลือกเจ้าหน้าที่'`, `'3. เลือกเวลา'`, `'4. หมายเหตุ (ถ้ามี)'` (match existing order in the file; number by on-screen order). Use `tTitle()` for the header text style inside `_bookingCard` and increase inter-card spacing to `kGapXL`.

- [ ] **Step 3: Enlarge selection chips** — Wherever date/time/staff chips are built in this screen, enforce `constraints: const BoxConstraints(minHeight: 48)` (or padding achieving ≥48px height) and selected style = solid `primaryGreen` background with white bold text; unselected = white background, `textDark` text, `lightGreen` border.

- [ ] **Step 4: Submit button with hint** — Replace the existing submit button area with a bottom-pinned container:

```dart
Container(
  color: Colors.white,
  padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
  child: Column(mainAxisSize: MainAxisSize.min, children: [
    if (!_canSubmit)
      Padding(
        padding: const EdgeInsets.only(bottom: kGapS),
        child: Text(_missingHint, style: tCaption(const Color(0xffB7791F))),
      ),
    SizedBox(
      width: double.infinity, height: 56,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryGreen, foregroundColor: Colors.white,
          disabledBackgroundColor: primaryGreen.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
        ),
        onPressed: _canSubmit && !isSubmitting ? _showConfirmSheet : null,
        child: Text('จองคิว', style: GoogleFonts.notoSansThai(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
    ),
  ]),
)
```

(`_showConfirmSheet` is created in Task 4; for this task's intermediate commit, point `onPressed` at the existing `submitBooking` and switch it in Task 4.)

- [ ] **Step 5: Verify** — `flutter analyze` clean. Manual: open booking screen; headers numbered, chips large, hint appears when no times available.

- [ ] **Step 6: Commit** — `git commit -am "feat: booking page numbered steps, large chips, submit hint"`

---

### Task 4: Confirmation bottom sheet

**Files:**
- Modify: `lib/main.dart` — `_BookingScreenState` (add `_showConfirmSheet`, modify `submitBooking`).

**Interfaces:**
- Consumes: `_canSubmit` (Task 3); the **transactional booking function from the security PR** — locate the post-PR booking implementation inside `submitBooking` (it will use `FirebaseFirestore.instance.runTransaction` and a `queue_days` counter). Do not reintroduce the old count-based logic.
- Produces: `submitBooking` now returns `Future<String?>` — the assigned `queueNo` on success, `null` on handled failure — consumed by Task 5.

- [ ] **Step 1: Add `_showConfirmSheet`**

```dart
void _showConfirmSheet() {
  final staff = staffList[selectedStaffIndex];
  final dateStr = _fmt(upcomingDays[selectedDateIndex]);
  final time = availableTimes[selectedTimeIndex];
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheetCtx) {
      bool submitting = false;
      String? error;
      return StatefulBuilder(builder: (sheetCtx, setSheet) {
        Widget row(IconData ic, String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Icon(ic, color: primaryGreen, size: 22),
            const SizedBox(width: kGapM),
            Text(label, style: tCaption()),
            const Spacer(),
            Flexible(child: Text(value, style: GoogleFonts.notoSansThai(fontSize: 16, fontWeight: FontWeight.w600, color: textDark), textAlign: TextAlign.end)),
          ]),
        );
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('ยืนยันการจองคิว', style: tTitle(), textAlign: TextAlign.center),
            const SizedBox(height: kGapL),
            row(Icons.person_rounded, 'เจ้าหน้าที่', staff['fullname'] ?? 'นักกายภาพ'),
            row(Icons.calendar_month_rounded, 'วันที่', dateStr),
            row(Icons.access_time_rounded, 'เวลา', time),
            if (error != null) ...[
              const SizedBox(height: kGapM),
              Text(error!, style: tCaption(const Color(0xffB91C1C)), textAlign: TextAlign.center),
            ],
            const SizedBox(height: kGapXL),
            SizedBox(height: 56, child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: primaryGreen, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius))),
              onPressed: submitting ? null : () async {
                setSheet(() { submitting = true; error = null; });
                final qNo = await submitBooking();
                if (!sheetCtx.mounted) return;
                if (qNo != null) {
                  Navigator.pop(sheetCtx);
                } else {
                  setSheet(() { submitting = false; error = 'จองไม่สำเร็จ ช่วงเวลานี้อาจถูกจองแล้ว กรุณาเลือกเวลาใหม่'; });
                  _loadAvailability();
                }
              },
              child: submitting
                  ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                  : Text('ยืนยันการจอง', style: GoogleFonts.notoSansThai(fontSize: 18, fontWeight: FontWeight.bold)),
            )),
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(sheetCtx),
              child: Text('ยกเลิก', style: tBody(textSecondary)),
            ),
          ]),
        );
      });
    },
  );
}
```

- [ ] **Step 2: Rework `submitBooking` to return the queue number** — Keep the security PR's transaction exactly as merged; change the signature to `Future<String?> submitBooking()`, return the assigned `queueNo` string after a successful transaction, and on any caught exception return `null` (keep the "already has active queue" pre-check → show the existing orange snackbar and return `null`). Remove the raw `e.toString()` snackbar and the old success snackbar/navigation — navigation moves to Task 5's success screen. Wire Task 3's button to `_showConfirmSheet`.

- [ ] **Step 3: Verify** — `flutter analyze` clean. Manual: book a queue — sheet shows staff/date/time; confirm shows spinner; sheet closes on success.

- [ ] **Step 4: Commit** — `git commit -am "feat: booking confirmation bottom sheet with in-sheet error handling"`

---

### Task 5: Success screen

**Files:**
- Modify: `lib/main.dart` — add `BookingSuccessScreen` class after `BookingScreen`'s closing brace; modify `_showConfirmSheet`'s success branch.

**Interfaces:**
- Consumes: `submitBooking() → Future<String?>` (Task 4), tokens (Task 1).
- Produces: `BookingSuccessScreen({required String queueNo, required String doctor, required String date, required String time, required String machineName})`.

- [ ] **Step 1: Add the screen**

```dart
// ==========================================
// 6.5 Booking Success Screen
// ==========================================
class BookingSuccessScreen extends StatelessWidget {
  final String queueNo, doctor, date, time, machineName;
  const BookingSuccessScreen({super.key, required this.queueNo, required this.doctor, required this.date, required this.time, required this.machineName});

  @override
  Widget build(BuildContext context) {
    Widget row(IconData ic, String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(ic, color: primaryGreen, size: 22),
        const SizedBox(width: kGapM),
        Text(label, style: tCaption()),
        const Spacer(),
        Flexible(child: Text(value, style: GoogleFonts.notoSansThai(fontSize: 16, fontWeight: FontWeight.w600, color: textDark), textAlign: TextAlign.end)),
      ]),
    );
    return Scaffold(
      backgroundColor: bgWhite,
      body: SafeArea(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          const Spacer(),
          Container(
            width: 96, height: 96,
            decoration: BoxDecoration(color: lightGreen, shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded, color: primaryGreen, size: 60),
          ),
          const SizedBox(height: kGapL),
          Text('จองคิวสำเร็จ', style: GoogleFonts.notoSansThai(fontSize: 24, fontWeight: FontWeight.bold, color: primaryGreen)),
          const SizedBox(height: kGapM),
          Text('หมายเลขคิวของคุณ', style: tCaption()),
          Text(queueNo, style: GoogleFonts.prompt(fontSize: 72, fontWeight: FontWeight.bold, color: primaryGreen)),
          const SizedBox(height: kGapL),
          Container(
            padding: const EdgeInsets.all(kCardPadding),
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(kRadius),
              boxShadow: [BoxShadow(color: primaryGreen.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 6))],
            ),
            child: Column(children: [
              row(Icons.person_rounded, 'เจ้าหน้าที่', doctor),
              row(Icons.calendar_month_rounded, 'วันที่', date),
              row(Icons.access_time_rounded, 'เวลา', time),
              if (machineName.isNotEmpty) row(Icons.precision_manufacturing_rounded, 'เครื่อง', machineName),
            ]),
          ),
          const Spacer(),
          SizedBox(width: double.infinity, height: 56, child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: primaryGreen, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius))),
            onPressed: () => Navigator.pushAndRemoveUntil(context,
              MaterialPageRoute(builder: (_) => const MainNavigation(initialIndex: 1)), (r) => false),
            child: Text('ดูคิวของฉัน', style: GoogleFonts.notoSansThai(fontSize: 18, fontWeight: FontWeight.bold)),
          )),
          const SizedBox(height: kGapM),
          TextButton(
            onPressed: () => Navigator.pushAndRemoveUntil(context,
              MaterialPageRoute(builder: (_) => const MainNavigation()), (r) => false),
            child: Text('กลับหน้าแรก', style: tBody(textSecondary)),
          ),
        ]),
      )),
    );
  }
}
```

- [ ] **Step 2: Support `initialIndex` on MainNavigation** — `MainNavigation` (~line 955) currently has no tab parameter. Add `final int initialIndex;` with `const MainNavigation({super.key, this.initialIndex = 0});` and initialize the state's selected-tab field from `widget.initialIndex` in `initState`.

- [ ] **Step 3: Navigate on success** — In `_showConfirmSheet`'s success branch (Task 4), after `Navigator.pop(sheetCtx)`, push the success screen from the page context:

```dart
if (!mounted) return;
Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => BookingSuccessScreen(
  queueNo: qNo,
  doctor: staffList[selectedStaffIndex]['fullname'] ?? 'นักกายภาพ',
  date: _fmt(upcomingDays[selectedDateIndex]),
  time: availableTimes[selectedTimeIndex],
  machineName: selectedMachineName,
)), (r) => false);
```

- [ ] **Step 4: Verify** — `flutter analyze` clean. Manual: complete a booking → success screen shows big queue number; both buttons land on the right tab.

- [ ] **Step 5: Commit** — `git commit -am "feat: booking success screen with queue number"`

---

### Task 6: Home screen hierarchy, contrast, empty/error states

**Files:**
- Modify: `lib/main.dart` — `HomeScreen` (~line 992–1295), `ActiveQueueScreen` (~1689), `HistoryScreen` (~1897).

**Interfaces:**
- Consumes: `statusInfo`, `StateMessage`, tokens, `textSecondary` (Task 1).

- [ ] **Step 1: Tagline** — In `HomeScreen`'s header/greeting area, add directly under the greeting: `Text('จองคิวกายภาพบำบัด', style: tCaption())`.

- [ ] **Step 2: Contrast sweep in these three screens** — Replace `color: Colors.grey` / `Colors.grey.shade400..600` on text with `textSecondary`. Raise any user-facing `fontSize:` below 14 to 14 (e.g. `HomeScreen` line 1142 caption 12→14, `_serviceCard` title 11→13 minimum given 3-column width — use 13 there and note it as the single allowed exception since the label is duplicated by the icon).

- [ ] **Step 3: Status chips via statusInfo** — In `HomeScreen`'s current-queue card, `ActiveQueueScreen`, and `HistoryScreen`, find each place a status string is mapped to a color/icon (search `'กำลังรอ'` etc. within these classes) and replace the local mapping with `final s = statusInfo(status);` using `s.color`, `s.icon`, `s.label`.

- [ ] **Step 4: Empty/error states** — In each `StreamBuilder`/`FutureBuilder` in these three screens: on `snapshot.hasError`, return `StateMessage(icon: Icons.wifi_off_rounded, message: 'โหลดข้อมูลไม่สำเร็จ ลองอีกครั้ง', onRetry: ...)` (for StatefulWidget screens call `setState((){})`; for `StreamBuilder` on Firestore streams where retry is automatic, omit `onRetry`). On empty data, keep/introduce a distinct empty message; `HomeScreen`'s "ยังไม่มีคิว" card copy becomes: `'ยังไม่มีคิว — กดปุ่มด้านล่างเพื่อจองคิวแรกของคุณ'`.

- [ ] **Step 5: Verify** — `flutter analyze` clean. Manual: home shows tagline; airplane mode shows error state, not blank/empty text.

- [ ] **Step 6: Commit** — `git commit -am "feat: home hierarchy, shared status chips, empty/error states"`

---

### Task 7: Staff queue — day filter, search, status chips

**Files:**
- Modify: `lib/main.dart` — `StaffQueueScreen` (~line 2259). Convert from `StatelessWidget` to `StatefulWidget` (filter state lives here).

**Interfaces:**
- Consumes: `statusInfo`, `StateMessage`, tokens, `_fmt`-style Buddhist date format (`dd/MM/yyyy+543` — reuse the exact format used when appointments are written; define a local `String _fmtDate(DateTime d)` identical to `_BookingScreenState._fmt`).
- Produces: state fields `DateTime selectedDay`, `String searchQuery`, `String statusFilter` ('' = all) used by Task 8.

- [ ] **Step 1: Convert to StatefulWidget** with state:

```dart
DateTime selectedDay = DateTime.now();
String searchQuery = '';
String statusFilter = ''; // '' = ทั้งหมด
String _fmtDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year + 543}';
```

- [ ] **Step 2: Day-scoped query** — Change the screen's appointments stream to `FirebaseFirestore.instance.collection('appointments').where('date', isEqualTo: _fmtDate(selectedDay)).snapshots()` (single `where` — no composite index needed; keep existing client-side `createdAt` sort).

- [ ] **Step 3: Day selector UI** — Above the list, a row of `ChoiceChip`s: `วันนี้` (today), `พรุ่งนี้` (today+1), and `เลือกวัน` which opens `showDatePicker` (firstDate: today−30d, lastDate: today+30d, locale Thai if app localization allows, otherwise default). Selecting updates `selectedDay` via `setState`. Chips ≥48px tall, selected = primaryGreen fill/white text.

- [ ] **Step 4: Search field + status chips** —

```dart
TextField(
  onChanged: (v) => setState(() => searchQuery = v.trim()),
  style: tBody(),
  decoration: InputDecoration(
    hintText: 'ค้นหาชื่อผู้ป่วยหรือเลขคิว',
    hintStyle: tCaption(),
    prefixIcon: const Icon(Icons.search_rounded, color: primaryGreen),
    filled: true, fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(vertical: 14),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(kRadius), borderSide: BorderSide.none),
  ),
),
```

Below it, horizontal `ChoiceChip` list for `['', 'กำลังรอ', 'เรียกคิว', 'กำลังรักษา', 'เสร็จสิ้น']` labeled `ทั้งหมด` for `''`, colored with `statusInfo`. Filter client-side:

```dart
final filtered = docs.where((d) {
  final m = d.data() as Map<String, dynamic>;
  final okStatus = statusFilter.isEmpty || m['status'] == statusFilter;
  final q = searchQuery.toLowerCase();
  final okSearch = q.isEmpty ||
      (m['patientName'] ?? '').toString().toLowerCase().contains(q) ||
      (m['queueNo'] ?? '').toString().contains(q);
  return okStatus && okSearch;
}).toList();
```

Empty result → `StateMessage(icon: Icons.inbox_rounded, message: 'ไม่พบคิวตามเงื่อนไขที่เลือก')`.

- [ ] **Step 5: Verify** — `flutter analyze` clean. Manual as staff: default shows today only; search and status chips filter live.

- [ ] **Step 6: Commit** — `git commit -am "feat: staff queue day filter, search, status filter chips"`

---

### Task 8: Call-next button, status-change confirmation, undo

**Files:**
- Modify: `lib/main.dart` — `StaffQueueScreen` (post-Task 7 stateful version).

**Interfaces:**
- Consumes: Task 7 state (`selectedDay`, `_fmtDate`), `statusInfo`. Status writes must use `FieldValue.serverTimestamp()` for any `updatedAt`-style fields, matching the security PR convention.

- [ ] **Step 1: Shared status updater with confirmation + undo**

```dart
Future<void> _changeStatus(BuildContext context, String docId, String queueNo, String patientName, String fromStatus, String toStatus) async {
  final s = statusInfo(toStatus);
  final ok = await showDialog<bool>(
    context: context,
    builder: (dCtx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('ยืนยันเปลี่ยนสถานะ', style: tTitle()),
      content: Text('เปลี่ยนคิว $queueNo — $patientName\nเป็น "${s.label}" ใช่หรือไม่?', style: tBody()),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dCtx, false), child: Text('ไม่ใช่', style: tBody(textSecondary))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: s.color, foregroundColor: Colors.white, minimumSize: const Size(100, 48)),
          onPressed: () => Navigator.pop(dCtx, true),
          child: const Text('ยืนยัน'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  await FirebaseFirestore.instance.collection('appointments').doc(docId).update({'status': toStatus, 'updatedAt': FieldValue.serverTimestamp()});
  if (!context.mounted) return;
  final undoable = toStatus == 'ยกเลิก' || toStatus == 'เสร็จสิ้น';
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text('เปลี่ยนสถานะคิว $queueNo เป็น ${s.label} แล้ว', style: GoogleFonts.notoSansThai()),
    backgroundColor: s.color,
    duration: const Duration(seconds: 5),
    action: undoable
        ? SnackBarAction(label: 'เลิกทำ', textColor: Colors.white, onPressed: () {
            FirebaseFirestore.instance.collection('appointments').doc(docId)
                .update({'status': fromStatus, 'updatedAt': FieldValue.serverTimestamp()});
          })
        : null,
  ));
}
```

Route every existing status-change button in this screen through `_changeStatus` (find current direct `.update({'status': ...})` calls in `StaffQueueScreen` and replace).

- [ ] **Step 2: Call-next button** — Pinned above the list (or as `floatingActionButton.extended`):

```dart
Future<void> _callNext(BuildContext context, List<QueryDocumentSnapshot> docs) async {
  final waiting = docs.where((d) => (d.data() as Map<String, dynamic>)['status'] == 'กำลังรอ').toList()
    ..sort((a, b) => ((a.data() as Map<String, dynamic>)['queueNo'] ?? '').toString()
        .compareTo(((b.data() as Map<String, dynamic>)['queueNo'] ?? '').toString()));
  if (waiting.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('ไม่มีคิวที่กำลังรอในวันนี้', style: GoogleFonts.notoSansThai()), backgroundColor: Colors.orange));
    return;
  }
  final m = waiting.first.data() as Map<String, dynamic>;
  await _changeStatus(context, waiting.first.id, m['queueNo'] ?? '', m['patientName'] ?? '', 'กำลังรอ', 'เรียกคิว');
}
```

Button: full-width 56px, primaryGreen, icon `Icons.campaign_rounded`, label `'เรียกคิวถัดไป'`. It operates on the **unfiltered** day list (`docs` before search/status filtering) so search state can't skip queues.

- [ ] **Step 3: Verify** — `flutter analyze` clean. Manual: call-next confirms lowest waiting queue; cancel/complete shows 5s undo which reverts.

- [ ] **Step 4: Commit** — `git commit -am "feat: staff call-next, status confirmation and undo"`

---

### Task 9: Staff SOS screen attention styling

**Files:**
- Modify: `lib/main.dart` — `StaffSOSScreen` (~line 2498).

**Interfaces:**
- Consumes: `StateMessage`, tokens. SOS status strings: keep whatever exact pending/resolved strings the class already uses (inspect the existing `where`/comparison values in `_StaffSOSScreenState` and reuse verbatim).

- [ ] **Step 1: Pending alert cards** — Pending alerts render with red styling: `Border.all(color: const Color(0xffB91C1C), width: 1.5)`, background `const Color(0xffFEF2F2)`, leading `_icon3D(Icons.sos_rounded, [Colors.red.shade300, Colors.red.shade700], 48)`, patient name in `tTitle()`. Sort pending newest-first by `createdAt` client-side (keep existing sort if already newest-first).

- [ ] **Step 2: One-tap acknowledge** — Each pending card gets a 48px-tall `ElevatedButton` `'รับเรื่องแล้ว'` (red bg, white text) that opens a confirm dialog (same pattern as Task 8's dialog, title `'ยืนยันรับเรื่อง SOS'`) and on confirm updates the alert to the screen's existing resolved status value + `resolvedAt: FieldValue.serverTimestamp()`.

- [ ] **Step 3: Empty state** — No pending alerts → `StateMessage(icon: Icons.verified_user_rounded, message: 'ไม่มีเหตุฉุกเฉินในขณะนี้')`.

- [ ] **Step 4: Verify** — `flutter analyze` clean. Manual: create SOS as patient; staff sees red card; acknowledge flow works and moves it out of pending.

- [ ] **Step 5: Commit** — `git commit -am "feat: high-attention SOS cards with acknowledge flow"`

---

### Task 10: Final sweep — raw errors, full verification

**Files:**
- Modify: `lib/main.dart` (whole file, targeted greps).

- [ ] **Step 1: Kill remaining raw errors** — `grep -n "e.toString()" lib/main.dart`; replace every user-facing occurrence with a plain-Thai message + appropriate `StateMessage`/snackbar (`'เกิดข้อผิดพลาด กรุณาลองใหม่'` as generic fallback; `'อินเทอร์เน็ตขัดข้อง กรุณาตรวจสอบการเชื่อมต่อ'` where a network error is likely). Log details with `debugPrint` instead.

- [ ] **Step 2: Full manual verification per spec** — run the app and walk the spec's 5 verification points (booking end-to-end, max text scale, staff filters/call-next/undo, SOS, airplane-mode failure).

- [ ] **Step 3: Final analyze + commit** — `flutter analyze` fully clean (no leftover unused-element warnings). `git commit -am "chore: replace raw error messages with Thai user-facing text"`.
