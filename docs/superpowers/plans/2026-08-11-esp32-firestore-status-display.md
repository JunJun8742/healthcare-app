# ESP32 → Firestore → Flutter Machine Status Display Implementation Plan

> **SUPERSEDED:** the user chose the HiveMQ-bridge architecture instead (App Check Enforcement compatibility). See `docs/superpowers/plans/2026-08-11-esp32-hivemq-bridge-status-display.md`. Kept for reference only — do not execute this plan.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ESP32 sends a periodic heartbeat (`is_active`, `last_updated`) directly to Firestore over HTTPS REST, and the Flutter app shows it live via the already-built `MachineStatusCard` widget.

**Architecture:** ESP32 firmware (Arduino core, `WiFiClientSecure` + `HTTPClient`) issues a `PATCH` request straight to the Firestore REST API document `machine_status/{machineId}`, using NTP-synced time for `last_updated`. No Cloud Function or MQTT broker is involved — `firestore.rules` already opens `machine_status` writes (restricted to exactly `is_active`/`last_updated`) to unauthenticated clients (commit `c35fc8a`), so the REST call needs nothing but the project's public web API key. This replaces the earlier HiveMQ/MQTT experiment, which had no bridge into Firestore at all. On the Flutter side, `MachineStatusCard` (`lib/core/widgets.dart`) already streams this doc and renders live/stale state — it just isn't placed on any screen yet, so this plan wires it into `HomeScreen`.

**Tech Stack:** Arduino/ESP32 (`WiFiClientSecure`, `HTTPClient`, `time.h` for NTP), Firestore REST API v1, Flutter `cloud_firestore` (existing `MachineStatusCard`).

## Global Constraints

- Firestore project ID: `heal-a49e3` (from `lib/firebase_options.dart`)
- Firestore doc path: `machine_status/{machineId}` — fields restricted to `is_active` (bool) and `last_updated` (Timestamp) only, per `firestore.rules:126-132`. Sending any other field makes the write get rejected by the rule.
- Staleness threshold: 30 seconds — `isMachineStale()` in `lib/core/format.dart:17`. Heartbeat interval must be well under this (plan uses 5s, matching the earlier Wokwi/HiveMQ sketch).
- All user-facing strings stay in Thai.
- Do not modify `firestore.rules`, `functions/src/index.ts`, or any collection other than `machine_status` — this feature needs none of them.
- The web API key (`AIzaSyDClqqlPEBLR_xN5ifdQdeP5Hub5HiJoU0`) is a public Firebase client key, not a secret — access control is entirely `firestore.rules`, not key secrecy. Safe to hardcode in firmware.

---

## File Structure

- `esp32/machine_status_heartbeat/machine_status_heartbeat.ino` — new ESP32 firmware sketch (Wokwi-compatible). New folder; no existing ESP32 code in this repo.
- `lib/features/patient/home_screen.dart` — modify: insert `MachineStatusCard` into the existing patient home screen layout.

No other files change. `firestore.rules` and `MachineStatusCard` itself are already correct/built.

---

### Task 1: Confirm Firestore rules are live on the real project

**Files:** `firestore.rules` (read-only verification, no edit expected)

**Interfaces:**
- Consumes: nothing
- Produces: confidence that `heal-a49e3` will actually accept the ESP32's writes before firmware is tested against it

- [ ] **Step 1: Re-read the current rule for `machine_status`**

Already confirmed in this session — `firestore.rules:126-132`:
```
match /machine_status/{id} {
  allow read: if isSignedIn();
  allow write: if request.resource.data.keys().hasOnly(['is_active', 'last_updated']);
}
```

- [ ] **Step 2: Deploy rules to make sure the live project matches the file**

Run from `healthcare-app/` (requires `firebase-tools` login already confirmed working, project `heal-a49e3`):

```bash
firebase deploy --only firestore:rules --project heal-a49e3
```

Expected: `✔ Deploy complete!` with no errors. This step only pushes rules — it does not touch app code, Cloud Functions, or data. **Confirm with the user before running this against the live project**, since it's a production rules deploy even though the content is unchanged.

- [ ] **Step 3: Spot-check with a throwaway curl write**

```bash
curl -X PATCH \
  "https://firestore.googleapis.com/v1/projects/heal-a49e3/databases/(default)/documents/machine_status/plan_test?key=AIzaSyDClqqlPEBLR_xN5ifdQdeP5Hub5HiJoU0" \
  -H "Content-Type: application/json" \
  -d '{"fields":{"is_active":{"booleanValue":true},"last_updated":{"timestampValue":"2026-08-11T00:00:00Z"}}}'
```

Expected: HTTP 200 with the document JSON echoed back. If this returns `403 PERMISSION_DENIED`, stop — the rule isn't live yet and Task 2's firmware will fail identically.

- [ ] **Step 4: Delete the throwaway doc**

```bash
curl -X DELETE \
  "https://firestore.googleapis.com/v1/projects/heal-a49e3/databases/(default)/documents/machine_status/plan_test?key=AIzaSyDClqqlPEBLR_xN5ifdQdeP5Hub5HiJoU0"
```

Expected: HTTP 200, empty body. This keeps the `plan_test` doc from confusing later manual testing.

---

### Task 2: ESP32 firmware — REST heartbeat sender

**Files:**
- Create: `esp32/machine_status_heartbeat/machine_status_heartbeat.ino`

**Interfaces:**
- Consumes: Firestore REST API v1 (`PATCH .../machine_status/{machineId}`), confirmed reachable by Task 1
- Produces: `machine_status/{machineId}` document with fields `is_active` (bool), `last_updated` (ISO-8601 UTC timestamp string) — consumed by Task 3's `MachineStatusCard`

- [ ] **Step 1: Write the sketch**

```cpp
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <time.h>

const char* ssid     = "Wokwi-GUEST";
const char* password = "";

// Firebase project heal-a49e3 (lib/firebase_options.dart) — public web API
// key, safe to embed. Write access is gated entirely by firestore.rules
// (machine_status allows unauthenticated writes restricted to
// is_active/last_updated only), not by key secrecy.
const char* apiKey    = "AIzaSyDClqqlPEBLR_xN5ifdQdeP5Hub5HiJoU0";
const char* projectId = "heal-a49e3";
const char* machineId = "current"; // เครื่องอื่นเปลี่ยนเป็น "machine_2" ฯลฯ

// ต้องถี่กว่า 30s stale timeout ใน lib/core/format.dart (isMachineStale)
const unsigned long heartbeatIntervalMs = 5000;
unsigned long lastSend = 0;

WiFiClientSecure secureClient;

String isoTimestampNow() {
  struct tm timeinfo;
  if (!getLocalTime(&timeinfo, 5000)) {
    return ""; // NTP ยังไม่ sync
  }
  char buf[25];
  strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%SZ", &timeinfo);
  return String(buf);
}

void sendHeartbeat(bool isActive) {
  String ts = isoTimestampNow();
  if (ts == "") {
    Serial.println("NTP ยังไม่ sync — ข้าม heartbeat รอบนี้");
    return;
  }

  String url = String("https://firestore.googleapis.com/v1/projects/") + projectId +
               "/databases/(default)/documents/machine_status/" + machineId +
               "?key=" + apiKey;

  String body = String("{\"fields\":{") +
                "\"is_active\":{\"booleanValue\":" + (isActive ? "true" : "false") + "}," +
                "\"last_updated\":{\"timestampValue\":\"" + ts + "\"}" +
                "}}";

  secureClient.setInsecure(); // Wokwi/dev only — ใช้ root CA cert จริงถ้าขึ้น production
  HTTPClient http;
  http.begin(secureClient, url);
  http.addHeader("Content-Type", "application/json");
  int code = http.PATCH(body);

  Serial.printf("PATCH %s -> %d\n", machineId, code);
  if (code > 0) {
    Serial.println(http.getString());
  } else {
    Serial.printf("HTTP error: %s\n", http.errorToString(code).c_str());
  }
  http.end();
}

void setup() {
  Serial.begin(115200);
  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi connected");

  configTime(0, 0, "pool.ntp.org", "time.nist.gov");
  Serial.println("รอ NTP sync...");
  struct tm timeinfo;
  while (!getLocalTime(&timeinfo, 5000)) {
    Serial.println("ยังไม่ sync ลองใหม่...");
  }
  Serial.println("NTP synced");
}

void loop() {
  if (millis() - lastSend >= heartbeatIntervalMs) {
    lastSend = millis();
    bool isActive = true; // TODO: ผูกกับ sensor/สถานะจริงของเครื่องภายหลัง
    sendHeartbeat(isActive);
  }
}
```

- [ ] **Step 2: Run in Wokwi and verify the serial log**

Open the sketch in the Wokwi simulator (ESP32 board), start the simulation.

Expected serial output within ~10s:
```
WiFi connected
รอ NTP sync...
NTP synced
PATCH current -> 200
{...document JSON with is_active:true and your last_updated...}
```

A `-> 200` every ~5s confirms the write succeeded. `-> -1` or `-> 0` means the TLS/HTTP request itself failed (check `http.errorToString`); `-> 403` means the rule rejected it (re-check Task 1).

- [ ] **Step 3: Verify the document directly in Firestore**

```bash
curl "https://firestore.googleapis.com/v1/projects/heal-a49e3/databases/(default)/documents/machine_status/current?key=AIzaSyDClqqlPEBLR_xN5ifdQdeP5Hub5HiJoU0"
```

Expected: JSON with `fields.is_active.booleanValue: true` and `fields.last_updated.timestampValue` updating on repeated calls a few seconds apart.

---

### Task 3: Wire `MachineStatusCard` into `HomeScreen`

**Files:**
- Modify: `lib/features/patient/home_screen.dart`

**Interfaces:**
- Consumes: `MachineStatusCard({String machineId = 'current', String machineName = 'เครื่องกายภาพบำบัด'})` — existing widget in `lib/core/widgets.dart:46`, already imported in `home_screen.dart` (`import 'package:healthcare_app/core/widgets.dart';`, line 8)
- Produces: nothing new for other tasks — this is the terminal display point

- [ ] **Step 1: Insert the card into the layout**

In `lib/features/patient/home_screen.dart`, inside the `Padding` at line 82's `Column` (`crossAxisAlignment: CrossAxisAlignment.start`), add the card right after the queue-card `StreamBuilder` block and its `SizedBox(height: 20)` (currently line 126), before the `// ===== Action Cards =====` comment:

```dart
                    const SizedBox(height: 20),

                    // ===== Machine Status (ESP32 heartbeat) =====
                    const MachineStatusCard(machineId: 'current', machineName: 'เครื่องกายภาพบำบัด'),

                    // ===== Action Cards =====
```

(This replaces the single `const SizedBox(height: 20)` currently at line 126 with the same `SizedBox` followed by the card — the card's own `margin: EdgeInsets.only(bottom: 16)` in `MachineStatusCard` already provides spacing before the action cards, so no extra `SizedBox` is needed after it.)

- [ ] **Step 2: Static-check**

Run: `flutter analyze`
Expected: no new errors/warnings introduced (baseline stays whatever it was before this change — see `flutter analyze` guidance in `CLAUDE.md`).

- [ ] **Step 3: Manual UI verification**

Run: `flutter run` (any target device), log in as a patient, land on `HomeScreen`.

Expected, in order as Task 2's ESP32 keeps running:
1. Before any heartbeat has ever arrived: card shows "ไม่ทราบสถานะ" / "ไม่พบข้อมูลจากเครื่อง" (orange)
2. Within a few seconds of the ESP32 sketch running: card flips to "เครื่องกำลังทำงาน" (green, pulsing dot) with an updating "อัปเดต: HH:MM น." timestamp
3. Stop the Wokwi simulation and wait 30+ seconds: card flips to "ไม่ทราบสถานะ" / "ไม่มีสัญญาณจากเครื่องนานกว่า 30 วินาที" (orange) — confirms `isMachineStale` staleness detection works against a real heartbeat source, not just the unit-tested pure function

- [ ] **Step 4: Commit**

```bash
git add lib/features/patient/home_screen.dart esp32/machine_status_heartbeat/machine_status_heartbeat.ino
git commit -m "feat: ESP32 REST heartbeat -> Firestore -> MachineStatusCard on HomeScreen"
```

---

## Self-Review Notes

- **Spec coverage:** REST-based ESP32→Firebase send (Task 2), display in Flutter (Task 3), end-to-end confirmation including staleness (Task 3 Step 3). Rules already satisfy the requirement (Task 1 only verifies/deploys, doesn't change them).
- **No placeholders:** firmware and Dart snippets are complete, copy-pasteable; the one `TODO` (binding `isActive` to a real sensor) is explicitly scoped out — this plan's goal is the transport + display path, not the machine's actual activity sensor, which doesn't exist yet in this codebase either.
- **Type/name consistency:** `machineId: 'current'` in Task 3 matches `MachineStatusCard`'s default and Task 2's firmware `machineId` constant; field names (`is_active`, `last_updated`) match `firestore.rules`, `isMachineStale`, and the firmware exactly throughout.
