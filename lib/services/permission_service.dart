import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

class PermissionService {
  static final PermissionService _instance = PermissionService._internal();
  factory PermissionService() => _instance;
  PermissionService._internal();

  // SharedPreferences anahtarları
  static const String _locationPermissionKey = 'location_permission_status';
  static const String _notificationPermissionKey = 'notification_permission_status';
  static const String _microphonePermissionKey = 'microphone_permission_status';
  static const String _permissionsRequestedKey = 'permissions_requested';

  // İzin durumlarını kontrol et ve gerekirse iste
  Future<Map<Permission, PermissionStatus>> checkAndRequestPermissions({
    bool forceRequest = false,
    BuildContext? context,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final permissionsRequested = prefs.getBool(_permissionsRequestedKey) ?? false;
    
    print('[PERMISSION SERVICE] forceRequest: $forceRequest, permissionsRequested: $permissionsRequested');
    
    // Eğer izinler daha önce istenmişse ve forceRequest false ise, sadece durumu kontrol et
    if (permissionsRequested && !forceRequest) {
      print('[PERMISSION SERVICE] İzinler daha önce istenmiş, sadece durum kontrol ediliyor');
      return await _checkPermissionStatuses();
    }

    print('[PERMISSION SERVICE] İzinler isteniyor...');

    // İzinleri sırayla iste
    final results = <Permission, PermissionStatus>{};
    
    // 1. Konum İzni
    results[Permission.location] = await _requestPermissionWithFallback(
      Permission.location,
      _locationPermissionKey,
      'Konum izni, size yakın olan aile üyelerinin sizi bulabilmesi için gereklidir.',
      context,
      forceRequest: forceRequest,
    );
    
    // 2. Bildirim İzni
    results[Permission.notification] = await _requestPermissionWithFallback(
      Permission.notification,
      _notificationPermissionKey,
      'Bildirim izni, acil durum sinyallerini ve önemli güncellemeleri alabilmeniz için gereklidir.',
      context,
      forceRequest: forceRequest,
    );
    
    // 3. Mikrofon İzni
    results[Permission.microphone] = await _requestPermissionWithFallback(
      Permission.microphone,
      _microphonePermissionKey,
      'Mikrofon izni, sesli mesaj gönderebilmeniz ve ortam sesini kaydedebilmeniz için gereklidir.',
      context,
      forceRequest: forceRequest,
    );

    // İzinlerin istendiğini kaydet
    await prefs.setBool(_permissionsRequestedKey, true);
    
    print('[PERMISSION SERVICE] İzin isteme tamamlandı: $results');
    return results;
  }

  // Belirli bir izni güvenli şekilde iste
  Future<PermissionStatus> _requestPermissionWithFallback(
    Permission permission,
    String storageKey,
    String explanation,
    BuildContext? context,
    {bool forceRequest = false}
  ) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Mevcut durumu kontrol et
    final currentStatus = await permission.status;
    print('[PERMISSION SERVICE] $permission mevcut durum: $currentStatus');
    
    // Eğer izin zaten verilmişse, durumu kaydet ve döndür
    if (currentStatus.isGranted) {
      print('[PERMISSION SERVICE] $permission zaten verilmiş');
      await prefs.setString(storageKey, 'granted');
      return currentStatus;
    }
    
    // Eğer izin kalıcı olarak reddedilmişse ve forceRequest false ise, durumu kaydet ve döndür
    if (currentStatus.isPermanentlyDenied && !forceRequest) {
      print('[PERMISSION SERVICE] $permission kalıcı olarak reddedilmiş, forceRequest false');
      await prefs.setString(storageKey, 'permanently_denied');
      return currentStatus;
    }
    
    print('[PERMISSION SERVICE] $permission izni isteniyor...');
    // İzin iste
    final status = await permission.request();
    print('[PERMISSION SERVICE] $permission izin sonucu: $status');
    
    // Sonucu kaydet
    String statusString;
    switch (status) {
      case PermissionStatus.granted:
        statusString = 'granted';
        break;
      case PermissionStatus.denied:
        statusString = 'denied';
        break;
      case PermissionStatus.permanentlyDenied:
        statusString = 'permanently_denied';
        break;
      case PermissionStatus.restricted:
        statusString = 'restricted';
        break;
      case PermissionStatus.limited:
        statusString = 'limited';
        break;
      default:
        statusString = 'unknown';
    }
    
    await prefs.setString(storageKey, statusString);
    
    // Eğer izin reddedildiyse ve context varsa, kullanıcıya bilgi ver
    if (status.isDenied && context != null) {
      print('[PERMISSION SERVICE] $permission reddedildi, açıklama gösteriliyor');
      _showPermissionExplanation(context, permission, explanation);
    }
    
    return status;
  }

  // İzin durumlarını kontrol et (izin istemeden)
  Future<Map<Permission, PermissionStatus>> checkPermissionStatuses() async {
    return await _checkPermissionStatuses();
  }

  Future<Map<Permission, PermissionStatus>> _checkPermissionStatuses() async {
    final results = <Permission, PermissionStatus>{};
    
    results[Permission.location] = await Permission.location.status;
    results[Permission.notification] = await Permission.notification.status;
    results[Permission.microphone] = await Permission.microphone.status;
    
    return results;
  }

  // Belirli bir iznin durumunu kontrol et
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async {
    return await permission.status;
  }

  // Kaydedilmiş izin durumlarını al
  Future<Map<String, String>> getStoredPermissionStatuses() async {
    final prefs = await SharedPreferences.getInstance();
    
    return {
      'location': prefs.getString(_locationPermissionKey) ?? 'unknown',
      'notification': prefs.getString(_notificationPermissionKey) ?? 'unknown',
      'microphone': prefs.getString(_microphonePermissionKey) ?? 'unknown',
    };
  }

  // İzin açıklaması göster
  void _showPermissionExplanation(BuildContext context, Permission permission, String explanation) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('İzin Gerekli'),
          content: Text(explanation),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Tamam'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
              child: const Text('Ayarlar'),
            ),
          ],
        );
      },
    );
  }

  // Tüm izinlerin verilip verilmediğini kontrol et
  Future<bool> areAllPermissionsGranted() async {
    final statuses = await _checkPermissionStatuses();
    
    return statuses.values.every((status) => status.isGranted);
  }

  // Eksik izinleri al
  Future<List<Permission>> getMissingPermissions() async {
    final statuses = await _checkPermissionStatuses();
    final missing = <Permission>[];
    
    statuses.forEach((permission, status) {
      if (!status.isGranted) {
        missing.add(permission);
      }
    });
    
    return missing;
  }

  // İzin durumlarını sıfırla (test amaçlı)
  Future<void> resetPermissionStatuses() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_locationPermissionKey);
    await prefs.remove(_notificationPermissionKey);
    await prefs.remove(_microphonePermissionKey);
    await prefs.remove(_permissionsRequestedKey);
  }

  // İzin durumunu string olarak al
  String getPermissionStatusString(PermissionStatus status) {
    switch (status) {
      case PermissionStatus.granted:
        return 'Verildi';
      case PermissionStatus.denied:
        return 'Reddedildi';
      case PermissionStatus.permanentlyDenied:
        return 'Kalıcı Olarak Reddedildi';
      case PermissionStatus.restricted:
        return 'Kısıtlandı';
      case PermissionStatus.limited:
        return 'Sınırlı';
      default:
        return 'Bilinmiyor';
    }
  }

  // Mikrofon izni kontrolü ve isteği
  static Future<bool> requestMicrophonePermission() async {
    try {
      var status = await Permission.microphone.status;
      print('Mikrofon izni mevcut durumu: $status');
      
      if (status.isDenied) {
        print('Mikrofon izni isteniyor...');
        status = await Permission.microphone.request();
        print('Mikrofon izni sonucu: $status');
      }
      
      if (status.isPermanentlyDenied) {
        print('Mikrofon izni kalıcı olarak reddedildi');
        await openAppSettings();
        return false;
      }
      
      return status.isGranted;
    } catch (e) {
      print('Mikrofon izni hatası: $e');
      return false;
    }
  }
} 