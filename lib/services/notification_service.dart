import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/premium_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  final Battery _battery = Battery();
  
  StreamSubscription<BatteryState>? _batterySubscription;
  StreamSubscription<DatabaseEvent>? _locationSubscription;
  StreamSubscription<DatabaseEvent>? _sosSubscription;
  
  // Bildirim kanalları
  static const String _emergencyChannelId = 'emergency_channel';
  static const String _locationChannelId = 'location_channel';
  static const String _batteryChannelId = 'battery_channel';
  static const String _generalChannelId = 'general_channel';

  Future<void> initialize() async {
    try {
      // Firebase Messaging izinleri ARTIK BURADA İSTENMEYECEK
      // await _requestNotificationPermissions();
      
      // Yerel bildirim kanallarını oluştur
      await _createNotificationChannels();
      
      // Yerel bildirimleri başlat
      await _initializeLocalNotifications();
      
      // Firebase Messaging dinleyicilerini ayarla
      await _setupFirebaseMessaging();
      
      // Batarya durumu takibini başlat
      await _startBatteryMonitoring();
      
      debugPrint('Bildirim servisi başarıyla başlatıldı');
    } catch (e) {
      debugPrint('Bildirim servisi başlatılırken hata: $e');
    }
  }

  Future<void> _createNotificationChannels() async {
    if (Platform.isAndroid) {
      // Acil durum kanalı
      AndroidNotificationChannel emergencyChannel = AndroidNotificationChannel(
        _emergencyChannelId,
        'Acil Durum Bildirimleri',
        description: 'SOS ve acil durum bildirimleri',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('alarm'),
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
        showBadge: true,
      );

      // Konum güncelleme kanalı
      AndroidNotificationChannel locationChannel = AndroidNotificationChannel(
        _locationChannelId,
        'Konum Bildirimleri',
        description: 'Konum güncellemeleri ve geofence bildirimleri',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 300, 100, 300]),
      );

      // Batarya uyarı kanalı
      const AndroidNotificationChannel batteryChannel = AndroidNotificationChannel(
        _batteryChannelId,
        'Batarya Uyarıları',
        description: 'Düşük batarya uyarıları',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );

      // Genel bildirim kanalı
      const AndroidNotificationChannel generalChannel = AndroidNotificationChannel(
        _generalChannelId,
        'Genel Bildirimler',
        description: 'Genel uygulama bildirimleri',
        importance: Importance.defaultImportance,
        playSound: true,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(emergencyChannel);

      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(locationChannel);

      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(batteryChannel);

      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(generalChannel);
    }
  }

  Future<void> _initializeLocalNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('ic_notification');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
  }

  Future<void> _setupFirebaseMessaging() async {
    // Ön planda mesaj alma
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    
    // Arka planda mesaj alma
    FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessage);
    
    // Uygulama kapalıyken açılma
    RemoteMessage? initialMessage = await _firebaseMessaging.getInitialMessage();
    if (initialMessage != null) {
      _handleBackgroundMessage(initialMessage);
    }
  }

  Future<void> _startBatteryMonitoring() async {
    _batterySubscription = _battery.onBatteryStateChanged.listen((BatteryState state) async {
      final batteryLevel = await _battery.batteryLevel;
      
      if (batteryLevel <= 20 && state == BatteryState.discharging) {
        await showBatteryWarning(batteryLevel);
      }
    });
  }

  void _onNotificationTapped(NotificationResponse response) {
    // Bildirime tıklandığında yapılacak işlemler
    debugPrint('Bildirime tıklandı: ${response.payload}');
    
    // TODO: Bildirim türüne göre uygun ekrana yönlendir
    switch (response.payload) {
      case 'sos':
        // Acil durum ekranına git
        break;
      case 'location':
        // Konum detay ekranına git
        break;
      case 'battery':
        // Ayarlar ekranına git
        break;
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('Ön planda mesaj alındı: ${message.data}');
    
    // Mesaj türüne göre yerel bildirim göster
    switch (message.data['type']) {
      case 'sos':
        // Firebase'den gelen konum verisini ayrıştırıp Position'a çevir
        Position? position;
        if (message.data['latitude'] != null && message.data['longitude'] != null) {
          try {
            final lat = double.parse(message.data['latitude'].toString());
            final lon = double.parse(message.data['longitude'].toString());
            position = Position(latitude: lat, longitude: lon, timestamp: DateTime.now(), accuracy: 0, altitude: 0, altitudeAccuracy: 0, heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0);
          } catch(e) {
            debugPrint("Firebase'den gelen konum ayrıştırılamadı: $e");
          }
        }
        showSOSNotification(position);
        break;
      case 'location_update':
        showLocationUpdateNotification(
          message.data['elderlyName'] ?? 'Takip edilen kişi',
          message.data['location'] ?? 'Yeni konum alındı',
        );
        break;
      case 'geofence':
        showGeofenceNotification(
          message.data['elderlyName'] ?? 'Takip edilen kişi',
          message.data['action'] ?? 'enter',
          message.data['areaName'] ?? 'Güvenli Alan',
        );
        break;
      default:
        _showGeneralNotification(message);
    }
  }

  void _handleBackgroundMessage(RemoteMessage message) {
    debugPrint('Arka planda mesaj alındı: ${message.data}');
    // Arka planda mesaj işleme
  }

  Future<bool> _isNotificationTypeEnabled(String type) async {
    final prefs = await SharedPreferences.getInstance();
    final all = prefs.getBool('notificationsEnabled') ?? true;
    if (!all) return false;
    switch (type) {
      case 'sos':
        return prefs.getBool('sosNotificationsEnabled') ?? true;
      case 'location':
        return prefs.getBool('locationNotificationsEnabled') ?? true;
      case 'battery':
        return prefs.getBool('batteryNotificationsEnabled') ?? true;
      case 'geofence':
        return prefs.getBool('geofenceNotificationsEnabled') ?? true;
      default:
        return true;
    }
  }

  // SOS Bildirimi (Aile cihazlarına gidecek)
  Future<void> showSOSNotification(Position? position) async {
    if (!await _isNotificationTypeEnabled('sos')) return;
    final String title = '🚨 ACİL DURUM: SOS SİNYALİ ALINDI! 🚨';
    final String body = position != null
        ? 'Yardım çağrısı yapıldı! Son bilinen konum: Lat: ${position.latitude.toStringAsFixed(4)}, Lon: ${position.longitude.toStringAsFixed(4)}'
        : 'Yardım çağrısı yapıldı! Konum bilgisi alınamadı.';

    AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _emergencyChannelId,
      'Acil Durum Bildirimleri',
      channelDescription: 'SOS ve acil durum bildirimleri',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('alarm'),
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      ongoing: false,
      autoCancel: true,
      icon: 'ic_sos_notification',
      largeIcon: const DrawableResourceAndroidBitmap('logo_notification_48dp'),
    );

    NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'alarm.aiff',
        categoryIdentifier: 'SOS',
      ),
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      notificationDetails,
      payload: 'sos',
    );
  }

  // SOS Gönderildi Bildirimi (Yaşlı cihazına gidecek)
  Future<void> showSOSSentNotification() async {
    const String title = '✅ SOS Çağrınız İletildi';
    const String body = 'Acil durum sinyali aile üyelerinize başarıyla iletildi.';

    AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _emergencyChannelId,
      'Acil Durum Bildirimleri',
      channelDescription: 'SOS ve acil durum bildirimleri',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 300, 100, 300]),
      icon: 'ic_sos_notification',
      largeIcon: const DrawableResourceAndroidBitmap('logo_notification_48dp'),
    );

    NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        categoryIdentifier: 'SOS_SENT',
      ),
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000) + 1,
      title,
      body,
      notificationDetails,
      payload: 'sos_sent',
    );
  }

  // Konum Güncelleme Bildirimi
  Future<void> showLocationUpdateNotification(String elderlyName, String location) async {
    if (!await _isNotificationTypeEnabled('location')) return;
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _locationChannelId,
      'Konum Bildirimleri',
      channelDescription: 'Konum güncellemeleri ve geofence bildirimleri',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: 'ic_notification_vector',
      largeIcon: DrawableResourceAndroidBitmap('logo_notification_48dp'),
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        categoryIdentifier: 'LOCATION',
      ),
    );

    await _localNotifications.show(
      1002,
      '📍 Konum Güncellendi',
      '$elderlyName: $location',
      notificationDetails,
      payload: 'location',
    );
  }

  // Geofence Bildirimi
  Future<void> showGeofenceNotification(String elderlyName, String action, String areaName) async {
    if (!await _isNotificationTypeEnabled('geofence')) return;
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _locationChannelId,
      'Konum Bildirimleri',
      channelDescription: 'Konum güncellemeleri ve geofence bildirimleri',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: 'ic_geofence_notification',
      largeIcon: DrawableResourceAndroidBitmap('logo_notification_48dp'),
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        categoryIdentifier: 'GEOFENCE',
      ),
    );

    String message = action == 'enter' 
        ? '$elderlyName güvenli alana girdi: $areaName'
        : '$elderlyName güvenli alandan çıktı: $areaName';

    await _localNotifications.show(
      1003,
      '🏠 Güvenli Alan Bildirimi',
      message,
      notificationDetails,
      payload: 'geofence',
    );
  }

  // Batarya Uyarı Bildirimi
  Future<void> showBatteryWarning(int batteryLevel) async {
    final isPremium = await PremiumService.isUserPremium();
    if (isPremium == null) return;
    if (!isPremium) return;
    if (!await _isNotificationTypeEnabled('battery')) return;
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _batteryChannelId,
      'Batarya Uyarıları',
      channelDescription: 'Düşük batarya uyarıları',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: 'ic_battery_notification',
      largeIcon: DrawableResourceAndroidBitmap('logo_notification_48dp'),
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        categoryIdentifier: 'BATTERY',
      ),
    );

    await _localNotifications.show(
      1004,
      '🔋 Düşük Batarya',
      'Batarya seviyesi %$batteryLevel. Lütfen şarj edin.',
      notificationDetails,
      payload: 'battery',
    );
  }

  // Genel Bildirim
  Future<void> _showGeneralNotification(RemoteMessage message) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _generalChannelId,
      'Genel Bildirimler',
      channelDescription: 'Genel uygulama bildirimleri',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      playSound: true,
      icon: 'ic_info_notification',
      largeIcon: DrawableResourceAndroidBitmap('logo_notification_48dp'),
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _localNotifications.show(
      1005,
      message.notification?.title ?? 'GPS Tracker',
      message.notification?.body ?? 'Yeni bildirim',
      notificationDetails,
      payload: 'general',
    );
  }

  // Konum takibi başlat
  Future<void> startLocationTracking(String elderlyId) async {
    _locationSubscription?.cancel();
    
    _locationSubscription = FirebaseDatabase.instance
        .ref('locations/$elderlyId/current_location')
        .onValue
        .listen((event) {
      if (event.snapshot.value != null) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        if (data['latitude'] != null && data['longitude'] != null) {
          // Konum güncelleme bildirimi göster
          showLocationUpdateNotification(
            'Takip edilen kişi',
            'Yeni konum alındı',
          );
        }
      }
    });
  }

  // SOS takibi başlat (Aile cihazları için)
  Future<void> startSOSTracking(String elderlyDeviceId) async {
    debugPrint('🔍 [SOS TAKİP] Başlatılıyor... Cihaz ID: $elderlyDeviceId');
    
    // Önceki dinleyiciyi iptal et
    await _sosSubscription?.cancel();

    final sanitizedDeviceId = elderlyDeviceId.replaceAll(RegExp(r'[.#$\[\]]'), '_');
    final dbRef = FirebaseDatabase.instance.ref('sos_alerts/$sanitizedDeviceId');
    
    debugPrint('🔍 [SOS TAKİP] Firebase yolu: sos_alerts/$sanitizedDeviceId');

    // Dinlemeye başladığımız zamanı kaydedelim. 
    // Firebase `onChildAdded` ilk başta tüm eski kayıtları da getirdiği için bu gerekli.
    final listeningStartTime = DateTime.now().millisecondsSinceEpoch;
    
    // Sadece yeni eklenen kayıtları dinle (onChildAdded)
    _sosSubscription = dbRef.onChildAdded.listen((event) async {
      debugPrint('🔍 [SOS TAKİP] Yeni SOS verisi geldi: ${event.snapshot.value}');
      
      final alertTimestamp = int.tryParse(event.snapshot.key ?? '0') ?? 0;

      // Sadece dinlemeye başladıktan SONRA gelen bildirimleri işle
      if (alertTimestamp < listeningStartTime) {
        debugPrint('🔍 [SOS TAKİP] Eski kayıt (${event.snapshot.key}) - bildirim atlanıyor.');
        return;
      }
      
      if (event.snapshot.value != null) {
        // Type casting hatasını düzelt - güvenli dönüşüm
        Map<String, dynamic> data;
        try {
          if (event.snapshot.value is Map) {
            final rawData = event.snapshot.value as Map;
            data = Map<String, dynamic>.from(rawData);
          } else {
            debugPrint('❌ [SOS TAKİP] Veri Map tipinde değil: ${event.snapshot.value.runtimeType}');
            return;
          }
        } catch (e) {
          debugPrint('❌ [SOS TAKİP] Veri dönüştürme hatası: $e');
          return;
        }
        
        debugPrint('🔍 [SOS TAKİP] Veri ayrıştırıldı: $data');
        
        // Test kayıtları için bildirim gösterme
        if (data['test'] == true) {
          debugPrint('🔍 [SOS TAKİP] Test kaydı - bildirim gösterilmiyor');
          return;
        }
        
        // Location verisini güvenli şekilde al
        Map<String, dynamic>? locationData;
        try {
          final locationRaw = data['location'];
          if (locationRaw is Map) {
            locationData = Map<String, dynamic>.from(locationRaw);
          }
        } catch (e) {
          debugPrint('❌ [SOS TAKİP] Location verisi dönüştürme hatası: $e');
        }
        
        debugPrint('🔍 [SOS TAKİP] Konum verisi: $locationData');
        
        Position? position;
        if (locationData != null && locationData['latitude'] != null && locationData['longitude'] != null) {
          try {
            position = Position(
              latitude: (locationData['latitude'] as num).toDouble(),
              longitude: (locationData['longitude'] as num).toDouble(),
              timestamp: DateTime.now(),
              accuracy: 0,
              altitude: 0,
              altitudeAccuracy: 0,
              heading: 0,
              headingAccuracy: 0,
              speed: 0,
              speedAccuracy: 0,
            );
            debugPrint('🔍 [SOS TAKİP] Position oluşturuldu: ${position.latitude}, ${position.longitude}');
          } catch (e) {
            debugPrint("❌ [SOS TAKİP] SOS konum verisi ayrıştırılamadı: $e");
          }
        }
        
        // Aile cihazına SOS bildirimi göster
        debugPrint('🔍 [SOS TAKİP] SOS bildirimi gösteriliyor...');
        await showSOSNotification(position);
        debugPrint('✅ [SOS TAKİP] SOS bildirimi gösterildi!');
      } else {
        debugPrint('❌ [SOS TAKİP] Event snapshot value null!');
      }
    }, onError: (error) {
      debugPrint('❌ [SOS TAKİP] Dinleme hatası: $error');
    });
    
    debugPrint('✅ [SOS TAKİP] SOS takibi başlatıldı!');
  }

  // SOS takibini durdur
  Future<void> stopSOSTracking() async {
    debugPrint('🛑 [SOS TAKİP] Durduruluyor...');
    await _sosSubscription?.cancel();
    _sosSubscription = null;
    debugPrint('✅ [SOS TAKİP] SOS takibi durduruldu!');
  }

  // Konum takibini durdur
  void stopLocationTracking() {
    _locationSubscription?.cancel();
  }

  // Tüm bildirimleri temizle
  Future<void> clearAllNotifications() async {
    await _localNotifications.cancelAll();
  }

  // Belirli bildirimi temizle
  Future<void> clearNotification(int id) async {
    await _localNotifications.cancel(id);
  }

  // Servisi temizle
  void dispose() {
    _batterySubscription?.cancel();
    _locationSubscription?.cancel();
    _sosSubscription?.cancel();
  }

  // FCM Token al
  Future<String?> getFCMToken() async {
    return await _firebaseMessaging.getToken();
  }

  // Topic'e abone ol
  Future<void> subscribeToTopic(String topic) async {
    await _firebaseMessaging.subscribeToTopic(topic);
  }

  // Topic'ten çık
  Future<void> unsubscribeFromTopic(String topic) async {
    await _firebaseMessaging.unsubscribeFromTopic(topic);
  }

  // Tüm temel bildirimleri test et
  Future<void> showAllTestNotifications() async {
    // SOS
    await showSOSNotification(null);
    // SOS Gönderildi
    await showSOSSentNotification();
    // Konum
    await showLocationUpdateNotification('Test Yaşlı', 'Test Lokasyon');
    // Geofence GİRİŞ
    await _localNotifications.show(
      20001,
      '🏠 Güvenli Alan GİRİŞ Testi',
      'Test Yaşlı güvenli alana GİRDİ: Test Alanı',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _locationChannelId,
          'Konum Bildirimleri',
          channelDescription: 'Konum güncellemeleri ve geofence bildirimleri',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: 'ic_geofence_notification',
          largeIcon: DrawableResourceAndroidBitmap('logo_notification_48dp'),
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          categoryIdentifier: 'GEOFENCE',
        ),
      ),
      payload: 'geofence',
    );
    debugPrint('Güvenli Alan GİRİŞ bildirimi gönderildi');
    // Geofence ÇIKIŞ
    await _localNotifications.show(
      20002,
      '🏠 Güvenli Alan ÇIKIŞ Testi',
      'Test Yaşlı güvenli alandan ÇIKTI: Test Alanı',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _locationChannelId,
          'Konum Bildirimleri',
          channelDescription: 'Konum güncellemeleri ve geofence bildirimleri',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: 'ic_geofence_notification',
          largeIcon: DrawableResourceAndroidBitmap('logo_notification_48dp'),
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          categoryIdentifier: 'GEOFENCE',
        ),
      ),
      payload: 'geofence',
    );
    debugPrint('Güvenli Alan ÇIKIŞ bildirimi gönderildi');
    // Batarya
    await showBatteryWarning(15);
    // Genel
    await _localNotifications.show(
      9999,
      'Test Genel Bildirim',
      'Bu bir test genel bildirimidir.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _generalChannelId,
          'Genel Bildirimler',
          channelDescription: 'Genel uygulama bildirimleri',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          playSound: true,
          icon: 'ic_info_notification',
          largeIcon: DrawableResourceAndroidBitmap('logo_notification_48dp'),
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: 'general',
    );
    debugPrint('Genel test bildirimi gönderildi');
  }
} 