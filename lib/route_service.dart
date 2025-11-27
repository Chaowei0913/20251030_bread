import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RouteService {
  /// 使用 OSRM 查詢從起點到終點的真實道路路線
  static Future<List<LatLng>> getRoute(LatLng start, LatLng end) async {
    final url =
        'https://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      // routes[0].geometry.coordinates 是 List<List<double>>
      final route = data['routes'][0]['geometry']['coordinates'] as List;

      // 轉換成 LatLng 座標格式 (OSRM 回傳的是 [lon, lat])
      return route.map((coord) {
        final lon = coord[0] as double;
        final lat = coord[1] as double;
        return LatLng(lat, lon);
      }).toList();
    } else {
      throw Exception('OSRM 請求失敗: ${response.statusCode}');
    }
  }
}