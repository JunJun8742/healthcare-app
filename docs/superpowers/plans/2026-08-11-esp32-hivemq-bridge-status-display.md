# ESP32 → HiveMQ → Firestore Bridge → Flutter Machine Status Display Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ESP32 reads a physical slide switch (GPIO23) and publishes its ON/OFF state as a heartbeat over MQTT to HiveMQ Cloud; a small Node.js bridge subscribes and writes it into Firestore via the Admin SDK; the existing "เลือกเครื่องที่ใช้" machine picker on `BookingScreen` (Step 4) shows it live — no Flutter changes needed.

**Architecture:** `ESP32 (reads slide switch on GPIO23) --MQTT(TLS,8883)--> HiveMQ Cloud --MQTT subscribe--> Node bridge --Admin SDK--> Firestore machine_status/{machineId} --snapshots()--> BookingScreen's Step 4 machine picker`. The bridge is a standalone, always-running Node process (not a Cloud Function — Cloud Functions are ephemeral and unsuited to a held-open MQTT connection) that authenticates to Firestore with a service-account key, which **bypasses both `firestore.rules` and App Check entirely**. This is the deciding reason this architecture was chosen over direct ESP32→Firestore REST: the ESP32 never talks to Firebase at all, so turning on App Check Enforcement for Firestore later cannot break this path — only client SDKs and public REST calls are subject to App Check, not Admin SDK writes.

**Display note (discovered during planning, changes scope):** `BookingScreen` (`lib/features/patient/booking_screen.dart:338-399`) already has its own live machine-status picker — it streams the whole `machine_status` collection directly and does NOT use the `MachineStatusCard` widget at all. This means once the bridge writes `machine_status/1`, it shows up in the booking flow automatically with zero Flutter changes. The standalone `MachineStatusCard` widget (`lib/core/widgets.dart`) stays unused for now — wiring it into `HomeScreen` was dropped from this plan as unnecessary for this feature; it can be added later as a separate, purely additive task if wanted. `BookingScreen`'s picker reads a `name` field (`data['name'] ?? doc.id`) that the earlier REST-direct plan never wrote — this plan's bridge writes it so the picker shows a real Thai label instead of the raw doc ID `"1"`.

**Tech Stack:** Node.js (`mqtt`, `firebase-admin` packages) for the bridge; ESP32/Arduino (`PubSubClient`, `WiFiClientSecure`, digital input) for the sketch; Flutter `cloud_firestore` (existing `BookingScreen` machine picker — unmodified).

## Global Constraints

- Firestore project ID: `heal-a49e3` (from `lib/firebase_options.dart`)
- HiveMQ Cloud cluster (from the user's Wokwi sketch): host `66534f45e89543519c61f51c461045ee.s1.eu.hivemq.cloud`, port `8883` (MQTT+TLS), user `healthcare`, topic `machine/status/1`
- Wiring (confirmed by user): slide switch common pin → `3V3`, switch signal leg → ESP32 `GPIO23`, other leg unconnected. `GPIO23` reads `HIGH` when the switch is in the position that bridges to `3V3`, and reads `LOW` (via internal pull-down) when in the other position/floating. Two LEDs (green + blue) share a resistor into a separate GPIO, unrelated to this feature — not wired into the sketch below.
- ESP32 publishes `{"is_active": true/false}` to `machine/status/1` every 5s (reading the switch fresh on every publish), which is under the 30s staleness window
- Firestore doc path stays `machine_status/{machineId}`, fields `is_active` (bool) + `last_updated` (Timestamp) + `name` (string — new, needed by `BookingScreen`'s picker, see Display note above) — `is_active`/`last_updated` are the same contract `MachineStatusCard`/`isMachineStale` already expect (`lib/core/widgets.dart`, `lib/core/format.dart:17`); `BookingScreen` additionally reads `name` (`booking_screen.dart:351`)
- `machineId` is derived from the MQTT topic's last segment (`machine/status/1` → doc `machine_status/1`), so multiple machines work by just changing the ESP32's `topic` constant and client ID — no bridge code changes needed as long as the new machine's ID is added to the bridge's `MACHINE_NAMES` map (Task 2)
- Never commit the Firebase service-account key or HiveMQ password to git
- All user-facing strings stay in Thai
- Do not modify `firestore.rules`, `functions/src/index.ts`, or any Flutter file — `BookingScreen`'s existing picker already covers display, so this plan is backend-only

---

## File Structure

- `bridge/package.json` — new Node project for the MQTT→Firestore bridge
- `bridge/index.js` — the bridge itself: connects to HiveMQ, subscribes, writes Firestore on each message
- `bridge/service-account.json` — Firebase Admin credential (downloaded manually, gitignored, never committed)
- `.gitignore` (repo root) — add `bridge/node_modules/` and `bridge/service-account.json`
- `esp32/machine_status_switch/machine_status_switch.ino` — new ESP32/Wokwi sketch: reads the slide switch on GPIO23 and publishes it over MQTT (based on the user's original HiveMQ test sketch, switch-driven instead of hardcoded `true`)

No Flutter or Cloud Functions files change — `BookingScreen`'s existing machine picker (`lib/features/patient/booking_screen.dart:338-399`) already streams `machine_status` and needs nothing added.

---

### Task 1: Firebase service-account key + bridge project scaffold

**Files:**
- Create: `bridge/package.json`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: nothing
- Produces: `bridge/service-account.json` (gitignored file, not committed) that Task 2's bridge code loads via `require('./service-account.json')`

- [ ] **Step 1: Download the service-account key**

In Firebase Console → project `heal-a49e3` → Project settings (gear icon) → Service accounts tab → "Generate new private key". Save the downloaded file as `bridge/service-account.json`.

This step is manual (console UI, not scriptable) — **confirm with the user they've done this and the file exists at that path before continuing**, since Task 2 will fail immediately without it.

- [ ] **Step 2: Gitignore the secret before anything else touches the folder**

Add to `.gitignore` at repo root:
```
# HiveMQ bridge secrets — never commit
bridge/node_modules/
bridge/service-account.json
```

- [ ] **Step 3: Scaffold the Node project**

Create `bridge/package.json`:
```json
{
  "name": "machine-status-bridge",
  "version": "1.0.0",
  "private": true,
  "type": "commonjs",
  "main": "index.js",
  "scripts": {
    "start": "node index.js"
  },
  "dependencies": {
    "firebase-admin": "^12.7.0",
    "mqtt": "^5.10.3"
  }
}
```

Run: `cd bridge && npm install`
Expected: `node_modules/` created, no install errors.

- [ ] **Step 4: Verify the secret isn't tracked**

Run: `git status`
Expected: `bridge/service-account.json` does NOT appear (gitignored); `bridge/package.json`, `bridge/package-lock.json` appear as untracked/new, ready to be added later.

---

### Task 2: The bridge — MQTT subscriber that writes Firestore

**Files:**
- Create: `bridge/index.js`

**Interfaces:**
- Consumes: HiveMQ topic `machine/status/+` (wildcard — any machine number), message payload `{"is_active": bool}`
- Produces: `machine_status/{machineId}` Firestore doc with `is_active` (bool) + `last_updated` (server timestamp) + `name` (string) — consumed by `BookingScreen`'s Step 4 machine picker (`lib/features/patient/booking_screen.dart:341-398`, unmodified)

- [ ] **Step 1: Write the bridge**

```js
const mqtt = require('mqtt');
const admin = require('firebase-admin');
const serviceAccount = require('./service-account.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});
const db = admin.firestore();

const MQTT_URL = 'mqtts://66534f45e89543519c61f51c461045ee.s1.eu.hivemq.cloud:8883';
const MQTT_USER = 'healthcare';
const MQTT_PASS = '12345678Heal';
const TOPIC_PATTERN = 'machine/status/+';

// machineId (from the topic's last segment) -> display name shown in
// BookingScreen's Step 4 picker. Add an entry here for each new machine.
const MACHINE_NAMES = {
  '1': 'เครื่องกายภาพบำบัด 1',
};

const client = mqtt.connect(MQTT_URL, {
  username: MQTT_USER,
  password: MQTT_PASS,
  clientId: 'firestore-bridge-' + Math.random().toString(16).slice(2),
});

client.on('connect', () => {
  console.log('[bridge] connected to HiveMQ');
  client.subscribe(TOPIC_PATTERN, (err) => {
    if (err) console.error('[bridge] subscribe failed:', err);
    else console.log('[bridge] subscribed to', TOPIC_PATTERN);
  });
});

client.on('message', async (topic, payloadBuf) => {
  const machineId = topic.split('/').pop(); // "machine/status/1" -> "1"

  let data;
  try {
    data = JSON.parse(payloadBuf.toString());
  } catch (e) {
    console.error('[bridge] bad JSON on', topic, payloadBuf.toString());
    return;
  }
  if (typeof data.is_active !== 'boolean') {
    console.error('[bridge] missing/invalid is_active on', topic, data);
    return;
  }

  const name = MACHINE_NAMES[machineId] || `เครื่อง ${machineId}`;

  try {
    await db.collection('machine_status').doc(machineId).set({
      is_active: data.is_active,
      last_updated: admin.firestore.FieldValue.serverTimestamp(),
      name,
    });
    console.log(`[bridge] machine_status/${machineId} <- is_active=${data.is_active}, name=${name}`);
  } catch (e) {
    console.error('[bridge] firestore write failed:', e);
  }
});

client.on('error', (err) => console.error('[bridge] mqtt error:', err));
client.on('reconnect', () => console.log('[bridge] reconnecting...'));
```

- [ ] **Step 2: Run the bridge and verify it connects**

Run: `cd bridge && npm start`
Expected:
```
[bridge] connected to HiveMQ
[bridge] subscribed to machine/status/+
```
Leave this running — it must stay up for the rest of the tasks.

- [ ] **Step 3: Verify with a manual MQTT publish (before touching the ESP32)**

In a second terminal, using `mosquitto_pub` (or any MQTT client) against the same HiveMQ cluster:
```bash
mosquitto_pub -h 66534f45e89543519c61f51c461045ee.s1.eu.hivemq.cloud -p 8883 \
  -u healthcare -P 12345678Heal --tls-use-os-certs \
  -t machine/status/1 -m '{"is_active":true}'
```
Expected in the bridge's terminal: `[bridge] machine_status/1 <- is_active=true`

- [ ] **Step 4: Verify the Firestore doc directly**

```bash
curl "https://firestore.googleapis.com/v1/projects/heal-a49e3/databases/(default)/documents/machine_status/1?key=AIzaSyDClqqlPEBLR_xN5ifdQdeP5Hub5HiJoU0"
```
Expected: JSON with `fields.is_active.booleanValue: true` and a fresh `fields.last_updated.timestampValue`. (This read works via the public API key + `allow read: if isSignedIn()` rule would normally require auth for a real client — this curl is just for manual verification and will actually 403 since it's unauthenticated; if you want to double check via curl specifically, use the Firebase Console's Firestore data viewer instead, which is simpler for a one-off look.)

---

### Task 3: ESP32 sketch — read the slide switch and publish its state

**Files:**
- Create: `esp32/machine_status_switch/machine_status_switch.ino`

**Interfaces:**
- Consumes: bridge running from Task 2, subscribed to `machine/status/+`
- Produces: continuous `machine_status/1` updates reflecting live switch position — consumed by Task 4's manual verification in `BookingScreen`

- [ ] **Step 1: Write the sketch**

Same connection logic as the user's original HiveMQ test sketch, with `bool isActive = true;` replaced by an actual `digitalRead()` of the slide switch on GPIO23:

```cpp
#include <WiFi.h>
#include <PubSubClient.h>
#include <WiFiClientSecure.h>

const char* ssid     = "Wokwi-GUEST";
const char* password = "";

const char* mqtt_server = "66534f45e89543519c61f51c461045ee.s1.eu.hivemq.cloud";
const int   mqtt_port   = 8883;
const char* mqtt_user   = "healthcare";
const char* mqtt_pass   = "12345678Heal";

const char* topic = "machine/status/1";

// Slide switch: common leg -> 3V3, signal leg -> GPIO23, other leg open.
// INPUT_PULLDOWN so an open/floating leg reads a definite LOW (OFF)
// instead of an undefined floating value.
const int SWITCH_PIN = 23;

WiFiClientSecure espClient;
PubSubClient client(espClient);

void connectMQTT() {
  while (!client.connected()) {
    client.connect("ESP32_machine_1", mqtt_user, mqtt_pass);
    // เครื่องที่ 2 ใช้ "ESP32_machine_2" (client ID ต้องไม่ซ้ำกัน)
    delay(1000);
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(SWITCH_PIN, INPUT_PULLDOWN);

  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) delay(500);
  Serial.println("WiFi connected");

  espClient.setInsecure();
  client.setServer(mqtt_server, mqtt_port);
  connectMQTT();
}

void loop() {
  if (!client.connected()) connectMQTT();
  client.loop();

  // สวิตช์เปิด (ต่อ 3V3) = HIGH = true, สวิตช์ปิด/ลอย = LOW = false
  bool isActive = digitalRead(SWITCH_PIN) == HIGH;
  String payload = String("{\"is_active\":") + (isActive ? "true" : "false") + "}";

  client.publish(topic, payload.c_str());
  Serial.println("ส่งแล้ว: " + payload);
  delay(5000);
}
```

- [ ] **Step 2: Run in Wokwi and confirm the switch actually changes the payload**

Start the simulation. In the Wokwi serial monitor, expected every ~5s:
```
ส่งแล้ว: {"is_active":false}
```
(or `true`, depending on the switch's starting position). Toggle the slide switch in the Wokwi UI mid-simulation — within one publish cycle (≤5s) the serial output must flip to the other value. If it never changes regardless of the switch position, `SWITCH_PIN` doesn't match the actual wiring — re-click the wire in Wokwi to re-confirm the GPIO number.

- [ ] **Step 3: Confirm end-to-end flow in the bridge log**

With the bridge (Task 2) still running, expected in the bridge terminal, repeating every ~5s and flipping when the switch is toggled:
```
[bridge] machine_status/1 <- is_active=false
```

If nothing appears: check the Wokwi serial monitor for `ส่งแล้ว: ...` first (confirms ESP32→HiveMQ succeeded) — if that's fine but the bridge sees nothing, the bridge's topic subscription or HiveMQ credentials are the problem, not the ESP32 sketch.

---

### Task 4: Verify the machine shows up live in `BookingScreen`'s existing picker

**Files:** none — this task only exercises code that already exists (`lib/features/patient/booking_screen.dart:338-399`)

**Interfaces:**
- Consumes: `machine_status/1` doc kept live by the bridge (Task 2) + ESP32 (Task 3)
- Produces: nothing further — terminal verification point

- [ ] **Step 1: Clear any stray test docs first**

If Task 2 Step 3/4's manual `mosquitto_pub`/curl testing left extra docs in `machine_status` (it shouldn't, since that test also targeted `machine/status/1`, but double check), delete anything that isn't the real machine via the Firebase Console's Firestore data viewer — `BookingScreen`'s picker lists every doc in the collection with no filtering, so stray docs show up as fake selectable "machines."

- [ ] **Step 2: Manual UI verification**

Run: `flutter run`, log in as a patient, go to "จองคิวใหม่" (`BookingScreen`), scroll to Step 4 "เลือกเครื่องที่ใช้", with the bridge (Task 2) and Wokwi sketch (Task 3) still running.

Expected:
1. A card labeled "เครื่องกายภาพบำบัด 1" (from the bridge's `MACHINE_NAMES` map) appears in the list
2. Toggle the slide switch to ON in Wokwi: within ≤5s the card's status pill shows "กำลังทำงาน" (green)
3. Toggle the slide switch to OFF: within ≤5s the pill shows "ว่างอยู่" (grey) — confirms the live switch position round-trips all the way to this screen, not just a hardcoded value
4. Stop the Wokwi simulation entirely, wait 30+ seconds: pill flips to "ไม่ทราบสถานะ" (orange) — confirms `BookingScreen`'s own 30s staleness check (`booking_screen.dart:353`) works through the extra hop
5. Stop the bridge process too (`Ctrl+C`), restart the Wokwi sketch: pill should NOT recover (bridge is down, nothing writes to Firestore) — confirms the bridge is actually load-bearing and not just incidentally working
6. Tap the card to select it, then confirm a booking through to the end — the resulting appointment's `machineName` should read "เครื่องกายภาพบำบัด 1" (sanity check that the `name` field flows all the way into a real booking, not just the picker UI)

- [ ] **Step 3: Commit**

```bash
git add bridge/package.json bridge/package-lock.json bridge/index.js .gitignore esp32/machine_status_switch/machine_status_switch.ino
git commit -m "feat: ESP32 switch -> HiveMQ -> Firestore bridge for machine_status"
```

(`bridge/service-account.json` is gitignored and must NOT appear in this commit — double-check `git status` before running it.)

---

## Follow-ups Explicitly Out of Scope for This Plan

- **Bridge is a local/manually-run process for this test pass.** For anything beyond testing, it needs to run somewhere always-on (e.g. Cloud Run with `min-instances: 1`, or a small VM) — not covered here since the user asked to "start testing" first.
- **`firestore.rules`'s `machine_status` rule still allows open unauthenticated writes** (`c35fc8a`), left over from when ESP32 wrote directly. Once this bridge is the only writer, that open rule is no longer needed and could be tightened to admin-only writes (Admin SDK bypasses rules regardless, so tightening it only blocks *other* unauthenticated clients, not the bridge). Left alone here to avoid touching rules in the same pass as new infrastructure.
- **HiveMQ credentials are hardcoded in `bridge/index.js`** (matching how they're hardcoded in the ESP32 sketch already) — fine for a test pass; move to environment variables before this bridge runs anywhere persistent/shared.

## Self-Review Notes

- **Spec coverage:** ESP32 slide-switch read + HiveMQ publish (Task 3), bridge subscribe+write (Task 2), end-to-end run including switch-toggle verification (Task 3 Step 2, Task 4 Step 3), Flutter display (Task 4), explicit confirmation this sidesteps App Check (Architecture section).
- **No placeholders:** bridge, sketch, and Dart code are complete and copy-pasteable using the user's actual HiveMQ credentials/topic and the confirmed `GPIO23` switch pin.
- **Type/name consistency:** `machineId: '1'` (Task 4) matches the bridge's topic-derived doc ID (Task 2) and the ESP32's topic `machine/status/1` (Task 3) throughout — deliberately NOT `'current'`, unlike the now-superseded REST-direct plan (`docs/superpowers/plans/2026-08-11-esp32-firestore-status-display.md`). `SWITCH_PIN = 23` (Task 3) matches the user-confirmed wiring in Global Constraints.
