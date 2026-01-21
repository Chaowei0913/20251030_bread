import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:geolocator/geolocator.dart';

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();

    service.setForegroundNotificationInfo(
      title: "Breadcrumbs",
      content: "背景定位中...",
    );
  }

  Timer.periodic(const Duration(seconds: 10), (timer) async {
    if (service is AndroidServiceInstance) {
      final isForeground = await service.isForegroundService();
      if (!isForeground) {
        timer.cancel();
        return;
      }
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // ✅ 等級一：只做定位，不碰 Firebase
      print(
        "📍 Background: ${position.latitude}, ${position.longitude}",
      );
    } catch (e) {
      print("❌ 背景定位錯誤：$e");
    }
  });
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'breadcrumbs_channel',
      initialNotificationTitle: 'Breadcrumbs',
      initialNotificationContent: '準備背景定位...',
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: (_) async => true,
    ),
  );
}