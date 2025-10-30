import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'location_service.dart';
import 'firestore_service.dart';
import 'route_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // 1️⃣ 狀態變數
  LatLng? currentPosition;
  LatLng? destination;
  final MapController mapController = MapController();
  final List<LatLng> pathPoints = [];

  // 2️⃣ 取得位置並上傳
  void _getLocationAndUpload() async {
    try {
      LatLng? position = await LocationService.getCurrentLocation();
      if (position == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('無法取得位置')),
        );
        return;
      }

      setState(() {
        currentPosition = position;
        pathPoints.add(position);
      });

      await FirestoreService.uploadLocation(position);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('位置已上傳 Firebase!')),
      );

      mapController.move(position, 16);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('上傳失敗: $e')),
      );
    }
  }

  // 3️⃣ 回到最新位置
  void _goToCurrentPosition() {
    if (currentPosition != null) {
      mapController.move(currentPosition!, 16);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('目前沒有位置可回到')),
      );
    }
  }

  // 4️⃣
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

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已設定目的地並顯示路線')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('無法取得路線: $e')),
      );
    }
  }

  // 5️⃣ 清除目前路線與目的地
  void _clearRoute() {
    setState(() {
      destination = null;
      pathPoints.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('🗑️ 已清除目前路線')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Breadcrumbs Tracker')),
      body: FlutterMap(
        mapController: mapController,
        options: MapOptions(
          initialCenter: currentPosition ?? LatLng(23.0169, 120.2324),
          initialZoom: 16,
          interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
          onTap: (tapPosition, point) {
            _setDestination(point);
          },
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.breadcrumbs',
          ),
          if (pathPoints.isNotEmpty)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: pathPoints,
                  color: Colors.blue,
                  strokeWidth: 4,
                ),
              ],
            ),
          if (currentPosition != null)
            MarkerLayer(
              markers: [
                Marker(
                  point: currentPosition!,
                  width: 40,
                  height: 40,
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.red,
                    size: 40,
                  ),
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
                  child: const Icon(
                    Icons.flag,
                    color: Colors.green,
                    size: 40,
                  ),
                ),
              ],
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
