import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:record/record.dart';
import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:provider/provider.dart';
import '../services/elderly_selection_service.dart';
import '../models/elderly_person.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../services/notification_service.dart';
import '../services/premium_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import '../services/auth_service.dart';

// >>> YENİ: SOSAlert veri modeli
class SOSAlert {
  final String id;
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final String status;
  final String userEmail;

  SOSAlert({
    required this.id,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.status,
    required this.userEmail,
  });
}
// <<< YENİ

class FamilyPanelScreen extends StatefulWidget {
  const FamilyPanelScreen({super.key});

  @override
  State<FamilyPanelScreen> createState() => _FamilyPanelScreenState();
}

class _FamilyPanelScreenState extends State<FamilyPanelScreen> {
  final MapController _mapController = MapController();
  LatLng? _trackedPosition;
  String? _trackedName;
  bool _isRecording = false;
  final List<Map<String, dynamic>> _envSounds = [];
  List<SOSAlert> _sosAlerts = [];
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _recordedFilePath;
  StreamSubscription<DatabaseEvent>? _locationSubscription;
  StreamSubscription<DatabaseEvent>? _envSoundsSubscription;
  StreamSubscription<DatabaseEvent>? _voiceMessageSubscription;
  StreamSubscription<DatabaseEvent>? _elderlyVoiceMessageSubscription;
  StreamSubscription<DatabaseEvent>? _sosAlertsSubscription;
  StreamSubscription<DatabaseEvent>? _batterySubscription;
  StreamSubscription<DatabaseEvent>? _serviceStatusSubscription;
  ElderlyPerson? _selectedElderly;
  final AudioRecorder _audioRecorder = AudioRecorder();
  int? _elderlyBatteryLevel;
  DateTime? _lastBatteryUpdate;
  bool _isPremium = false;
  int _familyCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSelectedElderly();
      _checkPremiumAndCount();
    });
  }

  Future<void> _checkPremiumAndCount() async {
    final isPremium = await PremiumService.isUserPremium();
    setState(() {
      _isPremium = isPremium ?? false;
    });
    // Kullanıcının eklediği aile üyesi sayısını çek
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final dbRef = FirebaseDatabase.instance.ref('users/${user.uid}/family_members');
      final snapshot = await dbRef.get();
      if (snapshot.exists && snapshot.value is Map) {
        setState(() {
          _familyCount = (snapshot.value as Map).length;
        });
      }
    }
  }

  void _loadSelectedElderly() {
    final elderlyService = Provider.of<ElderlySelectionService>(context, listen: false);

    // Önceki dinleyicileri iptal et
    _locationSubscription?.cancel();
    _envSoundsSubscription?.cancel();
    _voiceMessageSubscription?.cancel();
    _elderlyVoiceMessageSubscription?.cancel();
    _sosAlertsSubscription?.cancel();
    _batterySubscription?.cancel();
    _serviceStatusSubscription?.cancel();
    
    _selectedElderly = elderlyService.selectedElderly;

    // >>> TEŞHİS ADIM 1: Seçilen kişinin bilgileri doğru mu?
    if (_selectedElderly != null) {
      print('>>> [PANEL BİLGİSİ] Panel açıldı. Seçilen kişi: ${_selectedElderly!.name}');
      print('>>> [PANEL BİLGİSİ] Bu kişinin Cihaz Kimliği: ${_selectedElderly!.deviceId}');
    } else {
      print('>>> [PANEL BİLGİSİ] Panel açıldı ama seçili bir kişi YOK.');
    }
    // <<< TEŞHİS ADIM 1 SONU

    setState(() {
      // Yeni kişi seçildiğinde eski verileri temizle
      _envSounds.clear();
      _sosAlerts.clear();
      _trackedPosition = null;

      if (_selectedElderly != null) {
        _trackedName = _selectedElderly!.name;
        _listenToTrackedLocation();
        _listenToEnvSounds();
        _listenToVoiceMessages();
        _listenToElderlyVoiceMessages();
        _listenToSOSAlerts();
        _listenToBattery();
      } else {
        _trackedName = 'Takip Edilen Kişi';
        // Yaşlı seçimi kaldırıldığında tüm verileri temizle ve SOS takibini durdur
        print('🗑️ [PANEL] Yaşlı seçimi kaldırıldı, tüm veriler temizlendi');
        
        // SOS takibini durdur
        final notificationService = Provider.of<NotificationService>(context, listen: false);
        notificationService.stopSOSTracking();
        print('🛑 [PANEL] SOS takibi durduruldu');
      }
    });
  }

  void _listenToTrackedLocation() {
    if (_selectedElderly == null) {
      debugPrint('[AILE PANELI] Takip edilen yaşlı seçili değil, konum dinlenemiyor.');
      return;
    }
    
    print('Seçilen kişi: ${_selectedElderly!.name}');
    print('DeviceId: ${_selectedElderly!.deviceId}');
    print('ID: ${_selectedElderly!.id}');
    
    String deviceId = _selectedElderly!.deviceId ?? 'user1';
    deviceId = deviceId.replaceAll(RegExp(r'[.#$\[\]]'), '_');
    final dbRef = FirebaseDatabase.instance.ref('locations/$deviceId');
    debugPrint('[AILE PANELI] Firebase yolu: locations/$deviceId');
    
    _locationSubscription = dbRef.onValue.listen((event) async {
      debugPrint('[AILE PANELI] Firebase event alındı: ${event.snapshot.value}');
      final data = event.snapshot.value;
      
      if (data != null) {
        try {
          final user = FirebaseAuth.instance.currentUser;
          if (user == null) {
            debugPrint('[AILE PANELI] Kullanıcı girişi bulunamadı');
            return;
          }

          Map<String, dynamic>? jsonData;
          if (data is String) {
            final decryptedData = await AuthService.decryptData(data, user.uid);
            if (decryptedData == data) {
              debugPrint('[AILE PANELI] Veri çözülemedi, şifrelenmemiş veri olabilir');
              return;
            }
            
            try {
              jsonData = jsonDecode(decryptedData);
            } catch (jsonError) {
              debugPrint('[AILE PANELI] JSON çözme hatası: $jsonError');
              return;
            }
          } else if (data is Map<String, dynamic> || data is Map<Object?, Object?>) {
            jsonData = Map<String, dynamic>.from(data as Map);
          } else {
            debugPrint('[AILE PANELI] Bilinmeyen veri formatı: ${data.runtimeType}');
            return;
          }

          if (jsonData != null && jsonData['latitude'] != null && jsonData['longitude'] != null) {
            debugPrint('[AILE PANELI] Konum verisi bulundu: $jsonData');
        setState(() {
          _trackedPosition = LatLng(
                (jsonData!['latitude'] as num).toDouble(),
                (jsonData['longitude'] as num).toDouble(),
          );
        });
          debugPrint('[AILE PANELI] Konum güncellendi: $_trackedPosition');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            debugPrint('[AILE PANELI] Harita yeni konuma odaklanıyor: $_trackedPosition');
              if (_trackedPosition != null) {
            _mapController.move(_trackedPosition!, 15.0);
              }
          });
        } else {
            debugPrint('[AILE PANELI] Konum verisi bulunamadı! Data: $jsonData, deviceId: $deviceId');
          }
        } catch (e) {
          debugPrint('[AILE PANELI] Konum verisi çözme hatası: $e');
        }
      } else {
        debugPrint('[AILE PANELI] Firebase event data null! deviceId: $deviceId');
      }
    }, onError: (error) {
      debugPrint('[AILE PANELI] Konum dinleme hatası: $error, deviceId: $deviceId');
      setState(() {
        _trackedPosition = LatLng(41.0082, 28.9784); // İstanbul varsayılan konum
      });
    });
  }

  Future<void> _sendRemoteAlarm() async {
    print('Alarm gönderme başladı');
    try {
      if (_selectedElderly == null) {
        print('Seçili kişi null');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kişi seçili değil!'))
        );
        return;
      }
      
      String deviceId = _selectedElderly!.deviceId ?? 'user1';
      deviceId = deviceId.replaceAll(RegExp(r'[.#$\[\]]'), '_');

      print('Alarm gönderiliyor: $deviceId');
      final dbRef = FirebaseDatabase.instance.ref('alarms/$deviceId');
      await dbRef.set({'alarm': true, 'timestamp': DateTime.now().toIso8601String()});
      print('Alarm başarıyla gönderildi');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_trackedName ?? "Kişi"} için uzaktan alarm tetiklendi!'))
      );
    } catch (e) {
      print('Alarm gönderme hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alarm gönderilemedi!'))
      );
    }
  }

  Future<void> _stopRemoteAlarm() async {
    print('Alarm durdurma başladı');
    try {
      if (_selectedElderly == null) {
        print('Seçili kişi null');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kişi seçili değil!'))
        );
        return;
      }
      String deviceId = _selectedElderly!.deviceId ?? 'user1';
      deviceId = deviceId.replaceAll(RegExp(r'[.#$\[\]]'), '_');
      print('Alarm durduruluyor: $deviceId');
      final dbRef = FirebaseDatabase.instance.ref('alarms/$deviceId');
      await dbRef.set({'alarm': false, 'timestamp': DateTime.now().toIso8601String()});
      print('Alarm başarıyla durduruldu');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_trackedName ?? "Kişi"} için uzaktan alarm durduruldu!'))
      );
    } catch (e) {
      print('Alarm durdurma hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alarm durdurulamadı!'))
      );
    }
  }

  Future<void> _startRecording() async {
    print('Ses kaydı başlatılıyor');
    try {
      if (!await _audioRecorder.hasPermission()) {
        print('Mikrofon izni yok');
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mikrofon izni gerekli!')));
        return;
      }
      
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice_message_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _audioRecorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);

      setState(() {
        _isRecording = true;
        _recordedFilePath = null;
      });
      
      print('Ses kaydı başladı: $path');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ses kaydı başladı...')));
    } catch (e) {
      print('Kayıt başlatılamadı: $e');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kayıt başlatılamadı!')));
    }
  }

  Future<void> _stopRecordingAndSend() async {
    print('Ses kaydı durduruluyor ve gönderiliyor');
    try {
      if (_selectedElderly == null) {
        print('Seçili kişi null');
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kişi seçili değil!')));
        return;
      }
      
    final path = await _audioRecorder.stop();
      if (path == null) {
        print('Kayıt yolu null');
        setState(() { _isRecording = false; });
        return;
      }

      setState(() {
        _isRecording = false;
        _recordedFilePath = path;
      });

      print('Kayıt durduruldu: $path');
      
      final file = File(_recordedFilePath!);
      
      String deviceId = _selectedElderly!.deviceId ?? 'user1';
      deviceId = deviceId.replaceAll(RegExp(r'[.#$\[\]]'), '_');

      print('Sesli mesaj gönderiliyor: $deviceId');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sesli mesaj gönderiliyor...')));

      final fileBytes = await file.readAsBytes();
      final base64String = base64Encode(fileBytes);

      final voiceMessageRef = FirebaseDatabase.instance.ref('voice_messages/$deviceId').push();
      await voiceMessageRef.set({
        'audio_base64': base64String,
        'timestamp': DateTime.now().toIso8601String(),
        'from': 'family_member',
        'encoding': 'aacLc_base64'
      });

      await file.delete();
      print('Sesli mesaj başarıyla gönderildi');

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sesli mesaj başarıyla gönderildi!')));

    } catch (e) {
      print('Kayıt durdurma/gönderme hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mesaj gönderilemedi!')));
    }
  }

  // Ortam sesi isteği gönder (yaşlı cihazı dinlesin)
  Future<void> _sendListenRequest() async {
    if (_selectedElderly == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kişi seçili değil!')),
      );
      return;
    }
    try {
      String deviceId = _selectedElderly!.deviceId ?? 'user1';
      deviceId = deviceId.replaceAll(RegExp(r'[.#$\[\]]'), '_');
      
      print('🔍 [ORTAM SESİ İSTEĞİ] Gönderilen deviceId: $deviceId');
      print('🔍 [ORTAM SESİ İSTEĞİ] Firebase yolu: listen_requests/$deviceId');
      
      final dbRef = FirebaseDatabase.instance.ref('listen_requests/$deviceId');
      await dbRef.set({'request': true, 'timestamp': ServerValue.timestamp});
      
      print('🔍 [ORTAM SESİ İSTEĞİ] İstek başarıyla gönderildi');
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ortam sesi isteği gönderildi, yaşlı cihazı kaydedecek.')),
      );
    } catch (e) {
      print('❌ [ORTAM SESİ İSTEĞİ] Hata: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('İstek gönderilemedi: $e')),
      );
    }
  }

  // Ortam seslerini dinle (env_sounds/{deviceId})
  void _listenToEnvSounds() {
    if (_selectedElderly == null) return;
    String deviceId = _selectedElderly!.deviceId ?? 'user1';
    deviceId = deviceId.replaceAll(RegExp(r'[.#$\[\]]'), '_');
    final dbRef = FirebaseDatabase.instance.ref('env_sounds/$deviceId');
    _envSoundsSubscription = dbRef.onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (data != null) {
        final List<Map<String, dynamic>> sounds = [];
        data.forEach((key, value) {
          final sound = Map<String, dynamic>.from(value as Map);
          sound['key'] = key;
          sounds.add(sound);
        });
        sounds.sort((a, b) => (b['timestamp'] as String).compareTo(a['timestamp'] as String));
        setState(() {
          _envSounds
            ..clear()
            ..addAll(sounds);
        });
      } else {
          setState(() {
          _envSounds.clear();
        });
      }
    });
  }

  // Sesli mesajları dinle (voice_messages/{deviceId})
  void _listenToVoiceMessages() {
    if (_selectedElderly == null) return;
    String deviceId = _selectedElderly!.deviceId ?? 'user1';
    deviceId = deviceId.replaceAll(RegExp(r'[.#$\[\]]'), '_');
    final voiceRef = FirebaseDatabase.instance.ref('voice_messages/$deviceId');
    _voiceMessageSubscription = voiceRef.onChildAdded.listen((event) {
      final data = event.snapshot.value as Map?;
      // Sadece 'from' alanı 'family_member' olmayanları ekle
      if (data != null && data['audio_base64'] != null && data['from'] != 'family_member') {
        setState(() {
          if (!_envSounds.any((s) => s['key'] == event.snapshot.key)) {
            _envSounds.add({
              'key': event.snapshot.key!,
              'audio_base64': data['audio_base64'],
              'timestamp': data['timestamp'] ?? '',
              'from': data['from'] ?? 'voice',
            });
            _envSounds.sort((a, b) => (b['timestamp'] as String).compareTo(a['timestamp'] as String));
          }
        });
      }
    });
  }

  // Yaşlıdan gelen sesli mesajları dinle (family_member)
  void _listenToElderlyVoiceMessages() {
    final voiceRef = FirebaseDatabase.instance.ref('voice_messages/family_member');
    _elderlyVoiceMessageSubscription = voiceRef.onChildAdded.listen((event) {
      final data = event.snapshot.value as Map?;
      if (data != null && data['audio_base64'] != null && data['from'] == 'elderly') {
        setState(() {
          if (!_envSounds.any((s) => s['key'] == event.snapshot.key)) {
            _envSounds.add({
              'key': event.snapshot.key!,
              'audio_base64': data['audio_base64'],
              'timestamp': data['timestamp'] ?? '',
              'from': 'elderly_voice',
            });
            _envSounds.sort((a, b) => (b['timestamp'] as String).compareTo(a['timestamp'] as String));
          }
        });
      }
    });
  }

  // SOS bildirimlerini dinle
  void _listenToSOSAlerts() {
    if (_selectedElderly == null) return;
    final deviceId = _selectedElderly!.deviceId;
    if (deviceId == null || deviceId.isEmpty) {
      setState(() { _sosAlerts = []; });
      return;
    }
    final sanitizedDeviceId = deviceId.replaceAll(RegExp(r'[.#$\[\]_]'), '_');
    final dbPath = 'sos_alerts/$sanitizedDeviceId';
    final dbRef = FirebaseDatabase.instance.ref(dbPath);
    _sosAlertsSubscription = dbRef.onValue.listen((event) {
      final alertsData = event.snapshot.value as Map?;
      if (alertsData == null) {
        setState(() { _sosAlerts = []; });
        return;
      }
      final List<SOSAlert> alerts = [];
      for (var entry in alertsData.entries) {
        try {
          final data = entry.value as Map<dynamic, dynamic>;
          final locationData = data['location'] as Map<dynamic, dynamic>?;
          alerts.add(SOSAlert(
            id: entry.key,
            timestamp: DateTime.fromMillisecondsSinceEpoch(_getTimestampMs(data['timestamp'])),
            latitude: locationData?['latitude'] as double? ?? 0.0,
            longitude: locationData?['longitude'] as double? ?? 0.0,
            status: data['status'] as String? ?? 'active',
            userEmail: data['user_email'] as String? ?? 'Bilinmiyor',
          ));
        } catch (e) {}
      }
      alerts.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (mounted) {
        setState(() { _sosAlerts = alerts; });
      }
    });
  }

  int _getTimestampMs(dynamic value) {
    if (value is int) {
      return value;
    } else if (value is String) {
      return int.tryParse(value) ?? DateTime.tryParse(value)?.millisecondsSinceEpoch ?? 0;
    }
    return 0;
  }

  // Yaşlının batarya bilgisini dinle
  void _listenToBattery() {
    if (_selectedElderly == null) return;
    String deviceId = _selectedElderly!.deviceId ?? 'user1';
    deviceId = deviceId.replaceAll(RegExp(r'[.#$\[\]]'), '_');
    print('🔍 [BATARYA] Dinlenen deviceId: $deviceId');
    print('🔍 [BATARYA] Firebase yolu: battery_levels/$deviceId');
    
    final dbRef = FirebaseDatabase.instance.ref('battery_levels/$deviceId');
    _batterySubscription = dbRef.onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (data != null && data['level'] != null) {
        print('🔍 [BATARYA] Batarya bilgisi geldi: ${data['level']}');
        setState(() {
          _elderlyBatteryLevel = data['level'] as int?;
          _lastBatteryUpdate = DateTime.now();
        });
      } else {
        print('🔍 [BATARYA] Geçersiz veri formatı: $data');
      }
    }, onError: (error) {
      print('❌ [BATARYA] Dinleme hatası: $error');
    });
  }

  Widget _buildMap() {
    return SizedBox(
      height: 200,
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _trackedPosition ?? LatLng(39.9334, 32.8597), // Ankara merkezi
          initialZoom: 15.0,
          minZoom: 10.0,
          maxZoom: 18.0,
          onMapReady: () {
            print('Aile paneli haritası hazır');
            if (_trackedPosition != null) {
              print('Aile paneli haritası başlangıçta konuma odaklanıyor: $_trackedPosition');
              _mapController.move(_trackedPosition!, 15.0);
            }
          },
          keepAlive: true,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
            subdomains: const ['a', 'b', 'c'],
            userAgentPackageName: 'com.yasligoz.gpstracker',
            maxZoom: 18,
            tileProvider: NetworkTileProvider(),
          ),
          if (_trackedPosition != null)
            MarkerLayer(
              markers: [
                Marker(
                  width: 60.0,
                  height: 60.0,
                  point: _trackedPosition!,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.person_pin_circle,
                      color: Colors.white,
                      size: 30.0,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildLocationCard() {
    return _trackedPosition == null
        ? const SizedBox.shrink()
        : Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on, color: Colors.blue, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_trackedName ?? "Takip Edilen Kişi"} Konumu',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Enlem: ${_trackedPosition!.latitude.toStringAsFixed(6)}\nBoylam: ${_trackedPosition!.longitude.toStringAsFixed(6)}',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () {
                    _mapController.move(_trackedPosition!, 15.0);
                  },
                  icon: const Icon(Icons.my_location, color: Colors.blue),
                  tooltip: 'Konuma Git',
                ),
              ],
            ),
          );
  }

  Widget _buildBatteryCard() {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _elderlyBatteryLevel != null && _elderlyBatteryLevel! <= 20 
            ? Colors.red.shade50 
            : Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _elderlyBatteryLevel != null && _elderlyBatteryLevel! <= 20 
              ? Colors.red.shade200 
              : Colors.green.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.battery_full,
            color: _elderlyBatteryLevel != null && _elderlyBatteryLevel! <= 20 
                ? Colors.red 
                : Colors.green,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_trackedName ?? "Takip Edilen Kişi"} Bataryası',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                if (_elderlyBatteryLevel != null) ...[
                  Text(
                    'Seviye: %$_elderlyBatteryLevel',
                    style: TextStyle(
                      color: _elderlyBatteryLevel! <= 20 ? Colors.red : Colors.green,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_lastBatteryUpdate != null)
                    Text(
                      'Son Güncelleme: ${DateFormat('HH:mm').format(_lastBatteryUpdate!)}',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                ] else
                  Text(
                    'Batarya bilgisi alınıyor...',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 14,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 2.5,
        children: [
          ElevatedButton.icon(
            onPressed: _sendRemoteAlarm,
            icon: const Icon(Icons.notifications_active),
            label: const Text('Uzak Alarm'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange, foregroundColor: Colors.white),
          ),
          ElevatedButton.icon(
            onPressed: _stopRemoteAlarm,
            icon: const Icon(Icons.notifications_off),
            label: const Text('Alarmı Durdur'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
          ),
          ElevatedButton.icon(
            onPressed: _sendListenRequest,
            icon: const Icon(Icons.hearing),
            label: const Text('Ortam Sesi İste'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal, foregroundColor: Colors.white),
          ),
          GestureDetector(
            onLongPressStart: (_) => _startRecording(),
            onLongPressEnd: (_) => _stopRecordingAndSend(),
            child: ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Sesli mesaj göndermek için basılı tutun.')),
                );
              },
              icon: Icon(_isRecording ? Icons.mic : Icons.mic_none),
              label: const Text('Sesli Mesaj Gönder'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isRecording ? Colors.red : Colors.blueAccent,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnvSoundsList() {
    return Container(
      height: 220,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: _envSounds.isEmpty
        ? const Center(child: Text('Sesli mesaj veya ortam sesi kaydı yok'))
        : ListView.builder(
            itemCount: _envSounds.length,
            itemBuilder: (context, index) {
              final sound = _envSounds[index];
              final formattedDate = sound['timestamp'] != null && sound['timestamp'].toString().isNotEmpty
                ? sound['timestamp'].toString().replaceAll('T', ' ').substring(0, 19)
                : 'Tarih yok';
              final isEnv = sound['from'] == 'env_record';
              final isElderlyVoice = sound['from'] == 'elderly_voice';
              final isFamilyVoice = sound['from'] == 'family_member';
              
              IconData icon;
              String label;
              Color iconColor;
              
              if (isEnv) {
                icon = Icons.multitrack_audio;
                label = 'Ortam Sesi';
                iconColor = Colors.teal;
              } else if (isElderlyVoice) {
                icon = Icons.mic;
                label = 'Yaşlıdan Sesli Mesaj';
                iconColor = Colors.orange;
              } else if (isFamilyVoice) {
                icon = Icons.mic;
                label = 'Aileden Sesli Mesaj';
                iconColor = Colors.blue;
              } else {
                icon = Icons.mic;
                label = 'Sesli Mesaj';
                iconColor = Colors.grey;
              }
              
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  leading: Icon(icon, color: iconColor),
                  title: Text('$label - $formattedDate'),
                  onTap: () => _playSound(sound['audio_base64'] as String?),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _showDeleteSoundDialog(sound),
                    tooltip: 'Mesajı Sil',
                  ),
                ),
              );
            },
          ),
    );
  }

  Future<void> _playSound(String? base64String) async {
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

  // Sesli mesajı sil
  Future<void> _deleteSound(Map<String, dynamic> sound) async {
    try {
      final soundKey = sound['key'] as String?;
      if (soundKey == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mesaj silinemedi: Geçersiz anahtar')),
        );
        return;
      }

      // Firebase'den sil
      if (_selectedElderly != null) {
        String deviceId = _selectedElderly!.deviceId ?? 'user1';
        deviceId = deviceId.replaceAll(RegExp(r'[.#$\[\]]'), '_');
        
        // Mesaj türüne göre Firebase yolunu belirle
        String firebasePath;
        if (sound['from'] == 'env_record') {
          firebasePath = 'env_sounds/$deviceId/$soundKey';
        } else if (sound['from'] == 'elderly_voice') {
          firebasePath = 'voice_messages/family_member/$soundKey';
        } else {
          firebasePath = 'voice_messages/$deviceId/$soundKey';
        }
        
        await FirebaseDatabase.instance.ref(firebasePath).remove();
        
        // Yerel listeden kaldır
        setState(() {
          _envSounds.removeWhere((s) => s['key'] == soundKey);
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mesaj başarıyla silindi')),
        );
      }
    } catch (e) {
      print('Mesaj silme hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mesaj silinemedi: $e')),
      );
    }
  }

  // Sesli mesaj silme onay dialogu
  void _showDeleteSoundDialog(Map<String, dynamic> sound) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Mesajı Sil'),
          content: const Text('Bu mesajı silmek istediğinizden emin misiniz? Bu işlem geri alınamaz.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('İptal'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deleteSound(sound);
              },
              child: const Text('Sil', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  // SOS bildirimlerini listele
  Widget _buildSOSList() {
    return Container(
      height: 220,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.builder(
        itemCount: _sosAlerts.length,
        itemBuilder: (context, index) {
          final alert = _sosAlerts[index];
          final formattedDate = DateFormat('yyyy-MM-dd HH:mm:ss').format(alert.timestamp);
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.warning, color: Colors.red),
              title: Text('SOS Sinyali - ${alert.userEmail}'),
              subtitle: Text('Tarih: $formattedDate\nKonum: ${alert.latitude.toStringAsFixed(5)}, ${alert.longitude.toStringAsFixed(5)}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                icon: const Icon(Icons.location_on),
                onPressed: () => _openMap(alert.latitude, alert.longitude),
                    tooltip: 'Haritada Göster',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _showDeleteSOSDialog(alert),
                    tooltip: 'SOS Bildirimini Sil',
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // SOS bildirimi silme onay dialogu
  void _showDeleteSOSDialog(SOSAlert alert) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('SOS Bildirimini Sil'),
          content: const Text('Bu SOS bildirimini silmek istediğinizden emin misiniz? Bu işlem geri alınamaz.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('İptal'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deleteSOSAlert(alert);
              },
              child: const Text('Sil', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openMap(double latitude, double longitude) async {
    try {
      final googleMapsUrl = Uri.parse('https://www.google.com/maps/search/?api=1&query=$latitude,$longitude');
      if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
        return;
      }
      final alternativeUrl = Uri.parse('https://maps.google.com/?q=$latitude,$longitude');
      if (await canLaunchUrl(alternativeUrl)) {
        await launchUrl(alternativeUrl, mode: LaunchMode.externalApplication);
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Harita uygulaması açılamadı. Konum: $latitude, $longitude'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Harita açılırken hata oluştu: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // SOS bildirimini sil
  Future<void> _deleteSOSAlert(SOSAlert alert) async {
    try {
      if (_selectedElderly != null) {
        final deviceId = _selectedElderly!.deviceId;
        if (deviceId == null || deviceId.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('SOS bildirimi silinemedi: Cihaz ID bulunamadı')),
          );
          return;
        }
        
        final sanitizedDeviceId = deviceId.replaceAll(RegExp(r'[.#$\[\]_]'), '_');
        final sanitizedAlertId = alert.id.replaceAll(RegExp(r'[.#$\[\]]'), '_');
        final dbPath = 'sos_alerts/$sanitizedDeviceId/$sanitizedAlertId';
        
        await FirebaseDatabase.instance.ref(dbPath).remove();
        
        // Yerel listeden kaldır
        setState(() {
          _sosAlerts.removeWhere((a) => a.id == alert.id);
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SOS bildirimi başarıyla silindi')),
        );
      }
    } catch (e) {
      print('SOS bildirimi silme hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('SOS bildirimi silinemedi: $e')),
      );
    }
  }

  // Tüm sesli mesajları sil
  Future<void> _deleteAllSounds() async {
    try {
      if (_selectedElderly == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kişi seçili değil!')),
        );
        return;
      }

      String deviceId = _selectedElderly!.deviceId ?? 'user1';
      deviceId = deviceId.replaceAll(RegExp(r'[.#$\[\]]'), '_');
      
      // Firebase'den tüm sesli mesajları sil
      await FirebaseDatabase.instance.ref('env_sounds/$deviceId').remove();
      await FirebaseDatabase.instance.ref('voice_messages/$deviceId').remove();
      await FirebaseDatabase.instance.ref('voice_messages/family_member').remove();
      
      // Yerel listeyi temizle
      setState(() {
        _envSounds.clear();
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tüm sesli mesajlar başarıyla silindi')),
      );
    } catch (e) {
      print('Toplu sesli mesaj silme hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sesli mesajlar silinemedi: $e')),
      );
    }
  }

  // Tüm SOS bildirimlerini sil
  Future<void> _deleteAllSOSAlerts() async {
    try {
      if (_selectedElderly == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kişi seçili değil!')),
        );
        return;
      }

      final deviceId = _selectedElderly!.deviceId;
      if (deviceId == null || deviceId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cihaz ID bulunamadı!')),
        );
        return;
      }
      
      final sanitizedDeviceId = deviceId.replaceAll(RegExp(r'[.#$\[\]_]'), '_');
      
      // Firebase'den tüm SOS bildirimlerini sil
      await FirebaseDatabase.instance.ref('sos_alerts/$sanitizedDeviceId').remove();
      
      // Yerel listeyi temizle
      setState(() {
        _sosAlerts.clear();
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tüm SOS bildirimleri başarıyla silindi')),
      );
    } catch (e) {
      print('Toplu SOS bildirimi silme hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('SOS bildirimleri silinemedi: $e')),
      );
    }
  }

  // Tüm sesli mesajları silme onay dialogu
  void _showDeleteAllSoundsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Tüm Sesli Mesajları Sil'),
          content: const Text('Tüm sesli mesajları ve ortam seslerini silmek istediğinizden emin misiniz? Bu işlem geri alınamaz.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('İptal'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deleteAllSounds();
              },
              child: const Text('Tümünü Sil', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  // Tüm SOS bildirimlerini silme onay dialogu
  void _showDeleteAllSOSDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Tüm SOS Bildirimlerini Sil'),
          content: const Text('Tüm SOS bildirimlerini silmek istediğinizden emin misiniz? Bu işlem geri alınamaz.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('İptal'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deleteAllSOSAlerts();
              },
              child: const Text('Tümünü Sil', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedElderly != null
            ? '${_selectedElderly!.name} Paneli'
            : 'Aile Paneli'),
      ),
      body: _selectedElderly == null
          ? const Center(
              child: Text(
                  'Lütfen yaşlı listesinden birini seçin.'),
            )
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                _buildMap(),
                const SizedBox(height: 16),
                _buildLocationCard(),
                const SizedBox(height: 16),
                _buildBatteryCard(),
                const SizedBox(height: 16),
                _buildActionButtons(),
                const SizedBox(height: 16),
                if (_sosAlerts.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                    'Aktif SOS Sinyalleri',
                    style: Theme.of(context).textTheme.titleLarge,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _showDeleteAllSOSDialog(),
                        icon: const Icon(Icons.delete_sweep, color: Colors.red, size: 20),
                        label: const Text(
                          'Tümünü Sil',
                          style: TextStyle(color: Colors.red, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildSOSList(),
                ],
                if (_envSounds.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                    'Gelen Sesler (Mesaj, Ortam & Yaşlı)',
                    style: Theme.of(context).textTheme.titleLarge,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _showDeleteAllSoundsDialog(),
                        icon: const Icon(Icons.delete_sweep, color: Colors.red, size: 20),
                        label: const Text(
                          'Tümünü Sil',
                          style: TextStyle(color: Colors.red, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildEnvSoundsList(),
                ],
              ],
            ),
    );
  }

  @override
  void dispose() {
    _mapController.dispose();
    _locationSubscription?.cancel();
    _envSoundsSubscription?.cancel();
    _voiceMessageSubscription?.cancel();
    _elderlyVoiceMessageSubscription?.cancel();
    _sosAlertsSubscription?.cancel();
    _batterySubscription?.cancel();
    _serviceStatusSubscription?.cancel();
    _audioPlayer.dispose();
    _audioRecorder.dispose();
    super.dispose();
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
} 