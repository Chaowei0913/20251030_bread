import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

class FirestoreService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// 上傳位置到 Firestore
  static Future<void> uploadLocation(LatLng position) async {
    try {
      await _db.collection('locations').add({
        'latitude': position.latitude,
        'longitude': position.longitude,
        'timestamp': FieldValue.serverTimestamp(),
      });
      print('☁️ Firestore 上傳成功: $position');
    } catch (e) {
      print('❌ Firestore 上傳失敗: $e');
      rethrow;
    }
  }
}
