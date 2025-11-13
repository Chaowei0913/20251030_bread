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

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // === Map 狀態 ===
  LatLng? currentPosition;
  LatLng? destination;
  final MapController mapController = MapController();
  final List<LatLng> pathPoints = [];

  // === 錄製狀態 ===
  bool isRecording = false;
  LatLng? lastRecordedPosition;
  double minDistance = 5.0; // GPS 最小移動距離（公尺）
  Timer? _timer;

  // === 登入相關 ===
  User? user = FirebaseAuth.instance.currentUser;

  // === Google 登入 ===
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
      setState(() {
        user = FirebaseAuth.instance.currentUser;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('登入成功')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('登入失敗：$e')),
      );
    }
  }

  Future<void> signOut() async {
    await GoogleSignIn().signOut();
    await FirebaseAuth.instance.signOut();
    setState(() {
      user = null;
    });
  }

  // === 錄製控制 ===
  void _startRecording() {
    if (isRecording) return;

    setState(() {
      isRecording = true;
      pathPoints.clear();
      lastRecordedPosition = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('開始錄製路徑')),
    );

    // 每 5 秒抓一次位置並上傳
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _getLocationAndUpload());
  }

  void _stopRecording() {
    if (!isRecording) return;

    _timer?.cancel();
    setState(() {
      isRecording = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('結束錄製路徑')),
    );
  }

  // === 取得位置並上傳 ===
  void _getLocationAndUpload() async {
    if (!isRecording) return;

    try {
      LatLng? position = await LocationService.getCurrentLocation();
      if (position == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('無法取得位置')),
        );
        return;
      }

      // 🔹 濾掉 GPS 抖動
      if (lastRecordedPosition != null) {
        final distance = Distance().as(LengthUnit.Meter, lastRecordedPosition!, position);
        if (distance < minDistance) return;
      }
      lastRecordedPosition = position;

      setState(() {
        currentPosition = position;
        pathPoints.add(position);
      });

      await FirestoreService.uploadLocation(position);
      mapController.move(position, 16);

      debugPrint('☁️ Firestore 上傳成功: $position');
    } catch (e) {
      debugPrint('❌ Firestore 上傳失敗: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('上傳失敗: $e')),
      );
    }
  }

  void _goToCurrentPosition() {
    if (currentPosition != null) {
      mapController.move(currentPosition!, 16);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('目前沒有位置可回到')),
      );
    }
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

  void _clearRoute() {
    setState(() {
      destination = null;
      pathPoints.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Breadcrumbs Tracker')),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
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
          ],
        ),
      ),
      body: Stack(
        children: [
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
                    Polyline(points: pathPoints, color: Colors.blue, strokeWidth: 4),
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
          // 左下角開始/結束按鈕
          Positioned(
            bottom: 20,
            left: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    minimumSize: const Size(120, 50),
                  ),
                  onPressed: _startRecording,
                  child: const Text('開始', style: TextStyle(fontSize: 18)),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    minimumSize: const Size(120, 50),
                  ),
                  onPressed: _stopRecording,
                  child: const Text('結束', style: TextStyle(fontSize: 18)),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "btn1",
            onPressed: _getLocationAndUpload,
            child: const Icon(Icons.my_location),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: "btn2",
            onPressed: _goToCurrentPosition,
            child: const Icon(Icons.location_searching),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: "btn3",
            onPressed: _clearRoute,
            child: const Icon(Icons.delete),
          ),
        ],
      ),
    );
  }
}
