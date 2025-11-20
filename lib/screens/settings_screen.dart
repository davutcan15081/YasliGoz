import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/background_service.dart';
import '../services/notification_service.dart';
import '../services/cache_service.dart';
import '../services/battery_optimization_service.dart';
import '../services/network_optimization_service.dart';
import '../services/permission_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yasligoz/screens/role_selection_screen.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import '../services/elderly_selection_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _backgroundServiceEnabled = false;
  bool _notificationsEnabled = true;
  bool _sosNotificationsEnabled = true;
  bool _locationNotificationsEnabled = true;
  bool _batteryNotificationsEnabled = true;
  bool _geofenceNotificationsEnabled = true;
  int _batteryWarningThreshold = 20;
  
  // Performans ayarları
  bool _batteryOptimizationEnabled = true;
  bool _cacheEnabled = true;
  bool _lowBandwidthMode = false;
  bool _lazyLoadingEnabled = true;
  
  // İstatistikler
  Map<String, dynamic> _batteryStats = {};
  Map<String, dynamic> _networkStats = {};

  int _locationUpdateIntervalMinutes = 5;

  // İzin durumları
  Map<Permission, PermissionStatus> _permissionStatuses = {};
  final PermissionService _permissionService = PermissionService();

  String? _alarmSoundPath;
  String? _alarmSoundName;
  bool _isRecordingAlarm = false;
  final AudioRecorder _alarmRecorder = AudioRecorder();

  @override
  void initState() {
    super.initState();
    _checkBackgroundServiceStatus();
    _loadNotificationSettings();
    _loadPerformanceSettings();
    _loadPerformanceStats();
    _loadLocationUpdateInterval();
    _loadPermissionStatuses();
    _loadAlarmSound();
  }

  Future<void> _checkBackgroundServiceStatus() async {
    // Arka plan servisi durumunu kontrol et
    // Not: flutter_background_service paketinin API'si farklı olabilir
    setState(() {
      _backgroundServiceEnabled = true; // Varsayılan olarak true
    });
  }

  Future<void> _loadNotificationSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _notificationsEnabled = prefs.getBool('notificationsEnabled') ?? true;
      _sosNotificationsEnabled = prefs.getBool('sosNotificationsEnabled') ?? true;
      _locationNotificationsEnabled = prefs.getBool('locationNotificationsEnabled') ?? true;
      _batteryNotificationsEnabled = prefs.getBool('batteryNotificationsEnabled') ?? true;
      _geofenceNotificationsEnabled = prefs.getBool('geofenceNotificationsEnabled') ?? true;
    });
  }

  Future<void> _saveNotificationSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notificationsEnabled', _notificationsEnabled);
    await prefs.setBool('sosNotificationsEnabled', _sosNotificationsEnabled);
    await prefs.setBool('locationNotificationsEnabled', _locationNotificationsEnabled);
    await prefs.setBool('batteryNotificationsEnabled', _batteryNotificationsEnabled);
    await prefs.setBool('geofenceNotificationsEnabled', _geofenceNotificationsEnabled);
  }

  Future<void> _loadPerformanceSettings() async {
    final cachedSettings = await Provider.of<CacheService>(context, listen: false).getCachedSettings();
    if (cachedSettings != null) {
      final settings = cachedSettings['settings'] as Map<String, dynamic>?;
      if (settings != null) {
        setState(() {
          _batteryOptimizationEnabled = settings['batteryOptimization'] ?? true;
          _cacheEnabled = settings['cacheEnabled'] ?? true;
          _lowBandwidthMode = settings['lowBandwidthMode'] ?? false;
          _lazyLoadingEnabled = settings['lazyLoadingEnabled'] ?? true;
        });
      }
    }
  }

  Future<void> _loadPerformanceStats() async {
    final networkService = Provider.of<NetworkOptimizationService>(context, listen: false);

    setState(() {
      _batteryStats = networkService.getNetworkStats();
      _networkStats = networkService.getNetworkStats();
    });
  }

  Future<void> _loadLocationUpdateInterval() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _locationUpdateIntervalMinutes = prefs.getInt('location_update_interval_minutes') ?? 5;
    });
  }

  Future<void> _saveLocationUpdateInterval(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('location_update_interval_minutes', value);
    // Ayar değiştiğinde arka plan servisini yeniden başlat
    await BackgroundService.stopService();
    await BackgroundService.startService();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konum güncelleme sıklığı değişti, arka plan servisi yeniden başlatıldı.')),
      );
    }
  }

  Future<void> _toggleBackgroundService(bool value) async {
    try {
      if (value) {
        await BackgroundService.startService();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Arka plan servisi başlatıldı')),
          );
        }
      } else {
        await BackgroundService.stopService();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Arka plan servisi durduruldu')),
          );
        }
      }
      setState(() {
        _backgroundServiceEnabled = value;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    }
  }

  Future<void> _toggleNotifications(bool value) async {
    try {
      final notificationService = Provider.of<NotificationService>(context, listen: false);
      if (value) {
        // Bildirim izinlerini iste
        NotificationSettings settings = await FirebaseMessaging.instance.requestPermission(
          alert: true,
          announcement: false,
          badge: true,
          carPlay: false,
          criticalAlert: true,
          provisional: false,
          sound: true,
        );
        if (settings.authorizationStatus == AuthorizationStatus.authorized) {
          // FCM topic'e abone ol
          await notificationService.subscribeToTopic('all_users');
          setState(() {
            _notificationsEnabled = true;
          });
          _saveNotificationSettings();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Bildirimler açıldı ve FCM topic abonesi olundu.')),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Bildirim izni reddedildi')),
            );
          }
        }
      } else {
        // FCM topic'ten çık
        await notificationService.unsubscribeFromTopic('all_users');
        setState(() {
          _notificationsEnabled = false;
        });
        _saveNotificationSettings();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bildirimler kapatıldı ve FCM topic aboneliği iptal edildi.')),
          );
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Uyarı: Bildirim izinleri sistemden programatik olarak kapatılamaz. Lütfen cihaz ayarlarından kapatınız.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bildirim ayarı değiştirilirken hata: $e')),
        );
      }
    }
  }

  Future<void> _toggleBatteryOptimization(bool value) async {
    try {
      final batteryService = Provider.of<BatteryOptimizationService>(context, listen: false);
      await batteryService.setOptimizationEnabled(value);
      setState(() {
        _batteryOptimizationEnabled = value;
      });
      // Ayar değiştiğinde arka plan servisini yeniden başlat
      await BackgroundService.stopService();
      await BackgroundService.startService();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Batarya optimizasyonu ${value ? 'açıldı' : 'kapatıldı'} ve arka plan servisi yeniden başlatıldı.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Batarya optimizasyonu ayarlanırken hata: $e')),
        );
      }
    }
  }

  Future<void> _toggleCache(bool value) async {
    try {
      final cacheService = Provider.of<CacheService>(context, listen: false);
      if (!value) {
        await cacheService.clearCache();
      }
      setState(() {
        _cacheEnabled = value;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Önbellek ${value ? 'açıldı (veriler cache üzerinden alınacak)' : 'kapatıldı ve tüm cache temizlendi, yeni veriler doğrudan backendden alınacak'}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Önbellek ayarlanırken hata: $e')),
        );
      }
    }
  }

  Future<void> _toggleLowBandwidthMode(bool value) async {
    try {
      final networkService = Provider.of<NetworkOptimizationService>(context, listen: false);
      networkService.setNetworkStatus(true, isLowBandwidth: value);
      setState(() {
        _lowBandwidthMode = value;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Düşük bant genişliği modu ${value ? 'açıldı (veriler sıkıştırılarak gönderilecek, medya kalitesi düşürülecek)' : 'kapatıldı (veriler tam kalite ile gönderilecek)'}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bant genişliği modu ayarlanırken hata: $e')),
        );
      }
    }
  }

  Future<void> _toggleLazyLoading(bool value) async {
    try {
      setState(() {
        _lazyLoadingEnabled = value;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lazy loading ${value ? 'açıldı (veriler ihtiyaç anında yüklenecek)' : 'kapatıldı (tüm veriler baştan yüklenecek)'}')),
        );
      }
      // Lazy loading aktifse, veri yükleme fonksiyonlarında getLazyLoadedData kullanılmalı
      // (Ekranlarda ilgili fonksiyonlar güncellenmeli)
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lazy loading ayarlanırken hata: $e')),
        );
      }
    }
  }

  Future<void> _clearAllNotifications() async {
    try {
      final notificationService = Provider.of<NotificationService>(context, listen: false);
      await notificationService.clearAllNotifications();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tüm bildirimler temizlendi')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bildirimler temizlenirken hata: $e')),
        );
      }
    }
  }

  Future<void> _optimizePerformance() async {
    try {
      final networkService = Provider.of<NetworkOptimizationService>(context, listen: false);
      
      await networkService.optimizePerformance();
      
      // İstatistikleri yenile
      await _loadPerformanceStats();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Performans optimizasyonu tamamlandı')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Performans optimizasyonu sırasında hata: $e')),
        );
      }
    }
  }

  Future<void> _signOut() async {
    try {
      // Arka plan servisini durdur
      await BackgroundService.stopService();
      
      // Kullanıcıdan çıkış yap
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.signOut();
      
      if (mounted) {
        // Tüm ekranları temizle ve rol seçim ekranına git
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
          (Route<dynamic> route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Çıkış yapılırken hata: $e')),
        );
      }
    }
  }

  Future<void> _loadPermissionStatuses() async {
    final statuses = await _permissionService.checkPermissionStatuses();
    setState(() {
      _permissionStatuses = statuses;
    });
  }

  Future<void> _refreshAllPermissions() async {
    try {
      // Kullanıcıya bilgi ver
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('İzinler yenileniyor...'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 2),
          ),
        );
      }
      
      // Mevcut izin durumlarını kontrol et
      final currentStatuses = await _permissionService.checkPermissionStatuses();
      print('[İZİN YENİLEME] Mevcut durumlar: $currentStatuses');
      
      // Reddedilmiş izinleri tekrar iste
      final permissionsToRequest = <Permission>[];
      
      currentStatuses.forEach((permission, status) {
        if (!status.isGranted) {
          permissionsToRequest.add(permission);
          print('[İZİN YENİLEME] İzin tekrar istenecek: $permission (Durum: $status)');
        }
      });
      
      if (permissionsToRequest.isEmpty) {
        print('[İZİN YENİLEME] Tüm izinler zaten verilmiş');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tüm izinler zaten verilmiş!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }
      
      print('[İZİN YENİLEME] ${permissionsToRequest.length} izin tekrar istenecek');
      
      // Tüm izinleri tekrar iste
      await _permissionService.checkAndRequestPermissions(
        forceRequest: true,
        context: context,
      );
      
      // İzin durumlarını yenile
      await _loadPermissionStatuses();
      
      // Son durumları kontrol et
      final finalStatuses = await _permissionService.checkPermissionStatuses();
      print('[İZİN YENİLEME] Son durumlar: $finalStatuses');
      
      // Başarı mesajı göster
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('İzinler başarıyla yenilendi!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('[İZİN YENİLEME] Hata: $e');
      // Hata durumunda kullanıcıya bilgi ver
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('İzin yenileme hatası: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _showDeleteAccountDialog() async {
    String password = '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hesabınızı Silmek Üzeresiniz'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Bu işlem geri alınamaz. Hesabınız ve tüm verileriniz kalıcı olarak silinecek. Devam etmek istiyor musunuz?'),
            const SizedBox(height: 16),
            TextField(
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Şifrenizi tekrar girin',
                border: OutlineInputBorder(),
              ),
              onChanged: (val) => password = val,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Evet, Sil'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _deleteAccountAndData(password);
    }
  }

  void _showKvkkDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('KVKK Aydınlatma Metni'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Kişisel Verilerin Korunması Kanunu (KVKK) Aydınlatma Metni',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 16),
              const Text(
                '1. Veri Sorumlusu:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Text('GPS Takip Uygulaması, kişisel verilerinizin veri sorumlusudur.'),
              const SizedBox(height: 8),
              const Text(
                '2. Toplanan Kişisel Veriler:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Text('• Ad, soyad, e-posta adresi\n• Konum verileri\n• Cihaz bilgileri\n• Kullanım istatistikleri'),
              const SizedBox(height: 8),
              const Text(
                '3. Kişisel Verilerin İşlenme Amaçları:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Text('• GPS takip hizmeti sunumu\n• Acil durum bildirimleri\n• Güvenli alan takibi\n• Uygulama performansının iyileştirilmesi'),
              const SizedBox(height: 8),
              const Text(
                '4. Kişisel Verilerin Aktarılması:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Text('Verileriniz, hizmet kalitesini artırmak amacıyla güvenli sunucularda saklanır ve üçüncü taraflarla paylaşılmaz.'),
              const SizedBox(height: 8),
              const Text(
                '5. Kişisel Veri Sahibinin Hakları:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Text('• Verilerinize erişim\n• Düzeltme talep etme\n• Silme talep etme\n• İşlemeyi sınırlama\n• Veri taşınabilirliği'),
              const SizedBox(height: 8),
              const Text(
                '6. İletişim:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Text('KVKK haklarınız için info.villagestudiotr@gmail.com adresinden bizimle iletişime geçebilirsiniz.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  void _showOpenConsentDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Açık Rıza Metni'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Açık Rıza Beyanı',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 16),
              const Text(
                'Bu uygulamayı kullanarak, aşağıdaki işlemler için açık rızanızı verdiğinizi kabul ediyorsunuz:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('• Konum verilerinizin toplanması ve işlenmesi'),
              const Text('• Acil durum durumunda yakınlarınıza bildirim gönderilmesi'),
              const Text('• Güvenli alan takibi için geofence teknolojisinin kullanılması'),
              const Text('• Uygulama performansını artırmak için anonim kullanım verilerinin toplanması'),
              const Text('• Push bildirimlerinin gönderilmesi'),
              const SizedBox(height: 8),
              const Text(
                'Bu rızanızı istediğiniz zaman geri çekebilirsiniz. Rızanızı geri çekmek için uygulama ayarlarından veya bizimle iletişime geçerek talebinizi iletebilirsiniz.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  void _showDataDeletionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hesap Silme Talebi'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hesabınızı ve tüm verilerinizi kalıcı olarak silmek üzeresiniz.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Text('Bu işlem sonucunda:'),
            Text('• Hesabınız tamamen silinecek'),
            Text('• Tüm konum verileriniz silinecek'),
            Text('• Aile üyeleriyle olan bağlantınız kesilecek'),
            Text('• Uygulama ayarlarınız sıfırlanacak'),
            Text('• E-posta adresiniz sistemden kaldırılacak'),
            SizedBox(height: 8),
            Text(
              'Bu işlem geri alınamaz. Devam etmek istiyor musunuz?',
              style: TextStyle(fontStyle: FontStyle.italic, color: Colors.red),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _requestDataDeletion();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Hesabımı Sil'),
          ),
        ],
      ),
    );
  }

  Future<void> _requestDataDeletion() async {
    try {
      final user = Provider.of<AuthService>(context, listen: false).currentUser;
      if (user == null) return;
      
      // Kullanıcıya bilgi ver
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hesap silme işlemi başlatılıyor...'),
            backgroundColor: Colors.blue,
          ),
        );
      }
      
      final dbRef = Provider.of<AuthService>(context, listen: false).database;
      final uid = user.uid;
      
      // Tüm kullanıcı verilerini sil
      await _deleteAllUserData(dbRef, uid);
      
      // Firebase Authentication'dan kullanıcı hesabını sil
      await user.delete();
      
      // Kullanıcıya bilgi ver
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hesabınız ve tüm verileriniz başarıyla silindi.'),
            backgroundColor: Colors.green,
          ),
        );
      }
      
      // Çıkış yap
      await Provider.of<AuthService>(context, listen: false).signOut();
      
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hesap silme işlemi sırasında hata: $e')),
        );
      }
    }
  }

  Future<void> _deleteAllUserData(DatabaseReference dbRef, String uid) async {
    try {
      // 1. Kullanıcı profil bilgilerini sil
      await dbRef.child('users/$uid').remove();
      
      // 2. Konum verilerini sil
      await dbRef.child('locations/$uid').remove();
      
      // 3. Acil durum bildirimlerini sil
      await dbRef.child('sos_alerts/$uid').remove();
      
      // 4. Geofence verilerini sil
      await dbRef.child('geofences/$uid').remove();
      
      // 5. Aile üyeleri bağlantılarını sil
      await dbRef.child('family_members/$uid').remove();
      
      // 6. Cihaz bilgilerini sil
      await dbRef.child('devices/$uid').remove();
      
      // 7. Bildirim geçmişini sil
      await dbRef.child('notifications/$uid').remove();
      
      // 8. Kullanım istatistiklerini sil
      await dbRef.child('usage_stats/$uid').remove();
      
      // 9. Ayarlar verilerini sil
      await dbRef.child('user_settings/$uid').remove();
      
      // 10. Şifreleme anahtarlarını temizle
      final storage = const FlutterSecureStorage();
      await storage.delete(key: 'user_key_$uid');
      
      print('🗑️ [VERİ SİLME] Kullanıcı $uid için tüm veriler silindi');
    } catch (e) {
      print('🗑️ [VERİ SİLME] Veri silme hatası: $e');
      rethrow;
    }
  }



  Future<void> _deleteAccountAndData(String password) async {
    try {
      final user = Provider.of<AuthService>(context, listen: false).currentUser;
      if (user == null) return;
      final uid = user.uid;
      // Re-authenticate
      final cred = EmailAuthProvider.credential(email: user.email!, password: password);
      await user.reauthenticateWithCredential(cred);
      // Firebase Realtime Database veya Firestore'dan kullanıcıya ait tüm verileri sil
      final dbRef = Provider.of<AuthService>(context, listen: false).database;
      await dbRef.child('users/$uid').remove();
      // Firebase Authentication'dan kullanıcıyı sil
      await user.delete();
      // Çıkış yap ve giriş ekranına yönlendir
      await Provider.of<AuthService>(context, listen: false).signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hesap silinirken hata oluştu: $e')),
        );
      }
    }
  }

  Future<void> _loadAlarmSound() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _alarmSoundPath = prefs.getString('alarm_sound_path');
      _alarmSoundName = prefs.getString('alarm_sound_name');
    });
  }

  Future<String?> _getDeviceId() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      String? deviceId;
      if (Platform.isAndroid) {
        deviceId = (await deviceInfo.androidInfo).id;
      } else if (Platform.isIOS) {
        deviceId = (await deviceInfo.iosInfo).identifierForVendor;
      } else if (Platform.isWindows) {
        deviceId = (await deviceInfo.windowsInfo).deviceId;
      } else if (Platform.isLinux) {
        deviceId = (await deviceInfo.linuxInfo).machineId;
      } else if (Platform.isMacOS) {
        deviceId = (await deviceInfo.macOsInfo).systemGUID;
      }
      return deviceId?.replaceAll(RegExp(r'[.#$\[\]]'), '_');
    } catch (e) {
      return null;
    }
  }

  Future<void> _uploadAlarmSoundToFirebase(String filePath, String elderlyDeviceId) async {
    try {
      final deviceId = elderlyDeviceId;
      if (deviceId.isEmpty) return;
      final file = File(filePath);
      if (!await file.exists()) return;
      final fileBytes = await file.readAsBytes();
      final base64String = base64Encode(fileBytes);
      final dbRef = FirebaseDatabase.instance.ref('alarm_sounds/$deviceId');
      await dbRef.set({
        'audio_base64': base64String,
        'timestamp': DateTime.now().toIso8601String(),
        'file_name': filePath.split('/').last,
      });
      print('Alarm sesi Firebase\'e yüklendi: $deviceId');
    } catch (e) {
      print('Alarm sesi Firebase\'e yüklenemedi: $e');
    }
  }

  Future<void> _pickAlarmSound() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final name = result.files.single.name;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('alarm_sound_path', path);
      await prefs.setString('alarm_sound_name', name);
      setState(() {
        _alarmSoundPath = path;
        _alarmSoundName = name;
      });
      // Seçili yaşlının deviceId'sini al
      final elderlyService = Provider.of<ElderlySelectionService>(context, listen: false);
      final elderlyDeviceId = elderlyService.selectedElderly?.deviceId?.replaceAll(RegExp(r'[.#$\[\]]'), '_') ?? '';
      if (elderlyDeviceId.isNotEmpty) {
        await _uploadAlarmSoundToFirebase(path, elderlyDeviceId);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Alarm sesi seçildi: $name')),
        );
      }
    }
  }

  Future<void> _startAlarmRecording() async {
    if (!await _alarmRecorder.hasPermission()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mikrofon izni gerekli!')),
      );
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/alarm_custom_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _alarmRecorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    setState(() {
      _isRecordingAlarm = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Alarm sesi kaydı başladı...')),
    );
  }

  Future<void> _stopAlarmRecording() async {
    final path = await _alarmRecorder.stop();
    if (path == null) {
      setState(() { _isRecordingAlarm = false; });
      return;
    }
    final name = path.split('/').last;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('alarm_sound_path', path);
    await prefs.setString('alarm_sound_name', name);
    setState(() {
      _isRecordingAlarm = false;
      _alarmSoundPath = path;
      _alarmSoundName = name;
    });
    // Seçili yaşlının deviceId'sini al
    final elderlyService = Provider.of<ElderlySelectionService>(context, listen: false);
    final elderlyDeviceId = elderlyService.selectedElderly?.deviceId?.replaceAll(RegExp(r'[.#$\[\]]'), '_') ?? '';
    if (elderlyDeviceId.isNotEmpty) {
      await _uploadAlarmSoundToFirebase(path, elderlyDeviceId);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Alarm sesi kaydedildi: $name')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ayarlar'),
        backgroundColor: const Color(0xFF4A90E2),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.settings, size: 64, color: Color(0xFF4A90E2)),
            const SizedBox(height: 16),
            const Text(
              'Uygulama Ayarları',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            
            // Performans Ayarları Bölümü
            const Text(
              'Performans Ayarları',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            // Batarya Optimizasyonu
            Card(
              elevation: 4,
              child: SwitchListTile(
                value: _batteryOptimizationEnabled,
                onChanged: _toggleBatteryOptimization,
                title: const Text('Batarya Optimizasyonu', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                subtitle: const Text('Otomatik performans ayarlama'),
                secondary: const Icon(Icons.battery_saver, color: Colors.green),
              ),
            ),
            const SizedBox(height: 8),
            
            // Önbellek Yönetimi
            Card(
              elevation: 4,
              child: SwitchListTile(
                value: _cacheEnabled,
                onChanged: _toggleCache,
                title: const Text('Önbellek Yönetimi', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                subtitle: const Text('Veri önbellekleme ve hızlı erişim'),
                secondary: const Icon(Icons.storage, color: Colors.blue),
              ),
            ),
            const SizedBox(height: 8),
            
            // Düşük Bant Genişliği Modu
            Card(
              elevation: 4,
              child: SwitchListTile(
                value: _lowBandwidthMode,
                onChanged: _toggleLowBandwidthMode,
                title: const Text('Düşük Bant Genişliği', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                subtitle: const Text('Veri kullanımını azalt'),
                secondary: const Icon(Icons.signal_wifi_off, color: Colors.orange),
              ),
            ),
            const SizedBox(height: 8),
            
            // Lazy Loading
            Card(
              elevation: 4,
              child: SwitchListTile(
                value: _lazyLoadingEnabled,
                onChanged: _toggleLazyLoading,
                title: const Text('Lazy Loading', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                subtitle: const Text('Veri gerektiğinde yükle'),
                secondary: const Icon(Icons.download, color: Colors.purple),
              ),
            ),
            const SizedBox(height: 16),
            
            // Performans İstatistikleri
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Performans İstatistikleri',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 16),
                    _buildStatRow('Başlatma Süresi', '${_networkStats['startupTime'] ?? 0}ms'),
                    _buildStatRow('Önbellek Hit Oranı', '%${_networkStats['cacheHitRate']?.toStringAsFixed(1) ?? '0'}'),
                    _buildStatRow('Toplu İşlem Verimi', '%${_networkStats['batchEfficiency']?.toStringAsFixed(1) ?? '0'}'),
                    _buildStatRow('Batarya Seviyesi', '%${_batteryStats['currentBatteryLevel'] ?? 0}'),
                    _buildStatRow('Toplam İstek', '${_networkStats['totalRequests'] ?? 0}'),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _optimizePerformance,
                      icon: const Icon(Icons.speed),
                      label: const Text('Performansı Optimize Et'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // Bildirim Ayarları Bölümü
            const Text(
              'Bildirim Ayarları',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            // Genel Bildirimler
            Card(
              elevation: 4,
              child: SwitchListTile(
                value: _notificationsEnabled,
                onChanged: _toggleNotifications,
                title: const Text('Genel Bildirimler', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                subtitle: const Text('Tüm bildirimleri aç/kapat'),
                secondary: const Icon(Icons.notifications, color: Color(0xFF4A90E2)),
              ),
            ),
            const SizedBox(height: 8),
            
            // SOS Bildirimleri
            Card(
              elevation: 4,
              child: SwitchListTile(
                value: _sosNotificationsEnabled && _notificationsEnabled,
                onChanged: _notificationsEnabled ? (value) {
                  setState(() {
                    _sosNotificationsEnabled = value;
                  });
                  _saveNotificationSettings();
                } : null,
                title: const Text('SOS Bildirimleri', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                subtitle: const Text('Acil durum uyarıları'),
                secondary: const Icon(Icons.emergency, color: Colors.red),
              ),
            ),
            const SizedBox(height: 8),
            
            // Konum Bildirimleri
            Card(
              elevation: 4,
              child: SwitchListTile(
                value: _locationNotificationsEnabled && _notificationsEnabled,
                onChanged: _notificationsEnabled ? (value) {
                  setState(() {
                    _locationNotificationsEnabled = value;
                  });
                  _saveNotificationSettings();
                } : null,
                title: const Text('Konum Bildirimleri', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                subtitle: const Text('Konum güncellemeleri'),
                secondary: const Icon(Icons.location_on, color: Colors.green),
              ),
            ),
            const SizedBox(height: 8),
            
            // Geofence Bildirimleri
            Card(
              elevation: 4,
              child: SwitchListTile(
                value: _geofenceNotificationsEnabled && _notificationsEnabled,
                onChanged: _notificationsEnabled ? (value) {
                  setState(() {
                    _geofenceNotificationsEnabled = value;
                  });
                  _saveNotificationSettings();
                } : null,
                title: const Text('Güvenli Alan Bildirimleri', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                subtitle: const Text('Güvenli alan giriş/çıkış'),
                secondary: const Icon(Icons.home, color: Colors.orange),
              ),
            ),
            const SizedBox(height: 8),
            
            // Batarya Bildirimleri
            Card(
              elevation: 4,
              child: SwitchListTile(
                value: _batteryNotificationsEnabled && _notificationsEnabled,
                onChanged: _notificationsEnabled ? (value) {
                  setState(() {
                    _batteryNotificationsEnabled = value;
                  });
                  _saveNotificationSettings();
                } : null,
                title: const Text('Batarya Uyarıları', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                subtitle: const Text('Düşük batarya uyarıları'),
                secondary: const Icon(Icons.battery_alert, color: Colors.orange),
              ),
            ),
            const SizedBox(height: 16),
            
            // Batarya Uyarı Eşiği
            if (_batteryNotificationsEnabled && _notificationsEnabled) ...[
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.battery_alert, color: Colors.orange),
                          const SizedBox(width: 8),
                          const Text('Batarya Uyarı Eşiği', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Slider(
                        value: _batteryWarningThreshold.toDouble(),
                        min: 5,
                        max: 50,
                        divisions: 9,
                        label: '%$_batteryWarningThreshold',
                        onChanged: (value) {
                          setState(() {
                            _batteryWarningThreshold = value.round();
                          });
                        },
                      ),
                      Text('Uyarı: %$_batteryWarningThreshold ve altında'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            
            // Konum Güncelleme Sıklığı
            Card(
              elevation: 4,
              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Konum Güncelleme Sıklığı', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Slider(
                            min: 1,
                            max: 30,
                            divisions: 29,
                            value: _locationUpdateIntervalMinutes.toDouble(),
                            label: '$_locationUpdateIntervalMinutes dk',
                            onChanged: (val) async {
                              setState(() {
                                _locationUpdateIntervalMinutes = val.round();
                              });
                              await _saveLocationUpdateInterval(_locationUpdateIntervalMinutes);
                            },
                          ),
                        ),
                        SizedBox(width: 12),
                        Text('$_locationUpdateIntervalMinutes dk', style: TextStyle(fontSize: 16)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text('Cihazın konumu kaç dakikada bir güncellensin?', style: TextStyle(fontSize: 13, color: Colors.grey)),
                  ],
                ),
              ),
            ),
            
            // Bildirim Yönetimi
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Bildirim Yönetimi',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _clearAllNotifications,
                      icon: const Icon(Icons.clear_all),
                      label: const Text('Tümünü Temizle'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // İzin Yönetimi Bölümü
            const Text(
              'İzin Yönetimi',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            // Konum İzni
            Card(
              elevation: 4,
              child: ListTile(
                leading: Icon(
                  _permissionStatuses[Permission.location]?.isGranted == true 
                    ? Icons.location_on 
                    : Icons.location_off,
                  color: _permissionStatuses[Permission.location]?.isGranted == true 
                    ? Colors.green 
                    : Colors.red,
                ),
                title: const Text('Konum İzni', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                subtitle: Text(
                  _permissionStatuses[Permission.location] != null
                    ? _permissionService.getPermissionStatusString(_permissionStatuses[Permission.location]!)
                    : 'Kontrol ediliyor...',
                ),
                trailing: _permissionStatuses[Permission.location]?.isGranted != true
                  ? ElevatedButton(
                      onPressed: () async {
                        await _permissionService.checkAndRequestPermissions(
                          forceRequest: true,
                          context: context,
                        );
                        await _loadPermissionStatuses();
                      },
                      child: const Text('İzin Ver'),
                    )
                  : null,
              ),
            ),
            const SizedBox(height: 8),
            
            // Bildirim İzni
            Card(
              elevation: 4,
              child: ListTile(
                leading: Icon(
                  _permissionStatuses[Permission.notification]?.isGranted == true 
                    ? Icons.notifications_active 
                    : Icons.notifications_off,
                  color: _permissionStatuses[Permission.notification]?.isGranted == true 
                    ? Colors.green 
                    : Colors.red,
                ),
                title: const Text('Bildirim İzni', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                subtitle: Text(
                  _permissionStatuses[Permission.notification] != null
                    ? _permissionService.getPermissionStatusString(_permissionStatuses[Permission.notification]!)
                    : 'Kontrol ediliyor...',
                ),
                trailing: _permissionStatuses[Permission.notification]?.isGranted != true
                  ? ElevatedButton(
                      onPressed: () async {
                        await _permissionService.checkAndRequestPermissions(
                          forceRequest: true,
                          context: context,
                        );
                        await _loadPermissionStatuses();
                      },
                      child: const Text('İzin Ver'),
                    )
                  : null,
              ),
            ),
            const SizedBox(height: 8),
            
            // Mikrofon İzni
            Card(
              elevation: 4,
              child: ListTile(
                leading: Icon(
                  _permissionStatuses[Permission.microphone]?.isGranted == true 
                    ? Icons.mic 
                    : Icons.mic_off,
                  color: _permissionStatuses[Permission.microphone]?.isGranted == true 
                    ? Colors.green 
                    : Colors.red,
                ),
                title: const Text('Mikrofon İzni', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                subtitle: Text(
                  _permissionStatuses[Permission.microphone] != null
                    ? _permissionService.getPermissionStatusString(_permissionStatuses[Permission.microphone]!)
                    : 'Kontrol ediliyor...',
                ),
                trailing: _permissionStatuses[Permission.microphone]?.isGranted != true
                  ? ElevatedButton(
                      onPressed: () async {
                        await _permissionService.checkAndRequestPermissions(
                          forceRequest: true,
                          context: context,
                        );
                        await _loadPermissionStatuses();
                      },
                      child: const Text('İzin Ver'),
                    )
                  : null,
              ),
            ),
            const SizedBox(height: 16),
            
            // İzin Durumu Özeti
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'İzin Durumu Özeti',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _refreshAllPermissions,
                            icon: const Icon(Icons.refresh),
                            label: const Text('İzinleri Yenile'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              await openAppSettings();
                            },
                            icon: const Icon(Icons.settings),
                            label: const Text('Ayarlar'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // KVKK ve Gizlilik Bölümü
            const Text(
              'KVKK ve Gizlilik',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            // KVKK Aydınlatma Metni
            Card(
              elevation: 4,
              child: ListTile(
                leading: const Icon(Icons.privacy_tip, color: Color(0xFF4A90E2)),
                title: const Text('KVKK Aydınlatma Metni', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                subtitle: const Text('Kişisel verilerin korunması hakkında bilgi'),
                onTap: _showKvkkDialog,
                trailing: const Icon(Icons.arrow_forward_ios),
              ),
            ),
            const SizedBox(height: 8),
            
            // Açık Rıza Metni
            Card(
              elevation: 4,
              child: ListTile(
                leading: const Icon(Icons.verified_user, color: Color(0xFF4A90E2)),
                title: const Text('Açık Rıza Metni', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                subtitle: const Text('Veri işleme rızanız hakkında bilgi'),
                onTap: _showOpenConsentDialog,
                trailing: const Icon(Icons.arrow_forward_ios),
              ),
            ),
            const SizedBox(height: 8),
            
            // Hesap Silme Talebi
            Card(
              elevation: 4,
              child: ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text('Hesap Silme Talebi', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                subtitle: const Text('Hesabınızı ve tüm verilerinizi kalıcı olarak silin'),
                onTap: _showDataDeletionDialog,
                trailing: const Icon(Icons.arrow_forward_ios),
              ),
            ),
            const SizedBox(height: 8),
            
            // Alarm Sesi Seç
            Card(
              elevation: 4,
              child: ListTile(
                leading: const Icon(Icons.music_note, color: Colors.red),
                title: const Text('Alarm Sesi Seç', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                subtitle: Text(_alarmSoundName != null ? 'Seçili: $_alarmSoundName' : 'Varsayılan alarm.mp3 kullanılacak'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      onPressed: _pickAlarmSound,
                      child: const Text('Seç'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.remove('alarm_sound_path');
                        await prefs.remove('alarm_sound_name');
                        setState(() {
                          _alarmSoundPath = null;
                          _alarmSoundName = null;
                        });
                        // Firebase'deki alarm_sounds/{deviceId} yolunu sil
                        final elderlyService = Provider.of<ElderlySelectionService>(context, listen: false);
                        final elderlyDeviceId = elderlyService.selectedElderly?.deviceId?.replaceAll(RegExp(r'[.#$\[\]]'), '_') ?? '';
                        if (elderlyDeviceId.isNotEmpty) {
                          await FirebaseDatabase.instance.ref('alarm_sounds/$elderlyDeviceId').remove();
                        }
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Varsayılan alarm.mp3 seçildi')),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                      child: const Text('Varsayılan'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Alarm Sesi Kaydet
            Card(
              elevation: 4,
              child: ListTile(
                leading: Icon(_isRecordingAlarm ? Icons.mic : Icons.mic_none, color: Colors.orange),
                title: const Text('Alarm Sesi Kaydet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                subtitle: Text(_isRecordingAlarm ? 'Kayıt yapılıyor...' : (_alarmSoundName != null ? 'Seçili: $_alarmSoundName' : 'Varsayılan alarm.mp3 kullanılacak')),
                trailing: _isRecordingAlarm
                    ? ElevatedButton(
                        onPressed: _stopAlarmRecording,
                        child: const Text('Durdur'),
                      )
                    : ElevatedButton(
                        onPressed: _startAlarmRecording,
                        child: const Text('Kaydet'),
                      ),
              ),
            ),
            const SizedBox(height: 24),
            
            // Sistem Ayarları Bölümü
            const Text(
              'Sistem Ayarları',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            // Arka Plan Servisi
            Card(
              elevation: 4,
              child: SwitchListTile(
                value: _backgroundServiceEnabled,
                onChanged: _toggleBackgroundService,
                title: const Text('Arka Plan Servisi', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                subtitle: const Text('Uygulama kapalıyken konum takibi'),
                secondary: const Icon(Icons.location_on, color: Color(0xFF4A90E2)),
              ),
            ),
            const SizedBox(height: 32),
            
            // Çıkış Yap Butonu
            ElevatedButton.icon(
              onPressed: _signOut,
              icon: const Icon(Icons.logout),
              label: const Text('Çıkış Yap', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Bilgi Kartı
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Performans Optimizasyonu Hakkında',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
            const Text(
                      '• Batarya optimizasyonu otomatik performans ayarları\n'
                      '• Önbellek sistemi hızlı veri erişimi sağlar\n'
                      '• Düşük bant genişliği modu veri kullanımını azaltır\n'
                      '• Lazy loading gereksiz veri yüklemeyi önler',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // 'Tüm Bildirimleri Test Et' butonunu kaldır
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
} 