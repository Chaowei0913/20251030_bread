import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class LocationService {
  /// 取得當前位置，回傳 LatLng，如果失敗回傳 null
  static Future<LatLng?> getCurrentLocation({bool simulate = false}) async {
    if (simulate) {
      // 模擬位置
      return LatLng(23.0169109, 120.2324343);
    }

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return null;
        }
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      print('⚠️ LocationService 取得位置失敗: $e');
      return null;
    }
  }
}
