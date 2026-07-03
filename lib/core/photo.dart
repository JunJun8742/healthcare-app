import 'dart:convert';
import 'dart:typed_data';

String encodePhotoBase64(List<int> bytes) => base64Encode(bytes);

Uint8List? tryDecodePhotoBase64(String? value) {
  if (value == null || value.isEmpty) return null;
  try {
    return base64Decode(value);
  } catch (_) {
    return null;
  }
}
