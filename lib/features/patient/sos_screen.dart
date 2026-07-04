import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:healthcare_app/core/theme.dart';
import 'package:healthcare_app/services/sos_service.dart';
import 'package:healthcare_app/services/user_service.dart';

// ==========================================
// 11. SOS Screen
// ==========================================
class SOSScreen extends StatefulWidget {
  const SOSScreen({super.key});
  @override
  State<SOSScreen> createState() => _SOSScreenState();
}

class _SOSScreenState extends State<SOSScreen> {
  String selectedIssue = 'ผู้ป่วยหมดสติ';
  final otherCtrl = TextEditingController();
  final issues = ['ผู้ป่วยหมดสติ', 'หกล้มบาดเจ็บรุนแรง', 'หายใจไม่ออก / แน่นหน้าอก', 'อื่นๆ'];
  bool isSending = false;

  Future<void> sendSOS() async {
    String message = selectedIssue == 'อื่นๆ' ? otherCtrl.text : selectedIssue;
    if (message.isEmpty) return;
    setState(() => isSending = true);
    User? user = FirebaseAuth.instance.currentUser;
    try {
      var userDoc = await users.getUser(user!.uid);
      String patientName = userDoc.data()?['fullname'] ?? 'ผู้ป่วยไม่ทราบชื่อ';
      await sos.sendAlert(patientUid: user.uid, patientName: patientName, issue: message);
      if (mounted) {
        showDialog(
          context: context, barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.check_circle, color: Colors.green, size: 50),
            title: const Text('ส่งสัญญาณ SOS สำเร็จ'),
            content: Text('เจ้าหน้าที่ได้รับแจ้งเหตุ:\n\'$message\'\nและกำลังตรวจสอบ กรุณารอสักครู่', textAlign: TextAlign.center),
            actions: [SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: primaryGreen, foregroundColor: Colors.white), onPressed: () { Navigator.pop(ctx); Navigator.pop(context); }, child: const Text('ตกลง')))],
          ),
        );
      }
    } catch (e) {
      debugPrint('SOS send error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('เกิดข้อผิดพลาด กรุณาลองใหม่')));
    } finally {
      if (mounted) setState(() => isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('แจ้งเหตุฉุกเฉิน', style: TextStyle(color: Colors.red)), iconTheme: const IconThemeData(color: Colors.red)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle), child: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 80))),
          const SizedBox(height: 30),
          const Text('ระบุอาการหรือเหตุฉุกเฉิน:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          RadioGroup<String>(
            groupValue: selectedIssue,
            onChanged: (v) { if (v != null) setState(() => selectedIssue = v); },
            child: Column(children: issues.map((issue) => RadioListTile<String>(value: issue, title: Text(issue, style: const TextStyle(fontWeight: FontWeight.w500)), contentPadding: EdgeInsets.zero)).toList()),
          ),
          if (selectedIssue == 'อื่นๆ') ...[
            const SizedBox(height: 10),
            TextField(controller: otherCtrl, maxLines: 3, decoration: InputDecoration(hintText: 'โปรดระบุรายละเอียด...', filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)))),
          ],
          const SizedBox(height: 40),
          SizedBox(width: double.infinity, height: 60, child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
            icon: const Icon(Icons.sos, size: 30),
            label: isSending ? const CircularProgressIndicator(color: Colors.white) : const Text('ส่งสัญญาณขอความช่วยเหลือ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            onPressed: isSending ? null : sendSOS,
          )),
        ]),
      ),
    );
  }
}
