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
import 'friends_list_page.dart';
import 'waypoint_service.dart';


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
  StreamSubscription<LatLng>? _singleLocationSubscription;

  // === 登入相關 ===
  User? user = FirebaseAuth.instance.currentUser;

  bool isSharingLocation = false; // 代表是否分享位置
  Timer? _shareLocationTimer;      // 用來定時上傳位置

  //標點部分
  final waypointService = WaypointService();
  final List<Marker> waypointMarkers = [];

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
    _shareLocationTimer?.cancel();
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

  void _getCurrentLocationOnce() {
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🛑 請先登入才能取得位置')),
      );
      return;
    }

    // 如果正在錄製，直接提示
    if (isRecording) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ 記錄中，請先停止記錄')),
      );
      return;
    }

    // 取消之前的單次定位（避免重複）
    _singleLocationSubscription?.cancel();

    _singleLocationSubscription =
        LocationService.getPositionStream().listen((position) {
          setState(() {
            currentPosition = position;
          });

          // 地圖移動到目前位置
          mapController.move(position, 16);

          // ✅ 只取一次就停止
          _singleLocationSubscription?.cancel();
          _singleLocationSubscription = null;
        }, onError: (e) {
          debugPrint('❌ 取得位置失敗: $e');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('取得位置失敗: $e')),
          );
        });
      }
  void _startSharingLocation() {
    if (user == null) return;

    _shareLocationTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      final position = await LocationService.getCurrentLocation();
      if (position != null) {
        await FirestoreService.uploadLocation(position);
        debugPrint('☁️ 分享位置上傳: $position');
      }
    });
  }

  void _stopSharingLocation() {
    // 停掉定時上傳
    _shareLocationTimer?.cancel();
    _shareLocationTimer = null;

    // 暫時不清除 Firestore 上的座標，保留原位置
    debugPrint('分享位置已停止，但 Firestore 上的座標保留');
  }

  void _addWaypoint(LatLng position) async {
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🛑 請先登入才能新增標記點')),
      );
      return;
    }

    await waypointService.addWaypoint(
      latitude: position.latitude,
      longitude: position.longitude,
      message: "這裡有好玩的！",
      userId: user!.uid,
    );

    setState(() {
      waypointMarkers.add(
        Marker(
          point: position,
          width: 40,
          height: 40,
          child: GestureDetector(
            onTap: () => _deleteWaypoint(position), // 點擊刪除
            child: const Icon(Icons.star, color: Colors.yellowAccent, size: 35),
          ),
        ),
      );
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ 已新增標記點')),
    );
  }

  void _deleteWaypoint(LatLng position) async {
    try {
      // 從 Firestore 讀取所有 Waypoints
      final waypoints = await waypointService.getWaypoints();

      // 找到符合座標的 waypoint
      final target = waypoints.firstWhere(
            (wp) => wp.latitude == position.latitude && wp.longitude == position.longitude,
        orElse: () => throw Exception("找不到標記點"),
      );

      // 刪除 Firestore 資料
      await waypointService.deleteWaypoint(target.id);

      // 從地圖上移除
      setState(() {
        waypointMarkers.removeWhere((marker) => marker.point == position);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🗑️ 標記點已刪除')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('刪除失敗: $e')),
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
              title: const Text("好友申請"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => FriendsPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.list),
              title: const Text("好友列表"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const FriendsListPage(),
                  ),
                );
              },
            ),
            SwitchListTile(
              title: const Text("分享我的位置"),
              value: isSharingLocation,
              onChanged: (value) {
                setState(() {
                  isSharingLocation = value;
                });

                if (isSharingLocation) {
                  _startSharingLocation();
                } else {
                  _stopSharingLocation();
                }
              },
            )
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
              onLongPress: (tapPosition, point) => _addWaypoint(point),
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
              if (waypointMarkers.isNotEmpty)
                MarkerLayer(markers: waypointMarkers),
            ],
          ),

          // 2. 獨立的「開始/停止記錄」按鈕 (定位到左下角)
          // ⚠️ 注意：這個 Positioned Widget 必須在 Stack 的 children 列表內！
          Positioned(
            bottom: 150, // 與底部距離
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
          const SizedBox(height: 10), // 增加底部間距

          // 取得目前位置（不記錄）
          FloatingActionButton(
            heroTag: "btn_get_location",
            onPressed: _getCurrentLocationOnce,
            backgroundColor: Colors.white,
            foregroundColor: Colors.redAccent,
            child: const Icon(Icons.navigation),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}