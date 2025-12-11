import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

class FriendsMapPage extends StatefulWidget {
  final String friendUid;
  final String friendName;

  const FriendsMapPage({super.key, required this.friendUid, required this.friendName});

  @override
  State<FriendsMapPage> createState() => _FriendsMapPageState();
}

class _FriendsMapPageState extends State<FriendsMapPage> {
  final MapController mapController = MapController();
  List<LatLng> friendRoute = [];
  LatLng? friendCurrentPosition;

  @override
  void initState() {
    super.initState();
    _listenFriendLocations();
  }

  void _listenFriendLocations() {
    FirebaseFirestore.instance
        .collection('bread')
        .where('uid', isEqualTo: widget.friendUid)
        .orderBy('timestamp')
        .snapshots()
        .listen((snapshot) {
      final points = <LatLng>[];

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        if (data["latitude"] != null) {
          points.add(LatLng(data['latitude'], data['longitude']));
        }
      }

      setState(() {
        friendRoute = points;
        if (points.isNotEmpty) {
          friendCurrentPosition = points.last;
        }
      });

      if (friendCurrentPosition != null) {
        mapController.move(friendCurrentPosition!, 16);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("${widget.friendName} 的位置")),
      body: FlutterMap(
        mapController: mapController,
        options: MapOptions(
          initialCenter: LatLng(23.0, 120.0),
          initialZoom: 14,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.bread',
          ),
          if (friendRoute.isNotEmpty)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: friendRoute,
                  color: Colors.purple,
                  strokeWidth: 4,
                )
              ],
            ),
          if (friendCurrentPosition != null)
            MarkerLayer(
              markers: [
                Marker(
                  point: friendCurrentPosition!,
                  width: 40,
                  height: 40,
                  child: const Text("🧑‍🤝‍🧑", style: TextStyle(fontSize: 35)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
