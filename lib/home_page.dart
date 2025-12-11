import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:latlong2/latlong.dart' show Distance, LengthUnit;
import 'location_service.dart';
import 'firestore_service.dart';
import 'route_service.dart';
import 'friends_page.dart';


class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // === 核心狀態 ===
  LatLng? currentPosition;
  LatLng? destination;
  final MapController mapController = MapController();
  final List<LatLng> pathPoints = [];

  // === 錄製狀態與 Stream 管理 (取代 Timer) ===
  bool isRecording = false;
  LatLng? lastRecordedPosition;
  double minDistance = 5.0; // GPS 最小移動距離（公尺）
  StreamSubscription<LatLng>? _locationSubscription;

  // === 登入相關 ===
  User? user = FirebaseAuth.instance.currentUser;

  // 初始化時檢查登入狀態
  @override
  void initState() {
    super.initState();
    FirebaseAuth.instance.authStateChanges().listen((User? newUser) {
      setState(() {
        user = newUser;
      });
    });
  }

  // === 資源清理：App 關閉時停止追蹤 ===
  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  // === 登入/登出邏輯 (不變) ===
  Future<void> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return;

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ 登入成功')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ 登入失敗：$e')),
      );
    }
  }

  Future<void> signOut() async {
    _stopRecording();
    await GoogleSignIn().signOut();
    await FirebaseAuth.instance.signOut();
  }

  // === 錄製控制：切換開始/結束 ===
  void _toggleRecording() {
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🛑 請先登入才能開始記錄路線')),
      );
      return;
    }

    if (isRecording) {
      _stopRecording();
    } else {
      _startRecording();
    }
  }

  void _startRecording() {
    setState(() {
      isRecording = true;
      pathPoints.clear();
      lastRecordedPosition = null;
    });

    _locationSubscription = LocationService.getPositionStream().listen(
          (position) {
        _processNewLocation(position);
      },
      onError: (e) {
        _stopRecording();
        debugPrint('❌ GPS 追蹤 Stream 錯誤: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('GPS 追蹤發生錯誤，已停止記錄: $e')),
        );
      },
      onDone: () {
        debugPrint('GPS Stream 完成 (通常不會發生)');
      },
      cancelOnError: false,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ 路線記錄開始，持續追蹤中...')),
    );
  }

  void _stopRecording() {
    _locationSubscription?.cancel();
    _locationSubscription = null;

    setState(() {
      isRecording = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('🛑 路線記錄停止，路徑已儲存。')),
    );
  }

  // === 處理新的位置點、濾波並上傳 (核心邏輯) ===
  void _processNewLocation(LatLng position) async {
    bool shouldRecord = false;

    // 1. 濾波器邏輯：檢查距離是否大於 minDistance (10m)
    if (lastRecordedPosition == null) {
      shouldRecord = true;
    } else {
      final distance = Distance().as(LengthUnit.Meter, lastRecordedPosition!, position);

      if (distance >= minDistance) {
        shouldRecord = true;
      } else {
        debugPrint('Debug: 距離太近 (${distance.toStringAsFixed(2)}m)，忽略此點 (GPS 雜訊)');
      }
    }

    // 2. 執行記錄和上傳
    if (shouldRecord) {
      try {
        setState(() {
          currentPosition = position;
          pathPoints.add(position);
        });
        lastRecordedPosition = position;

        await FirestoreService.uploadLocation(position);
        debugPrint('☁️ Firestore 上傳成功: $position');

      } catch (e) {
        debugPrint('❌ Firestore 上傳失敗: $e');
      }
    } else {
      setState(() {
        currentPosition = position;
      });
    }

    mapController.move(currentPosition!, mapController.camera.zoom);
  }

  // === 地圖操作方法 (不變) ===
  void _goToCurrentPosition() {
    if (currentPosition != null) {
      mapController.move(currentPosition!, 16);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('目前沒有位置可回到')),
      );
    }
  }

  void _clearRoute() {
    setState(() {
      destination = null;
      pathPoints.clear();
      lastRecordedPosition = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('路線已清除')),
    );
  }

  void _setDestination(LatLng point) async {
    setState(() {
      destination = point;
    });

    if (currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先取得目前位置')),
      );
      return;
    }

    _stopRecording();

    try {
      final routePoints = await RouteService.getRoute(currentPosition!, destination!);
      setState(() {
        pathPoints
          ..clear()
          ..addAll(routePoints);
      });
      mapController.move(destination!, 15);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('無法取得路線: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Breadcrumbs Tracker')),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // ... Drawer UI 保持不變
            UserAccountsDrawerHeader(
              accountName: Text(user?.displayName ?? '尚未登入'),
              accountEmail: Text(user?.email ?? ''),
              currentAccountPicture: CircleAvatar(
                backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
                child: user?.photoURL == null ? const Icon(Icons.person, size: 40) : null,
              ),
              decoration: const BoxDecoration(color: Colors.deepPurple),
            ),
            if (user == null)
              ListTile(
                leading: const Icon(Icons.login),
                title: const Text('使用 Google 登入'),
                onTap: () async {
                  Navigator.pop(context);
                  await signInWithGoogle();
                },
              )
            else
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('登出'),
                onTap: () async {
                  Navigator.pop(context);
                  await signOut();
                },
              ),
            ListTile(
              leading: const Icon(Icons.people),
              title: const Text("朋友列表"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => FriendsPage()),
                );
              },
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          // 1. 地圖層 (保持不變)
          FlutterMap(
            mapController: mapController,
            options: MapOptions(
              initialCenter: currentPosition ?? LatLng(23.0169, 120.2324),
              initialZoom: 16,
              onTap: (tapPosition, point) => _setDestination(point),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.breadcrumbs',
              ),
              if (pathPoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(points: pathPoints, color: isRecording ? Colors.orange : Colors.blue, strokeWidth: 4),
                  ],
                ),
              if (currentPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: currentPosition!,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                    ),
                  ],
                ),
              if (destination != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: destination!,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.flag, color: Colors.green, size: 40),
                    ),
                  ],
                ),
            ],
          ),

          // 2. 獨立的「開始/停止記錄」按鈕 (定位到左下角)
          // ⚠️ 注意：這個 Positioned Widget 必須在 Stack 的 children 列表內！
          Positioned(
            bottom: 70, // 距離底部 20
            left: 20,    // 距離左側 20
            child: FloatingActionButton.extended(
              heroTag: "btn_record",
              onPressed: _toggleRecording,
              label: Text(isRecording ? '停止記錄 (ON)' : '開始記錄 (OFF)',
                  style: const TextStyle(fontWeight: FontWeight.bold)
              ),
              icon: Icon(isRecording ? Icons.stop : Icons.play_arrow),
              backgroundColor: isRecording ? Colors.red : Colors.green, // 顏色切換
              foregroundColor: Colors.white,
            ),
          ),
        ], // Stack 的 children 結束
      ), // body 結束

      // 3. 右下角的操作按鈕 (回到位置、清除路線)
      // 保持在 Scaffold 的 floatingActionButton 屬性中，位於右下角
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end, // 確保右對齊
        children: [
          // 回到最新位置
          FloatingActionButton(
            heroTag: "btn_goto",
            onPressed: _goToCurrentPosition,
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            child: const Icon(Icons.location_searching),
          ),
          const SizedBox(height: 10),

          // 清除路線
          FloatingActionButton(
            heroTag: "btn_clear",
            onPressed: _clearRoute,
            backgroundColor: Colors.white,
            foregroundColor: Colors.red,
            child: const Icon(Icons.delete),
          ),
          const SizedBox(height: 40), // 增加底部間距
        ],
      ),
    );
  }
}