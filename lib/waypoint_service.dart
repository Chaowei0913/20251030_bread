import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';

/// Waypoint 資料模型
class Waypoint {
  final String id;
  final double latitude;
  final double longitude;
  final String message;
  final String photoUrl;
  final DateTime timestamp;
  final String userId;

  Waypoint({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.message,
    required this.photoUrl,
    required this.timestamp,
    required this.userId,
  });

  /// Firestore 轉換成 Dart 物件
  factory Waypoint.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Waypoint(
      id: doc.id,
      latitude: (data['latitude'] as num).toDouble(),
      longitude: (data['longitude'] as num).toDouble(),
      message: data['message'] ?? '',
      photoUrl: data['photoUrl'] ?? '',
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      userId: data['userId'] ?? '',
    );
  }

  /// Dart 物件轉換成 Firestore 格式
  Map<String, dynamic> toMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'message': message,
      'photoUrl': photoUrl,
      'timestamp': timestamp,
      'userId': userId,
    };
  }
}

/// Waypoint Service
class WaypointService {
  final CollectionReference waypointsRef =
  FirebaseFirestore.instance.collection('waypoints');

  /// 新增標記點
  Future<void> addWaypoint({
    required double latitude,
    required double longitude,
    required String message,
    required String userId,
  }) async {
    await waypointsRef.add({
      'latitude': latitude,
      'longitude': longitude,
      'message': message,
      'photoUrl': '', // 先留空，之後再加照片
      'timestamp': FieldValue.serverTimestamp(),
      'userId': userId,
    });
  }

  /// 讀取所有標記點
  Future<List<Waypoint>> getWaypoints() async {
    final snapshot = await waypointsRef.orderBy('timestamp', descending: true).get();
    return snapshot.docs.map((doc) => Waypoint.fromDoc(doc)).toList();
  }

  /// 更新標記點
  Future<void> updateWaypoint(String waypointId, Map<String, dynamic> data) async {
    await waypointsRef.doc(waypointId).update(data);
  }

  /// 刪除標記點
  Future<void> deleteWaypoint(String waypointId) async {
    await waypointsRef.doc(waypointId).delete();
  }
}