import 'dart:async';
import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';
import 'battery_optimization_service.dart';
import 'package:flutter/services.dart';
import 'cache_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_service.dart';
import 'alarm_audio_player.dart';
import 'package:battery_plus/battery_plus.dart';

// Bu fonksiyon artık bir üst düzey fonksiyon ve servis başladığında çağrılır.
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // =======================================================================
  print('--- ARKA PLAN SERVISI YENI KODLA BAŞLATILDI --- v5.0 ---');
  // =======================================================================

  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();
  
  // CacheService'i başlat
  final cacheService = CacheService();
  await cacheService.initialize();
  
  try {
    await Firebase.initializeApp();
  } catch (e) {
    print('Arka planda Firebase başlatılamadı: $e');
  }
  
  // Cihaz ID'sini al ve güvenli hale getir
  String? originalDeviceId;
  try {
    originalDeviceId = await _getDeviceId();
    if (originalDeviceId == null) {
      service.stopSelf();
      return;
    }
  } catch (e) {
    print('Cihaz ID alınamadı: $e');
    service.stopSelf();
    return;
  }
  final safeDeviceId = originalDeviceId.replaceAll(RegExp(r'[.#$\[\]]'), '_');

  // Konum verilerini şifreli olarak Firebase'e kaydet
  Future<void> saveLocationToFirebase(LatLng position) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('❌ [KONUM KAYIT] Kullanıcı girişi bulunamadı');
        return;
      }
      // Kullanıcı anahtarını al
      final storage = const FlutterSecureStorage();
      String? key = await storage.read(key: 'user_key_${user.uid}');
      if (key == null) {
        print('❌ [KONUM KAYIT] Kullanıcı anahtarı bulunamadı');
        return;
      }
      final locationData = {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'timestamp': DateTime.now().toIso8601String(),
        'deviceId': originalDeviceId,
      };
      // Konum verisini şifrele
      final encryptedData = await AuthService.encryptData(jsonEncode(locationData), user.uid);
      // Şifreli konum verisini Firebase'e kaydet
      await FirebaseDatabase.instance.ref('locations/$safeDeviceId').set(encryptedData);
      print('✅ [KONUM KAYIT] Şifreli konum verisi kaydedildi: $safeDeviceId');
    } catch (e) {
      print('❌ [KONUM KAYIT] Konum kaydetme hatası: $e');
    }
  }

  // Firebase dinleme bağlantılarını yönetmek için değişkenler
  StreamSubscription<DatabaseEvent>? listenRequestSubscription;
  StreamSubscription<DatabaseEvent>? voiceMessageSubscription;
  Timer? reconnectTimer;
  Timer? healthCheckTimer;
  Timer? alarmCheckTimer;
  bool isConnected = false;
 

  // Firebase dinleyicilerini kur
  Future<void> setupFirebaseListeners() async {
    // Dinleme isteklerini dinle
    final listenRequestRef = FirebaseDatabase.instance.ref('listen_requests/$safeDeviceId');
    listenRequestSubscription = listenRequestRef.onValue.listen(
      (event) {
        final data = event.snapshot.value as Map?;
        if (data != null && data['request'] == true) {
          print('Ortam sesi dinleme isteği alındı.');
          _recordAndUploadAudio(safeDeviceId);
          listenRequestRef.remove();
        }
      },
      onError: (error) {
        print('Firebase dinleme hatası: $error');
        isConnected = false;
      },
    );

    // Gelen sesli mesajları dinle
    final voiceMessageRef = FirebaseDatabase.instance.ref('voice_messages/$safeDeviceId');
    voiceMessageSubscription = voiceMessageRef.onChildAdded.listen(
      (event) async {
        final data = event.snapshot.value as Map?;
        if (data != null && data['url'] != null) {
          print('Yeni sesli mesaj alındı: ${data['url']}');
          try {
            await AlarmAudioPlayer.instance.play(UrlSource(data['url']));
          } catch (e) {
            print('Sesli mesaj çalınamadı: $e');
          }
        }
      },
      onError: (error) {
        print('Firebase sesli mesaj dinleme hatası: $error');
        isConnected = false;
      },
    );
  }

  // Firebase bağlantısını yeniden kurma fonksiyonu
  Future<void> reconnectToFirebase() async {
    try {
      print('Firebase bağlantısı yeniden kuruluyor...');
      
      // Önceki dinleyicileri iptal et
      listenRequestSubscription?.cancel();
      voiceMessageSubscription?.cancel();
      
      // Yeni dinleyicileri başlat
      await setupFirebaseListeners();
      
      isConnected = true;
      print('Firebase bağlantısı başarıyla yeniden kuruldu');
    } catch (e) {
      print('Firebase yeniden bağlanma hatası: $e');
      isConnected = false;
      
      // 5 saniye sonra tekrar dene
      reconnectTimer?.cancel();
      reconnectTimer = Timer(const Duration(seconds: 5), () {
        reconnectToFirebase();
      });
    }
  }

  // Sağlık kontrolü - her 15 saniyede bir bağlantıyı kontrol et ve koparsa otomatik yeniden bağlan
  void startHealthCheck() {
    healthCheckTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
      try {
        await FirebaseDatabase.instance.ref('health_check/$safeDeviceId').set({
          'timestamp': DateTime.now().toIso8601String(),
          'device_id': safeDeviceId,
        });
        isConnected = true;
      } catch (e) {
        print('Bağlantı kopuk, yeniden bağlanılıyor...');
        isConnected = false;
        await reconnectToFirebase();
      }
    });
  }

  // Alarm kontrolü - her 15 saniyede bir alarm isteklerini kontrol et
  void startAlarmCheck() {
    print('[ALARM][DEBUG] startAlarmCheck fonksiyonu başlatıldı');
    alarmCheckTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
      print('[ALARM][DEBUG] Timer tetiklendi, Firebase alarm kontrolü başlıyor');
      try {
        final alarmRef = FirebaseDatabase.instance.ref('alarms/$safeDeviceId');
        final snapshot = await alarmRef.get();
        print('[ALARM][DEBUG] Firebase alarms/$safeDeviceId yolundan veri çekildi: exists=${snapshot.exists}');
        if (snapshot.exists) {
          final data = snapshot.value as Map?;
          print('[ALARM][DEBUG] Alarm verisi: $data');
          // Alarmı durdurma kontrolü
          if (data != null && (data['alarm'] == false || data['alarm_playing'] == false)) {
            AlarmAudioPlayer.instance.stop();
            print('[ALARM][DEBUG] Alarm durduruldu, player da durduruldu.');
          }
          if (data != null && data['alarm'] == true) {
            // Alarm zaten çalıyor mu kontrolü
            final alarmPlayingRef = FirebaseDatabase.instance.ref('alarms/$safeDeviceId/alarm_playing');
            final alarmPlayingSnapshot = await alarmPlayingRef.get();
            final isAlarmPlaying = alarmPlayingSnapshot.value == true;
            if (isAlarmPlaying) {
              print('[ALARM][DEBUG] Alarm zaten çalıyor, yeni alarm başlatılmadı.');
              return;
            }
            print('[ALARM] Alarm isteği alındı, alarm çalınıyor...');
            final prefs = await SharedPreferences.getInstance();
            final customAlarmPath = prefs.getString('alarm_sound_path');
            bool played = false;
            String? alarmFilePath = customAlarmPath;

            // --- YENİ: Firebase'den alarm sesi ve dosya adı çekme ---
            try {
              final alarmSoundRef = FirebaseDatabase.instance.ref('alarm_sounds/$safeDeviceId');
              final alarmSoundSnap = await alarmSoundRef.get();
              print('[ALARM][DEBUG] alarm_sounds/$safeDeviceId yolundan veri çekildi: exists= [alarmSoundSnap.exists]');
              if (alarmSoundSnap.exists) {
                final alarmSoundData = alarmSoundSnap.value as Map?;
                final audioBase64 = alarmSoundData?['audio_base64'] as String?;
                final fileName = alarmSoundData?['file_name'] as String?;
                print('[ALARM][DEBUG] audio_base64 var mı:  [audioBase64 != null], file_name: $fileName');
                if (audioBase64 != null && fileName != null) {
                  final dir = await getApplicationDocumentsDirectory();
                  final filePath = '${dir.path}/$fileName';
                  final file = File(filePath);
                  // Her seferinde aile cihazından gelen dosyayı güncelle
                  try {
                    final bytes = base64Decode(audioBase64);
                    await file.writeAsBytes(bytes, flush: true);
                    print('[ALARM] Dosya kaydedildi/güncellendi: $filePath');
                  } catch (e) {
                    print('[ALARM][HATA] Dosya decode/kaydetme hatası: $e');
                  }
                  alarmFilePath = filePath;
                } else {
                  print('[ALARM][HATA] Firebase alarm sesi verisi eksik!');
                }
              } else {
                print('[ALARM] Firebase alarm sesi bulunamadı. Varsayılan alarm.mp3 çalınacak.');
              }
            } catch (e) {
              print('[ALARM][HATA] Firebase alarm sesi çekme hatası: $e');
            }

            // --- Dosyayı çal ---
            if (alarmFilePath != null && alarmFilePath.isNotEmpty) {
              final file = File(alarmFilePath);
              print('[ALARM][DEBUG] alarmFilePath: $alarmFilePath, exists: ${await file.exists()}');
              if (await file.exists()) {
                try {
                  await AlarmAudioPlayer.instance.play(DeviceFileSource(alarmFilePath), volume: 1.0);
                  played = true;
                  print('[ALARM] Özel alarm sesi çalındı: $alarmFilePath');
                } catch (e) {
                  print('[ALARM][HATA] Özel alarm sesi çalınamadı: $e');
                }
              } else {
                print('[ALARM] Alarm dosyası bulunamadı: $alarmFilePath');
              }
            }

            // --- Fallback: alarm.mp3 ---
            if (!played) {
              try {
                await AlarmAudioPlayer.instance.play(AssetSource('alarm.mp3'), volume: 1.0);
                print('[ALARM] Varsayılan alarm.mp3 çalındı.');
              } catch (e) {
                print('[ALARM][HATA] alarm.mp3 çalınamadı: $e');
              }
            }

            // Alarmı resetle
            // await alarmRef.set({'alarm': false}); // Bu kısım artık alarm_playing flag'i yönetilecek.
          }
        }
      } catch (e) {
        print('[ALARM][HATA] Alarm kontrolünde hata: $e');
      }
    });
  }

  // Servis durumunu Firebase'e yaz - her 30 saniyede bir
  void startServiceStatusUpdate() {
    Timer.periodic(const Duration(seconds: 30), (timer) async {
      try {
        await FirebaseDatabase.instance.ref('service_status/$safeDeviceId').set({
          'timestamp': DateTime.now().toIso8601String(),
          'status': isConnected ? 'running' : 'stopped',
          'device_id': safeDeviceId,
        });
      } catch (e) {
        print('Servis durumu güncelleme hatası: $e');
      }
    });
  }

  // İlk bağlantıyı kur
  await setupFirebaseListeners();
  isConnected = true;
  print('İlk Firebase bağlantısı kuruldu');
  
  // Sağlık kontrolü ve alarm kontrolünü başlat
  startHealthCheck();
  startAlarmCheck();
  startServiceStatusUpdate();

  // Pil optimizasyonu servisini başlat
  final batteryOptimization = BatteryOptimizationService();
  await batteryOptimization.initialize();

  // Batarya seviyesini Firebase'e yazan fonksiyon
  Future<void> saveBatteryLevelToFirebase() async {
    try {
      final battery = Battery();
      final deviceInfo = DeviceInfoPlugin();
      int batteryLevel = 100;
      String? deviceId;
      if (Platform.isAndroid) {
        deviceId = (await deviceInfo.androidInfo).id;
      } else if (Platform.isIOS) {
        deviceId = (await deviceInfo.iosInfo).identifierForVendor;
      }
      if (deviceId == null) return;
      final safeDeviceId = deviceId.replaceAll(RegExp(r'[.#$\[\]]'), '_');
      // Batarya seviyesini al
      batteryLevel = await battery.batteryLevel;
      final dbRef = FirebaseDatabase.instance.ref('battery_levels/$safeDeviceId');
      await dbRef.set({
        'level': batteryLevel,
        'timestamp': DateTime.now().toIso8601String(),
        'deviceId': deviceId,
      });
      print('[ARKA PLAN] Batarya seviyesi Firebase\'e yazıldı: $batteryLevel');
    } catch (e) {
      print('[ARKA PLAN] Batarya seviyesi yazma hatası: $e');
    }
  }

  // Batarya seviyesini periyodik olarak güncelle (her 5 dakika)
  Timer.periodic(const Duration(minutes: 5), (timer) async {
    await saveBatteryLevelToFirebase();
  });

  // ARKA PLANDA SOS KONTROLÜ (örnek: bir dosya ile tetikleme)
  Timer.periodic(const Duration(minutes: 1), (timer) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final sosFile = File('${dir.path}/sos_request.txt');
      if (await sosFile.exists()) {
        final content = await sosFile.readAsString();
        if (content.trim() == 'SOS') {
          // SOS tetikleme
          final deviceInfo = DeviceInfoPlugin();
          String? deviceId;
          if (Platform.isAndroid) {
            deviceId = (await deviceInfo.androidInfo).id;
          } else if (Platform.isIOS) {
            deviceId = (await deviceInfo.iosInfo).identifierForVendor;
          }
          if (deviceId != null) {
            final safeDeviceId = deviceId.replaceAll(RegExp(r'[.#$\[\]]'), '_');
            Position? position;
            try {
              position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
            } catch (e) {
              position = null;
            }
            await FirebaseDatabase.instance
                .ref('sos_alerts/$safeDeviceId/${DateTime.now().millisecondsSinceEpoch}')
                .set({
              'timestamp': ServerValue.timestamp,
              'status': 'active',
              'location': position != null
                  ? {'latitude': position.latitude, 'longitude': position.longitude}
                  : null,
            });
            print('[ARKA PLAN] SOS tetiklendi ve Firebase\'e yazıldı!');
            await sosFile.delete(); // SOS isteğini sıfırla
          }
        }
      }
    } catch (e) {
      print('[ARKA PLAN] SOS kontrol hatası: $e');
    }
  });

  // --- SONU ---

  // Dinamik Firebase dinleme aralığı
  void startDynamicFirebaseListener() async {
    while (true) {
      final interval = batteryOptimization.getOptimalFirebaseListenInterval();
      final shouldListen = batteryOptimization.shouldListenToAudio();
      if (!shouldListen) {
        print('Pil seviyesi düşük, ses dinleme durduruldu.');
        listenRequestSubscription?.cancel();
        voiceMessageSubscription?.cancel();
        await Future.delayed(Duration(milliseconds: interval));
        continue;
      }
      // Bağlantı kopuksa yeniden bağlan
      if (!isConnected) {
        reconnectToFirebase();
      }
      await Future.delayed(Duration(milliseconds: interval));
    }
  }

  startDynamicFirebaseListener();



  // Konum güncelleme aralığını SharedPreferences'tan oku
  final prefs = await SharedPreferences.getInstance();
  final intervalMinutes = prefs.getInt('location_update_interval_minutes') ?? 5;
  final selectedElderlyId = prefs.getString('selected_elderly_id') ?? safeDeviceId;
  String? elderlyName = prefs.getString('selected_elderly_name') ?? 'Takip edilen kişi';

  // Son durumun tekrar tekrar bildirilmemesi için flag
  bool wasOutside = false;

  print("✅ Arka plan servisi ISOLATE BAŞLATILDI. Cihaz: $safeDeviceId, Takip edilen yaşlı: $selectedElderlyId");

  service.on('stopService').listen((event) {
    listenRequestSubscription?.cancel();
    voiceMessageSubscription?.cancel();
    reconnectTimer?.cancel();
    healthCheckTimer?.cancel();
    alarmCheckTimer?.cancel();
    service.stopSelf();
    print("🛑 Arka plan servisi durduruldu.");
  });

  // Konum gönderme ve geofence kontrolü Timer'ı
  Timer.periodic(Duration(minutes: intervalMinutes), (timer) async {
    try {
      // Bildirim tercihini kontrol et
      final prefs = await SharedPreferences.getInstance();
      final all = prefs.getBool('notificationsEnabled') ?? true;
      final tracking = prefs.getBool('trackingNotificationsEnabled') ?? true;
      if (!all || !tracking) return;
      final position = await Geolocator.getCurrentPosition();
      // Konumu Firebase'e yaz
              await saveLocationToFirebase(LatLng(position.latitude, position.longitude));
      print('[ARKA PLAN] Konum Firebase\'e gönderildi: $safeDeviceId, $position');

      // Güvenli alanı Firebase'den çek
      final geofenceSnap = await FirebaseDatabase.instance.ref('geofence/$selectedElderlyId').get();
      if (geofenceSnap.exists && geofenceSnap.value != null && geofenceSnap.value is Map) {
        final data = geofenceSnap.value as Map;
        final center = LatLng((data['lat'] as num).toDouble(), (data['lng'] as num).toDouble());
        final radius = (data['radius'] as num).toDouble();
        final currentPos = LatLng(position.latitude, position.longitude);
        final distance = Distance().as(LengthUnit.Meter, center, currentPos);
        final isOutside = distance > radius;

        // Sadece dışarı çıkış anında bildir
        if (isOutside && !wasOutside) {
          print('Arka Plan: Kişi güvenli alanın dışına çıktı!');
          // Bildirim gönder
          final notifications = FlutterLocalNotificationsPlugin();
          const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
            'location_channel',
            'Konum Bildirimleri',
            channelDescription: 'Konum güncellemeleri ve geofence bildirimleri',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            icon: 'ic_mic_notification',
            largeIcon: DrawableResourceAndroidBitmap('logo_notification_48dp'),
            ongoing: true,
            autoCancel: false,
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
          await notifications.show(
            1003,
            '🏠 Güvenli Alan Bildirimi',
            '$elderlyName güvenli alandan çıktı!',
            notificationDetails,
            payload: 'geofence',
          );
        }
        wasOutside = isOutside;
      }
    } catch(e) {
      print('[ARKA PLAN] Konum/güvenli alan kontrol hatası: $e, deviceId: $safeDeviceId');
    }
  });

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
  }

  // Foreground servis bildirimi için özel ikon ve largeIcon kullan
  final notifications = FlutterLocalNotificationsPlugin();
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'gps_tracker_channel',
    'GPS Takip Sistemi',
    channelDescription: 'GPS takip servisi bildirimi',
    importance: Importance.low,
    priority: Priority.low,
    playSound: false,
    enableVibration: false,
    icon: 'ic_mic_notification',
    largeIcon: DrawableResourceAndroidBitmap('logo_notification_48dp'),
    ongoing: true,
    autoCancel: false,
  );
  const NotificationDetails notificationDetails = NotificationDetails(
    android: androidDetails,
  );
  await notifications.show(
    888,
    'GPS Takip Servisi',
    'Arka planda ortam sesi dinleniyor',
    notificationDetails,
  );
}

Future<String?> _getDeviceId() async {
  final deviceInfo = DeviceInfoPlugin();
  if (Platform.isAndroid) {
    final androidInfo = await deviceInfo.androidInfo;
    return androidInfo.id;
  } else if (Platform.isIOS) {
    final iosInfo = await deviceInfo.iosInfo;
    return iosInfo.identifierForVendor;
  }
  return null;
}

// iOS için arka plan servisi (üst düzey fonksiyon)
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

class BackgroundService {

  // Bildirim kanalını oluşturmak için ayrı bir fonksiyon.
  static Future<void> createNotificationChannel() async {
      final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'gps_tracker_channel',
        'GPS Takip Sistemi',
        description: 'Konum takibi için bildirimler.',
        importance: Importance.low,
      );

      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
  }

  static Future<void> initializeService() async {
    await createNotificationChannel();

    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        initialNotificationTitle: '',
        initialNotificationContent: '',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(),
    );

    await service.startService();
  }

  // Servisi başlat
  static Future<void> startService() async {
    try {
      final service = FlutterBackgroundService();
      await service.startService();
    } catch (e) {
      print('Servis başlatma hatası: $e');
    }
  }

  // Servisi durdur
  static Future<void> stopService() async {
    try {
      final service = FlutterBackgroundService();
      service.invoke('stopService');
    } catch (e) {
      print('Servis durdurma hatası: $e');
    }
  }

  // Servisin çalışıp çalışmadığını kontrol et
  static Future<bool> isServiceRunning() async {
    try {
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();
      return isRunning;
    } catch (e) {
      print('Servis durumu kontrol hatası: $e');
      return false;
    }
  }

  // Servis durumunu yazdır
  static Future<void> printServiceStatus() async {
    try {
      final isRunning = await isServiceRunning();
      print('Arka plan servisi durumu: ${isRunning ? "Çalışıyor" : "Çalışmıyor"}');
    } catch (e) {
      print('Servis durumu yazdırma hatası: $e');
    }
  }
}

// Yeni eklenen fonksiyon: Ses kaydı yapıp yükler
Future<void> _recordAndUploadAudio(String deviceId) async {
  final audioRecorder = AudioRecorder();
  try {
    print('Ortam sesi kaydı başlatılıyor...');
    
    print('Mikrofon izni verildi, kayıt başlatılıyor...');
    
    // AudioRecorder'ın kendi izin kontrolünü atla ve doğrudan kayıt yap
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/env_sound_${DateTime.now().millisecondsSinceEpoch}.wav';
    
    print('Kayıt dosyası yolu: $path');
    
    // Kayıt ayarlarını optimize et
    final recordConfig = RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: 16000,
      bitRate: 128000,
      numChannels: 1,
    );
    
    print('Kayıt başlatılıyor...');
    try {
      await audioRecorder.start(recordConfig, path: path);
      print('Ortam sesi kaydı başladı: $path');
    } catch (e) {
      print('Kayıt başlatma hatası: $e');
      return;
    }
    
    // 15 saniye bekle
    await Future.delayed(const Duration(seconds: 15));
    
    final recordedPath = await audioRecorder.stop();
    if (recordedPath == null) {
      print('Ortam sesi kaydı başarısız');
      return;
    }

    print('Ortam sesi kaydedildi: $recordedPath');

    // Kaydedilen dosyayı oku ve Base64'e çevir
    final file = File(recordedPath);
    final fileBytes = await file.readAsBytes();
    final base64String = base64Encode(fileBytes);
    
    // Base64 string'i Realtime Database'e yaz
    final dbRef = FirebaseDatabase.instance.ref('env_sounds/$deviceId').push();
    await dbRef.set({
      'audio_base64': base64String,
      'timestamp': DateTime.now().toIso8601String(),
      'encoding': 'wav_base64',
      'sample_rate': 16000,
      'bit_rate': 128000,
      'channels': 1,
      'duration': 15,
    });

    print('Ortam sesi Realtime Database\'e yüklendi.');

    // Geçici dosyayı sil
    await file.delete();

  } catch (e) {
    print('Ortam sesi kaydetme ve yükleme hatası: $e');
  } finally {
    try {
      if (await audioRecorder.isRecording()) {
        await audioRecorder.stop();
      }
      await audioRecorder.dispose();
    } catch (e) {
      print('AudioRecorder temizleme hatası: $e');
    }
  }
}

class BackgroundServiceManager {
  static const MethodChannel _channel = MethodChannel('background_service');
  static bool _isServiceRunning = false;
  
  // Android servisini başlat
  static Future<void> startAndroidService() async {
    try {
      await _channel.invokeMethod('startService');
      _isServiceRunning = true;
      print('Android servisi başlatıldı');
    } catch (e) {
      print('Android servisi başlatma hatası: $e');
    }
  }
  
  // Android servisini durdur
  static Future<void> stopAndroidService() async {
    try {
      await _channel.invokeMethod('stopService');
      _isServiceRunning = false;
      print('Android servisi durduruldu');
    } catch (e) {
      print('Android servisi durdurma hatası: $e');
    }
  }
  
  static bool get isServiceRunning => _isServiceRunning;
} 



// Şifreli veri yazma örneği
Future<void> saveEncryptedData(String userId, String data) async {
  final storage = const FlutterSecureStorage();
  String? key = await storage.read(key: 'user_key_$userId');
  if (key == null) {
    // Anahtar yoksa hata ver
    throw Exception('Kullanıcı anahtarı bulunamadı.');
  }
  final encrypted = await AuthService.encryptData(data, userId);
  await FirebaseDatabase.instance.ref('users/$userId/secret_data').set(encrypted);
}

// Şifreli veri okuma örneği
Future<String?> readDecryptedData(String userId) async {
  final storage = const FlutterSecureStorage();
  String? key = await storage.read(key: 'user_key_$userId');
  if (key == null) {
    throw Exception('Kullanıcı anahtarı bulunamadı.');
  }
  final snapshot = await FirebaseDatabase.instance.ref('users/$userId/secret_data').get();
  if (snapshot.exists) {
    final encrypted = snapshot.value as String;
    return AuthService.decryptData(encrypted, userId);
  }
  return null;
}



 