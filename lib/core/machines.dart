import 'package:healthcare_app/core/format.dart';

/// รายชื่อเครื่องกายภาพบำบัดที่ระบบรู้จัก — ตายตัว ไม่ได้ดึงจาก Firestore
/// เพราะต้องแสดงเครื่องที่ "ยังไม่เคยส่งข้อมูลเลย" ด้วย (สถานะ "ไม่ทราบข้อมูล")
/// เพิ่ม/ลดเครื่องจริงให้แก้ที่นี่ที่เดียว — id ต้องตรงกับ doc ID ที่ ESP32
/// เขียนลง machine_status/{id}
const List<({String id, String name})> knownMachines = [
  (id: 'machine_1', name: 'เครื่อง 1'),
  (id: 'machine_2', name: 'เครื่อง 2'),
];

enum MachineState { unknown, online, inUse }

/// ตัดสินสถานะเครื่องจาก heartbeat ล่าสุด — ไม่ทราบข้อมูล (ไม่เคยส่ง/สัญญาณขาด
/// เกิน 30 วิ) / ออนไลน์ (เชื่อมต่ออยู่ แต่ไม่ได้รักษาใคร) / กำลังใช้งาน
/// (เชื่อมต่ออยู่ + กำลังรักษา)
MachineState machineStateFor({required bool? isActive, required DateTime? lastUpdated, DateTime? now}) {
  if (lastUpdated == null) return MachineState.unknown;
  if (isMachineStale(lastUpdated: lastUpdated, recordExists: true, now: now)) return MachineState.unknown;
  return (isActive ?? false) ? MachineState.inUse : MachineState.online;
}
