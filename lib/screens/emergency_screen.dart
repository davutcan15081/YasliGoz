import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/notification_service.dart';
import '../services/auth_service.dart';
import '../services/permission_service.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'add_emergency_contact_screen.dart';
import 'package:yasligoz/screens/role_selection_screen.dart';
import 'package:yasligoz/services/background_service.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'package:battery_plus/battery_plus.dart';
import 'dart:async';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yasligoz/services/alarm_audio_player.dart';

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  bool _isSendingSOS = false;
  List<Map<String, dynamic>> _emergencyContacts = [];
  String _pairingInfo = 'Eşleştirme Kodu alınıyor...';
  bool _isRecordingVoice = false;
  final List<Map<String, dynamic>> _voiceMessages = [];
  final AudioRecorder _voiceRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _recordedVoicePath;
  Timer? _batteryUpdateTimer;
  Timer? _locationStatusTimer;
  bool _familyConnected = false;
  StreamSubscription<DatabaseEvent>? _familyConnectedSubscription;
  Timer? _foregroundLocationTimer;
  bool _isAlarmActive = false;
  StreamSubscription<DatabaseEvent>? _alarmSubscription;
  Timer? alarmCheckTimer;

  @override
  void initState() {
    super.initState();
    _checkAndRequestPermissions();
    _loadEmergencyContacts();
    _generateAndStorePairingCode();
    _listenToVoiceMessages();
    _checkDeviceConnectionStatus();
    _startBatteryTracking();
    _startLocationStatusTracking();
    _listenFamilyConnected();
    _startForegroundLocationUpdates();
    _listenToAlarmStatus();
    startAlarmCheck();
  }

  @override
  void dispose() {
    _voiceRecorder.dispose();
    _audioPlayer.dispose();
    _batteryUpdateTimer?.cancel();
    _locationStatusTimer?.cancel();
    _familyConnectedSubscription?.cancel();
    _foregroundLocationTimer?.cancel();
    _alarmSubscription?.cancel();
    alarmCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _generateAndStorePairingCode() async {
    setState(() {
      _pairingInfo = 'Eşleştirme Kodu oluşturuluyor...';
    });
    try {
      // 1. Gerçek Cihaz ID'sini al
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

      if (deviceId == null) {
        throw Exception('Cihaz ID alınamadı');
      }

      // 2. Benzersiz, 6 haneli bir eşleştirme kodu üret
      final random = Random();
      const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      final pairingCode = String.fromCharCodes(Iterable.generate(
          6, (_) => chars.codeUnitAt(random.nextInt(chars.length))));

      // 3. Bu kodu ve gerçek Cihaz ID'sini Firebase'e kaydet
      final dbRef = FirebaseDatabase.instance.ref('pairing_codes/$pairingCode');
      await dbRef.set({
        'deviceId': deviceId,
        'createdAt': ServerValue.timestamp,
      });

      if (mounted) {
        setState(() {
          _pairingInfo = 'Eşleştirme Kodu: $pairingCode';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _pairingInfo = 'Hata: ${e.toString()}';
        });
      }
    }
  }

  Future<void> _checkAndRequestPermissions() async {
    final permissionService = PermissionService();
    
    // İzinleri kontrol et ve gerekirse iste
    await permissionService.checkAndRequestPermissions(
      context: context,
    );
    
    // Mikrofon iznini de iste
    final hasMicrophonePermission = await PermissionService.requestMicrophonePermission();
    if (!hasMicrophonePermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mikrofon izni gerekli. Ayarlardan izin verin.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _loadEmergencyContacts() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('❌ [ACİL KONTAKLAR] Kullanıcı girişi bulunamadı');
        return;
      }

      // Kullanıcı anahtarını al
      final storage = const FlutterSecureStorage();
      String? key = await storage.read(key: 'user_key_${user.uid}');
      if (key == null) {
        print('❌ [ACİL KONTAKLAR] Kullanıcı anahtarı bulunamadı');
        return;
      }
      
      final snapshot = await FirebaseDatabase.instance
          .ref('users/${user.uid}/emergency_contacts')
          .get();
      
      if (snapshot.exists) {
        final List<Map<String, dynamic>> contacts = [];
        for (var child in snapshot.children) {
          try {
            final data = child.value;
            if (data is String) {
              // Şifreli veriyi çöz
              final decryptedData = decryptData(data, key);
              final jsonData = jsonDecode(decryptedData);
              
              if (jsonData is Map) {
                final Map<String, dynamic> contactMap = {};
                jsonData.forEach((key, value) {
                  if (key != null) {
                    contactMap[key.toString()] = value;
                  }
                });
                contactMap['id'] = child.key;
                contacts.add(contactMap);
              }
            }
          } catch (e) {
            print('❌ [ACİL KONTAKLAR] Veri çözme hatası: $e');
            continue; // Bu veriyi atla, diğerlerini yüklemeye devam et
          }
      }
      
      if (mounted) {
        setState(() {
            _emergencyContacts = contacts;
        });
      }
      } else {
      if (mounted) {
        setState(() {
          _emergencyContacts = [];
        });
      }
      }
    } catch (e) {
      print('❌ [ACİL KONTAKLAR] Yükleme hatası: $e');
    }
  }

  // AES ile veri çözme
  String decryptData(String encryptedText, String base64Key) {
    try {
      final key = encrypt.Key.fromBase64(base64Key);
      
      // Yeni format kontrolü - IV:encrypted_data
      if (encryptedText.contains(':')) {
        final parts = encryptedText.split(':');
        if (parts.length == 2) {
          try {
            final ivBase64 = parts[0];
            final encryptedBase64 = parts[1];
            
            final iv = encrypt.IV.fromBase64(ivBase64);
            final encrypter = encrypt.Encrypter(encrypt.AES(key));
            final decrypted = encrypter.decrypt64(encryptedBase64, iv: iv);
            return decrypted;
          } catch (e) {
            print('Yeni format çözme hatası: $e');
            // Yeni format çözülemezse, veriyi olduğu gibi döndür
            return encryptedText;
          }
        }
      }
      
      // Eski format veya şifrelenmemiş veri
      // Eski veriler için çözme denemesi yapmıyoruz, sadece veriyi olduğu gibi döndürüyoruz
      print('Eski format veya şifrelenmemiş veri tespit edildi, olduğu gibi döndürülüyor');
      return encryptedText;
      
    } catch (e) {
      print('Çözme hatası: $e');
      // Hata durumunda veriyi olduğu gibi döndür
      return encryptedText;
    }
  }

  Future<void> _sendSOS() async {
    if (_isSendingSOS) return;

    // Aile bağlantısı kontrolü
    if (!_familyConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Aile cihazı ile bağlantı yok! SOS sinyali gönderilemez.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }

    setState(() { _isSendingSOS = true; });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Acil durum sinyali gönderiliyor, lütfen bekleyin...'),
        backgroundColor: Colors.orange,
      ),
    );

    try {
      final notificationService = Provider.of<NotificationService>(context, listen: false);
      
      // 1. Cihaz ID'sini al
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

      if (deviceId == null) {
        throw Exception('Cihaz ID alınamadı.');
      }
      final sanitizedDeviceId = deviceId.replaceAll(RegExp(r'[.#$\[\]]'), '_');

      // 3. Konumu al
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      } catch (e) {
        debugPrint("Konum alınamadı: $e");
      }

      // TEŞHİS İÇİN EKLENDİ: Hangi ID ile kayıt yapıldığını konsola yazdır.
      print('>>> [SOS GÖNDERİLİYOR] Bu Cihaz Kimliği ile kayıt yapılıyor: $sanitizedDeviceId');

      // 4. Firebase'e SOS kaydı ekle (Cihaz ID ile)
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseDatabase.instance
          .ref('sos_alerts/$sanitizedDeviceId/${DateTime.now().millisecondsSinceEpoch}')
          .set({
        'timestamp': ServerValue.timestamp,
        'user_id': user?.uid, // Bilgi amaçlı tutulabilir
        'user_email': user?.email, // Bilgi amaçlı tutulabilir
        'status': 'active',
        'location': position != null 
            ? {'latitude': position.latitude, 'longitude': position.longitude}
            : null,
      });

      // 5. Acil durum kontaklarına bildirim gönder (Backend'de yapılacak)
      await _notifyEmergencyContacts();
      
      // 6. Kullanıcıya bildirim göster
      await notificationService.showSOSSentNotification();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SOS sinyali gönderildi!'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('SOS gönderilirken hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSendingSOS = false;
        });
      }
    }
  }

  // Cihazın bağlı olup olmadığını kontrol et
  Future<bool> _checkDeviceConnection(String deviceId) async {
    try {
      // pairing_codes altında bu cihazın kaydı var mı ve family_connected true mu kontrol et
      final pairingCodesSnapshot = await FirebaseDatabase.instance.ref('pairing_codes').get();
      if (pairingCodesSnapshot.exists && pairingCodesSnapshot.value != null) {
        final pairingCodesData = pairingCodesSnapshot.value as Map;
        for (var entry in pairingCodesData.entries) {
          final codeData = entry.value as Map?;
          if (codeData != null && codeData['deviceId'] == deviceId) {
            // Ek kontrol: aile cihazı gerçekten bağlı mı?
            if (codeData['family_connected'] == true) {
              print('✅ [BAĞLANTI KONTROL] Cihaz gerçekten bağlı: ${entry.key}');
              return true;
            } else {
              print('❌ [BAĞLANTI KONTROL] Cihaz eşleşmiş ama aile cihazı bağlı değil: ${entry.key}');
              return false;
            }
          }
        }
      }
      print('❌ [BAĞLANTI KONTROL] Cihaz hiçbir aile cihazına bağlı değil');
      return false;
    } catch (e) {
      print('❌ [BAĞLANTI KONTROL] Bağlantı kontrolü hatası: $e');
      return false;
    }
  }

  // Cihaz bağlantı durumunu kontrol et ve UI'ı güncelle
  Future<void> _checkDeviceConnectionStatus() async {
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

      if (deviceId != null) {
        final sanitizedDeviceId = deviceId.replaceAll(RegExp(r'[.#$\[\]]'), '_');
        final isConnected = await _checkDeviceConnection(sanitizedDeviceId);
        
        if (mounted) {
          setState(() {
            _familyConnected = isConnected;
          });
        }
      }
    } catch (e) {
      print('❌ [BAĞLANTI DURUMU] Kontrol hatası: $e');
      if (mounted) {
        setState(() {
          _familyConnected = false;
        });
      }
    }
  }

  Future<void> _notifyEmergencyContacts() async {
    // Bu kısım normalde bir backend (Firebase Cloud Functions) üzerinden yapılmalıdır.
    // FCM token'lar alınıp bu token'lara bildirim gönderilir.
    // Şimdilik sadece bir print komutu ile simüle ediyoruz.
    for (var contact in _emergencyContacts) {
      debugPrint("${contact['name']} adlı kişiye bildirim gönderiliyor...");
    }
  }

  Future<void> _makePhoneCall(String? phoneNumber) async {
    if (phoneNumber == null || phoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geçerli bir telefon numarası bulunamadı.')),
      );
      return;
    }
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$phoneNumber aranamadı.')),
      );
    }
  }

  Future<void> _signOut() async {
    try {
      await BackgroundService.stopService();
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.signOut();
      
      if (mounted) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBE9E7), // Hafif kırmızı/pembe arka plan
      appBar: AppBar(
        title: const Text('ACİL DURUM', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.red.shade800,
        foregroundColor: Colors.white,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
            tooltip: 'Çıkış Yap',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_isAlarmActive) ...[
            ElevatedButton.icon(
              onPressed: _stopRemoteAlarm,
              icon: const Icon(Icons.notifications_off, color: Colors.white),
              label: const Text('Alarmı Durdur', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
          ],
          // Servis durumu kartı
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.info, color: Colors.blue, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Arka Plan Servisi',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Çalışıyor - Ortam sesi dinleniyor',
                        style: TextStyle(
                          color: Colors.blue,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: () => _showServiceStatus(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  child: const Text('Detaylar'),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Yardıma mı ihtiyacınız var?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: Color(0xFFC62828)),
            ),
            const SizedBox(height: 24),
            
            // SOS Butonu
            GestureDetector(
              onLongPress: _isSendingSOS ? null : _sendSOS,
              child: AspectRatio(
                aspectRatio: 1.0,
                child: Container(
                  decoration: BoxDecoration(
                    color: _isSendingSOS ? Colors.grey.shade600 : Colors.red.shade600,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 6),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.5),
                        blurRadius: 30,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isSendingSOS ? Icons.hourglass_top : Icons.sos,
                          size: 90,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isSendingSOS ? 'GÖNDERİLİYOR' : 'SOS',
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Yardım çağırmak için butona basılı tutun.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, color: Colors.black54, fontWeight: FontWeight.w500),
            ),
            
            const SizedBox(height: 40),
            const Divider(thickness: 1.5),
            const SizedBox(height: 24),

            // Sesli Mesaj Bölümü
            const Text(
              'Sesli Mesajlar',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1976D2)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            
            // Sesli mesaj gönderme butonu
            GestureDetector(
              onLongPressStart: (_) => _startVoiceRecording(),
              onLongPressEnd: (_) => _stopVoiceRecordingAndSend(),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _isRecordingVoice ? Colors.red.shade100 : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _isRecordingVoice ? Colors.red : Colors.blue.shade200,
                    width: 2,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isRecordingVoice ? Icons.mic : Icons.mic_none,
                      color: _isRecordingVoice ? Colors.red : Colors.blue,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _isRecordingVoice ? 'Kayıt Yapılıyor...' : 'Sesli Mesaj Gönder',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _isRecordingVoice ? Colors.red : Colors.blue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Aile cihazına sesli mesaj göndermek için basılı tutun',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.black54),
            ),
            
            const SizedBox(height: 24),
            
            // Gelen sesli mesajlar
            if (_voiceMessages.isNotEmpty) ...[
              const Text(
                'Gelen Sesli Mesajlar',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1976D2)),
              ),
              const SizedBox(height: 8),
              Container(
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListView.builder(
                  itemCount: _voiceMessages.length,
                  itemBuilder: (context, index) {
                    final message = _voiceMessages[index];
                    final formattedDate = message['timestamp'] != null && message['timestamp'].toString().isNotEmpty
                      ? message['timestamp'].toString().replaceAll('T', ' ').substring(0, 19)
                      : 'Tarih yok';
                    
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: ListTile(
                        leading: const Icon(Icons.mic, color: Colors.blue),
                        title: Text('Aile Cihazından - $formattedDate'),
                        subtitle: const Text('Sesli mesajı dinlemek için dokunun'),
                        onTap: () => _playVoiceMessage(message['audio_base64'] as String?),
                      ),
                    );
                  },
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: const Text(
                  'Henüz gelen sesli mesaj yok',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.black54),
                ),
              ),
            ],
            
            const SizedBox(height: 24),
            const Divider(thickness: 1.5),
            const SizedBox(height: 24),

            // Acil Durum Kontakları
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Acil Durum Kişileri',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFFC62828)),
                  textAlign: TextAlign.center,
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: Colors.green, size: 28),
                  onPressed: () => _navigateToAddContact(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            if (_emergencyContacts.isNotEmpty)
              ListView.separated(
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                itemCount: _emergencyContacts.length,
                itemBuilder: (context, index) {
                  final contact = _emergencyContacts[index];
                  return Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      leading: CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.red.shade100,
                        child: const Icon(Icons.person, size: 32, color: Colors.red),
                      ),
                      title: Text(
                        contact['name'] ?? 'İsimsiz', 
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)
                      ),
                      subtitle: Text(
                        contact['phone'] ?? 'Telefon numarası yok',
                        style: const TextStyle(fontSize: 16)
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ElevatedButton.icon(
                            icon: const Icon(Icons.call, color: Colors.white, size: 18),
                            label: const Text('ARA', style: TextStyle(color: Colors.white)),
                            onPressed: () => _makePhoneCall(contact['phone']),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade600,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'edit') {
                                _editContact(contact);
                              } else if (value == 'delete') {
                                _deleteContact(contact['id']);
                              }
                            },
                            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                              const PopupMenuItem<String>(
                                value: 'edit',
                                child: ListTile(
                                  leading: Icon(Icons.edit),
                                  title: Text('Düzenle'),
                                ),
                              ),
                              const PopupMenuItem<String>(
                                value: 'delete',
                                child: ListTile(
                                  leading: Icon(Icons.delete),
                                  title: Text('Sil'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
                separatorBuilder: (context, index) => const SizedBox(height: 12),
              )
            else
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Henüz acil durum kişisi eklenmemiş.\nEklemek için yukarıdaki (+) ikonuna dokunun.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.black54),
                  ),
                ),
              ),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            // Eşleştirme Kodu Bilgisi
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: SelectableText(
                _pairingInfo,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey),
              ),
            ),

            // Durum Kartı (Aile bağlantısı)
            Card(
              color: _familyConnected ? Colors.green.shade50 : Colors.red.shade50,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.only(top: 16),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(_familyConnected ? Icons.link : Icons.link_off,
                        color: _familyConnected ? Colors.green : Colors.red, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _familyConnected
                            ? 'Aile cihazına bağlı'
                            : 'Aile cihazı ile bağlantı yok! (Takip edilmiyorsunuz)',
                        style: TextStyle(
                          color: _familyConnected ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
          ),
        ],
      ),
    );
  }

  void _navigateToAddContact() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddEmergencyContactScreen()),
    );
    if (result == true && mounted) {
      _loadEmergencyContacts(); // Listeyi yenile
    }
  }

  void _editContact(Map<String, dynamic> contact) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => AddEmergencyContactScreen(contact: contact)),
    );
    if (result == true && mounted) {
      _loadEmergencyContacts(); // Listeyi yenile
    }
  }

  Future<void> _deleteContact(String contactId) async {
    final bool? confirmed = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kişiyi Sil'),
        content: const Text('Bu kişiyi acil durum kişilerinden silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('SİL'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) throw Exception('Kullanıcı bulunamadı.');

        await FirebaseDatabase.instance
            .ref('users/${user.uid}/emergency_contacts/$contactId')
            .remove();
        
        if(mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Kişi başarıyla silindi.'), backgroundColor: Colors.green),
          );
          _loadEmergencyContacts(); // Listeyi yenile
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Kişi silinirken hata oluştu: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  // Sesli mesajları dinle
  void _listenToVoiceMessages() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    // Yaşlı cihazının kendi deviceId'sini dinle (aile cihazından gelen mesajlar için)
    _getDeviceId().then((deviceId) {
      if (deviceId == null) return;
      
      final voiceRef = FirebaseDatabase.instance.ref('voice_messages/$deviceId');
      voiceRef.onChildAdded.listen((event) {
        final data = event.snapshot.value as Map?;
        if (data != null && data['audio_base64'] != null && data['from'] == 'family_member') {
          setState(() {
            if (!_voiceMessages.any((msg) => msg['key'] == event.snapshot.key)) {
              _voiceMessages.add({
                'key': event.snapshot.key!,
                'audio_base64': data['audio_base64'],
                'timestamp': data['timestamp'] ?? '',
                'from': data['from'] ?? 'family',
              });
              _voiceMessages.sort((a, b) => (b['timestamp'] as String).compareTo(a['timestamp'] as String));
            }
          });
        }
      });
    });
  }

  // Cihaz ID'sini al
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

  // Sesli mesaj kaydı başlat
  Future<void> _startVoiceRecording() async {
    try {
      if (!await _voiceRecorder.hasPermission()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mikrofon izni gerekli!')),
        );
        return;
      }
      
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice_message_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _voiceRecorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);

      setState(() {
        _isRecordingVoice = true;
        _recordedVoicePath = null;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sesli mesaj kaydı başladı...')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kayıt başlatılamadı!')),
      );
    }
  }

  // Sesli mesaj kaydı durdur ve gönder
  Future<void> _stopVoiceRecordingAndSend() async {
    try {
      final path = await _voiceRecorder.stop();
      if (path == null) {
        setState(() { _isRecordingVoice = false; });
        return;
      }

      setState(() {
        _isRecordingVoice = false;
        _recordedVoicePath = path;
      });

      final file = File(_recordedVoicePath!);
      final fileBytes = await file.readAsBytes();
      final base64String = base64Encode(fileBytes);

      // Aile cihazına gönder (family_member deviceId'sine)
      final voiceMessageRef = FirebaseDatabase.instance.ref('voice_messages/family_member').push();
      await voiceMessageRef.set({
        'audio_base64': base64String,
        'timestamp': DateTime.now().toIso8601String(),
        'from': 'elderly',
        'encoding': 'aacLc_base64'
      });

      await file.delete();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sesli mesaj başarıyla gönderildi!')),
      );

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mesaj gönderilemedi!')),
      );
    }
  }

  // Sesli mesaj oynat
  Future<void> _playVoiceMessage(String? base64String) async {
    if (base64String == null || base64String.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ses dosyası bulunamadı!')),
      );
      return;
    }
    try {
      final audioBytes = base64Decode(base64String);
      await _audioPlayer.play(BytesSource(audioBytes));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ses dosyası çalınamadı!')),
      );
    }
  }

  void _startBatteryTracking() {
    // İlk batarya seviyesini al
    _updateBatteryLevel();
    
    // Her 5 dakikada bir batarya seviyesini güncelle
    _batteryUpdateTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      _updateBatteryLevel();
    });
  }

  Future<void> _updateBatteryLevel() async {
    try {
      final battery = Battery();
      final level = await battery.batteryLevel;
      
      // Firebase'e batarya bilgisini kaydet
      await _saveBatteryToFirebase(level);
      
    } catch (e) {
      print('Batarya seviyesi alınırken hata: $e');
    }
  }

  Future<void> _saveBatteryToFirebase(int batteryLevel) async {
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

      if (deviceId != null) {
        final sanitizedDeviceId = deviceId.replaceAll(RegExp(r'[.#$\[\]]'), '_');
        final dbRef = FirebaseDatabase.instance.ref('battery_levels/$sanitizedDeviceId');
        await dbRef.set({
          'level': batteryLevel,
          'timestamp': DateTime.now().toIso8601String(),
          'deviceId': deviceId,
        });
      }
    } catch (e) {
      print('Batarya bilgisi Firebase\'e kaydedilirken hata: $e');
    }
  }

  void _startLocationStatusTracking() {
    _updateLocationStatusToFirebase();
    _locationStatusTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _updateLocationStatusToFirebase();
    });
  }

  Future<void> _updateLocationStatusToFirebase() async {
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
      if (deviceId == null) return;
      final sanitizedDeviceId = deviceId.replaceAll(RegExp(r'[.#$\[\]]'), '_');
      final enabled = await Geolocator.isLocationServiceEnabled();
      await FirebaseDatabase.instance.ref('location_status/$sanitizedDeviceId').set({
        'enabled': enabled,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Konum servisi durumu Firebase\'e yazılamadı: $e');
    }
  }

  Future<void> _listenFamilyConnected() async {
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
      if (deviceId == null) return;
      final pairingCodesRef = FirebaseDatabase.instance.ref('pairing_codes');
      final snapshot = await pairingCodesRef.get();
      if (snapshot.exists && snapshot.value != null) {
        final data = snapshot.value as Map;
        for (var entry in data.entries) {
          final codeData = entry.value as Map?;
          if (codeData != null && codeData['deviceId'] == deviceId) {
            final pairingCode = entry.key;
            final familyConnectedRef = FirebaseDatabase.instance.ref('pairing_codes/$pairingCode/family_connected');
            _familyConnectedSubscription = familyConnectedRef.onValue.listen((event) {
              final value = event.snapshot.value;
              setState(() {
                _familyConnected = value == true;
              });
            });
            break;
          }
        }
      }
    } catch (e) {
      print('Aile bağlantısı dinlenirken hata: $e');
    }
  }

  void _startForegroundLocationUpdates() {
    _foregroundLocationTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _sendCurrentLocationToFirebase();
    });
  }

  Future<void> _sendCurrentLocationToFirebase() async {
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
      if (deviceId == null) return;
      final safeDeviceId = deviceId.replaceAll(RegExp(r'[.#$\[\]]'), '_');

      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

      final dbRef = FirebaseDatabase.instance.ref('locations/$safeDeviceId');
      await dbRef.set({
        'latitude': position.latitude,
        'longitude': position.longitude,
        'timestamp': DateTime.now().toIso8601String(),
      });

      debugPrint('[YAŞLI CİHAZI] (ÖN PLAN) Konum Firebase\'e gönderildi: $safeDeviceId, $position');
    } catch (e) {
      debugPrint('[YAŞLI CİHAZI] (ÖN PLAN) Konum gönderme hatası: $e');
    }
  }

  // Servis durumunu gösteren dialog
  void _showServiceStatus(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Arka Plan Servisi Durumu'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Servis Durumu: Çalışıyor'),
              const SizedBox(height: 8),
              Text('Son Kontrol: ${DateTime.now().toString().substring(11, 19)}'),
              const SizedBox(height: 16),
              const Text(
                'Arka plan servisi aktif ve ortam sesi dinleme isteklerini bekliyor.\n\n'
                'Eğer sorun yaşıyorsanız:\n'
                '1. Uygulamayı yeniden başlatın\n'
                '2. Pil optimizasyonunu kapatın\n'
                '3. Arka plan izinlerini kontrol edin',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Tamam'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _stopRemoteAlarm() async {
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
      if (deviceId == null) return;
      final dbRef = FirebaseDatabase.instance.ref('alarms/$deviceId');
      await dbRef.update({'alarm': false, 'alarm_playing': false});
      AlarmAudioPlayer.instance.stop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Alarm başarıyla durduruldu.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Alarmı durdururken hata oluştu: $e')),
      );
    }
  }

  void _listenToAlarmStatus() async {
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
    if (deviceId == null) return;
    final safeDeviceId = deviceId.replaceAll(RegExp(r'[.#$\[\]]'), '_');
    final dbRef = FirebaseDatabase.instance.ref('alarms/$safeDeviceId');
    _alarmSubscription = dbRef.onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      final isActive = data != null && data['alarm'] == true;
      if (mounted) {
        setState(() {
          _isAlarmActive = isActive;
        });
      }
    });
  }

  void startAlarmCheck() {
    print('[ALARM][DEBUG] startAlarmCheck fonksiyonu başlatıldı');
    alarmCheckTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
      print('[ALARM][DEBUG] Timer tetiklendi, Firebase alarm kontrolü başlıyor');
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
        if (deviceId == null) return;
        final safeDeviceId = deviceId.replaceAll(RegExp(r'[.#$\[\]]'), '_');

        final alarmRef = FirebaseDatabase.instance.ref('alarms/$safeDeviceId');
        final snapshot = await alarmRef.get();
        print('[ALARM][DEBUG] Firebase alarms/$safeDeviceId yolundan veri çekildi: exists=${snapshot.exists}');
        if (snapshot.exists) {
          final data = snapshot.value as Map?;
          print('[ALARM][DEBUG] Alarm verisi: $data');
          if (data != null && data['alarm'] == true) {
            print('[ALARM] Alarm isteği alındı, alarm çalınıyor...');
            // Alarm çalınıyor flagini yaz
            await alarmRef.update({'alarm_playing': true});
            final prefs = await SharedPreferences.getInstance();
            final customAlarmPath = prefs.getString('alarm_sound_path');
            bool played = false;
            String? alarmFilePath = customAlarmPath;

            // --- YENİ: Firebase'den alarm sesi ve dosya adı çekme ---
            try {
              final alarmSoundRef = FirebaseDatabase.instance.ref('alarm_sounds/$safeDeviceId');
              final alarmSoundSnap = await alarmSoundRef.get();
              print('[ALARM][DEBUG] alarm_sounds/$safeDeviceId yolundan veri çekildi: exists=${alarmSoundSnap.exists}');
              if (alarmSoundSnap.exists) {
                final alarmSoundData = alarmSoundSnap.value as Map?;
                final audioBase64 = alarmSoundData?['audio_base64'] as String?;
                final fileName = alarmSoundData?['file_name'] as String?;
                print('[ALARM][DEBUG] audio_base64 var mı: ${audioBase64 != null}, file_name: $fileName');
                if (audioBase64 != null && fileName != null) {
                  final dir = await getApplicationDocumentsDirectory();
                  final filePath = '${dir.path}/$fileName';
                  final file = File(filePath);
                  if (!await file.exists()) {
                    print('[ALARM] Firebase alarm sesi indiriliyor ve kaydediliyor: $fileName');
                    try {
                      final bytes = base64Decode(audioBase64);
                      await file.writeAsBytes(bytes);
                      print('[ALARM] Dosya kaydedildi: $filePath');
                    } catch (e) {
                      print('[ALARM][HATA] Dosya decode/kaydetme hatası: $e');
                    }
                  } else {
                    print('[ALARM] Dosya zaten var: $filePath');
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
                  // Sesin süresi kadar bekle, sonra alarm_playing'i false yap
                  await Future.delayed(const Duration(seconds: 15));
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
                await Future.delayed(const Duration(seconds: 15));
              } catch (e) {
                print('[ALARM][HATA] alarm.mp3 çalınamadı: $e');
              }
            }

            // Alarmı resetle
          }
        }
      } catch (e) {
        print('[ALARM][HATA] Alarm kontrolünde hata: $e');
      }
    });
  }
} 