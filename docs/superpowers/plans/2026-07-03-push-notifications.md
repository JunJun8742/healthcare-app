# Push Notifications — Implementation Plan

Spec: `docs/superpowers/specs/2026-07-03-push-notifications-design.md`
Branch: `push-notifications`. Orchestrator commits after reviewing each task; workers never commit.

## Task graph

```
T1 functions/ (worker, parallel) ──────────────┐
T2 FCM client main.dart+android (worker) ──┐   │
T3 history screen + badge (worker, after T2)│  ├─ T6 final review + verify ─ T7 merge/push ─ deploy gates
T4 cancelledBy writes (worker, after T3) ───┘  │
T5 firestore.rules (orchestrator) ─────────────┘  [DONE — committed with this plan]
```

T1 ∥ T2 (disjoint files). T2 → T3 → T4 strictly sequential (all edit lib/main.dart).

## T1 — functions/ codebase

Files: `functions/package.json` (engines node 22, firebase-admin ^13, firebase-functions ^6, typescript dev), `functions/tsconfig.json`, `functions/.gitignore` (node_modules/, lib/), `functions/src/index.ts`, plus a `functions` block in `firebase.json` (preserve existing keys; predeploy `npm --prefix "$RESOURCE_DIR" run build`).

index.ts contract (see spec for guards, copy, payload, date fn — all frozen):
- `REGION` constant `asia-southeast1` with verify-at-deploy comment.
- Helpers: `bangkokThaiDateString()`; `createHistory(docId, fields)` → `.create()` with `read:false, createdAt: serverTimestamp, expiresAt: now+30d`, returns false on ALREADY_EXISTS; `sendToTokens(uidForPruning, tokens, {title, body, type, refId, channelId})` → ≤500-token chunks via `sendEachForMulticast`, prunes dead tokens with `arrayRemove`.
- Pattern per recipient: `if (await createHistory(...)) await sendToTokens(...)`.
- Five functions per spec table. Cancelled routing: cancelledBy 'patient'→[staffUid], 'staff'→[patientUid], else both (filter empty, dedupe). SOS uses channel `sos_channel`; everything else `healthcare_default`. Reminder history docId `${patientUid}_${todayKey}_reminder` (`/`→`-`); event functions `${event.id}_${uid}`.
- Top-level try/catch per handler; log, never rethrow.
- Accept: `cd functions && npm install && npm run build` exits 0. Touch nothing outside functions/ + firebase.json.

## T2 — Flutter FCM client

- `flutter pub add firebase_messaging flutter_local_notifications` (fallback: pin current majors manually + `flutter pub get`).
- Manifest: `POST_NOTIFICATIONS` uses-permission.
- `android/app/build.gradle.kts`: `isCoreLibraryDesugaringEnabled = true` + `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")`.
- main.dart: global navigator key on MaterialApp; two channels created in main(); global `currentUserRole` + `_pendingNotifType`; `_registerFcm(uid)` from AuthGate post-frame once per session (permission → getToken try/catch → arrayUnion; onTokenRefresh once); `onMessage` → local heads-up (payload {type}); `onMessageOpenedApp` + local-notif tap → `_routeFromNotification`; `getInitialMessage` → pending type consumed when AuthGate builds nav root; `StaffNavigation.initialIndex` (mirror MainNavigation); every `signOut()` site: best-effort arrayRemove(token) + deleteToken() in try/catch.
- Accept: `dart analyze lib/main.dart` = exactly 5 pre-existing infos.

## T3 — History screen + badge

- Rebuild `NotificationScreen` (placeholder at ~lib/main.dart:2458): StreamBuilder where uid==me, client-side sort createdAt desc, StateMessage empty/loading states, card per design tokens (type icon via _icon3D-style, bold title when unread, relative Thai time), tap → update {read:true}.
- Patient home แจ้งเตือน card + staff StaffQueueScreen AppBar bell: red dot via StreamBuilder on read==false count.
- Accept: dart analyze baseline; Thai strings; matches design tokens (kRadius, kGap*, tTitle/tBody/tCaption, statusInfo palette conventions).

## T4 — cancelledBy writes

- lib/main.dart:1304 and :2157: add `'cancelledBy': 'patient'` to the update map.
- Staff cancel call site of `_changeStatus` (toStatus 'ยกเลิก'): pass `extra: {'cancelledBy': 'staff'}`; confirm undo machinery (prevValues/FieldValue.delete) reverts it cleanly.
- Accept: dart analyze baseline; patient cancel payload ⊆ {status, cancelledAt, cancelledBy} (matches tightened rule).

## T5 — firestore.rules  [DONE by orchestrator]

notifications block (owner read; read false→true flip only; no client create/delete) + tightened patient-cancel rule (from-กำลังรอ, affectedKeys subset). Committed with this plan.

## T6 — Final review + verification

Whole-branch diff review by orchestrator (Codex fresh-eyes pass if available): cross-checks = payload type strings identical across functions/app/spec; Thai status strings byte-identical; channel ids match; guard against double-send on undo paths; dart analyze + npm build both clean.

## T7 — Merge & push, then deploy gates

Merge `push-notifications` → `main`, push. Then the spec's deploy-time checklist (Blaze, login, region verify, deploy functions+rules, TTL enable, real-device walk).
