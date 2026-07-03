import 'package:cloud_firestore/cloud_firestore.dart';

String thaiBuddhistDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year + 543}';

String queueSlotDateKey(String thaiDate) => thaiDate.replaceAll('/', '-');

String relativeTimeTh(Timestamp? ts) {
  if (ts == null) return '';
  final diff = DateTime.now().difference(ts.toDate());
  if (diff.inMinutes < 1) return 'เมื่อสักครู่';
  if (diff.inMinutes < 60) return '${diff.inMinutes} นาทีที่แล้ว';
  if (diff.inHours < 24) return '${diff.inHours} ชั่วโมงที่แล้ว';
  final d = ts.toDate();
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${(d.year % 100).toString().padLeft(2, '0')}';
}

bool isMachineStale({required DateTime? lastUpdated, required bool recordExists, DateTime? now, Duration timeout = const Duration(seconds: 30)}) {
  if (lastUpdated != null) {
    final age = (now ?? DateTime.now()).difference(lastUpdated);
    return age >= timeout;
  }
  return recordExists;
}

int compareCreatedAtDesc(Timestamp? a, Timestamp? b) {
  if (b == null) return -1;
  if (a == null) return 1;
  return b.compareTo(a);
}
