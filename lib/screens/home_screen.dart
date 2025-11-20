import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'emergency_screen.dart';
import 'family_panel_screen.dart';
import 'geofence_screen.dart';
import 'settings_screen.dart';
import 'elderly_list_screen.dart';
import 'package:provider/provider.dart';
import '../services/elderly_selection_service.dart';
import '../services/auth_service.dart';
import '../services/background_service.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../screens/role_selection_screen.dart';
import '../services/permission_service.dart';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';

import 'package:firebase_auth/firebase_auth.dart';

class HomeScreen extends StatefulWidget {
  final String deviceRole;
  const HomeScreen({super.key, required this.deviceRole});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MapController _mapController = MapController();
  LatLng? _currentPosition;
  String _locationStatus = '';
  bool _isSilent = false;
  bool _batteryWarned = false;
  LatLng? _lastActivePosition;
  DateTime? _lastActiveTime;
  bool _inactivityWarned = false;
  final AudioRecorder _envRecorder = AudioRecorder();
  StreamSubscription<BatteryState>? _batteryStateSubscription;
  StreamSubscription<DatabaseEvent>? _voiceMessageSubscription;
  Timer? _inactivityTimer;
  Timer? _locationUpdateTimer;
  final AudioPlayer _audioPlayer = AudioPlayer();
  StreamSubscription<DatabaseEvent>? _listenRequestSubscription;
  bool _isLocationFetchInitiated = false;
  LatLng? _geofenceCenter;
  double? _geofenceRadius;
  StreamSubscription<ServiceStatus>? _locationServiceStatusSub;
  bool _wasLocationServiceEnabled = true;
  bool? _elderlyLocationEnabled;
  StreamSubscription<DatabaseEvent>? _locationStatusSubscription;
  Timer? _silentModeTimer;
  StreamSubscription<DatabaseEvent>? _elderlyLocationSubscription;
  
  String? _deviceId;

  @override
  void initState() {
    super.initState();
    _initDeviceId();
    _checkAndRequestPermissions();
    _startSilentModeTracking();
    _checkBatteryLevel();
    _startInactivityCheck();
    _setupDeviceListenersIfNeeded();
    _listenLocationServiceStatus();
    _startLocationUpdateTimer();
  }

  Future<void> _initDeviceId() async {
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
      setState(() {
        _deviceId = deviceId?.replaceAll(RegExp(r'[.#$\[\]]'), '_');
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final selectionService = Provider.of<ElderlySelectionService>(context);
    
    if (selectionService.hasSelectedElderly && !_isLocationFetchInitiated) {
      setState(() {
        _isLocationFetchInitiated = true;
        _locationStatus = '';
      });
      _determinePosition();
      _loadGeofenceForSelectedElderly();
    } else if (!selectionService.hasSelectedElderly && _isLocationFetchInitiated) {
      setState(() {
        _isLocationFetchInitiated = false;
        _currentPosition = null;
        _locationStatus = '';
        _geofenceCenter = null;
        _geofenceRadius = null;
      });
      _elderlyLocationSubscription?.cancel();
    }

    if (widget.deviceRole == 'family' && selectionService.hasSelectedElderly) {
      _listenToElderlyLocationStatus();
    } else {
      _locationStatusSubscription?.cancel();
      setState(() {
        _elderlyLocationEnabled = null;
      });
    }
  }

  Future<void> _checkAndRequestPermissions() async {
    final permissionService = PermissionService();
    
    // İzinleri kontrol et ve gerekirse iste
    await permissionService.checkAndRequestPermissions(
      context: context,
    );
  }

  void _setupDeviceListenersIfNeeded() {
    final elderlyService = Provider.of<ElderlySelectionService>(context, listen: false);
    if (!elderlyService.hasSelectedElderly) {
      _setupDeviceListeners();
    }
  }

  Future<void> _setupDeviceListeners() async {
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
        _listenForEnvironmentSoundRequests(sanitizedDeviceId);
      }
    } catch (e) {
      // Üretim kodunda gereksizse tamamen kaldır
    }
  }

  void _listenForEnvironmentSoundRequests(String deviceId) {
    final dbRef = FirebaseDatabase.instance.ref('listen_requests/$deviceId');
    _listenRequestSubscription = dbRef.onValue.listen((event) async {
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map?;
        if (data != null && data['request'] == true) {
          // Ortam sesi kaydet
          await _recordAndUploadEnvironmentSound(deviceId);
          // İsteği sil
          dbRef.remove();
        }
      }
    });
  }

  // Ortam sesi kaydet ve Firebase'e yükle
  Future<void> _recordAndUploadEnvironmentSound(String deviceId) async {
    try {
      if (!await _envRecorder.hasPermission()) {
        print('Mikrofon izni yok.');
        return;
      }

      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/env_sound_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _envRecorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
      print('Ortam sesi kaydı başladı: $path');

      // 15 saniye bekle
      await Future.delayed(const Duration(seconds: 15));

      final recordedPath = await _envRecorder.stop();
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
      final envSoundRef = FirebaseDatabase.instance.ref('env_sounds/$deviceId').push();
      await envSoundRef.set({
        'audio_base64': base64String,
        'timestamp': DateTime.now().toIso8601String(),
        'encoding': 'aacLc_base64'
      });

      print('Ortam sesi Realtime Database\'e yüklendi.');

      // Geçici dosyayı sil
      await file.delete();

    } catch (e) {
      print('Ortam sesi kaydetme ve yükleme hatası: $e');
    }
  }

  Future<void> _determinePosition() async {
    // Aile cihazı ise yaşlı kişinin konumunu Firebase'den dinle, kendi konumunu alma
    if (widget.deviceRole == 'family') {
      final selectionService = Provider.of<ElderlySelectionService>(context, listen: false);
      if (selectionService.hasSelectedElderly) {
        // Yaşlı kişinin konumunu Firebase'den dinle
        _listenToElderlyLocationFromFirebase();
        return;
      }
    }

    // Yaşlı cihazı ise kendi konumunu al
    try {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _locationStatus = 'Konum servisleri kapalı!';
      });
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          _locationStatus = 'Konum izni reddedildi!';
        });
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _locationStatus = 'Konum izni kalıcı olarak reddedildi!';
      });
      return;
    }

    Position position = await Geolocator.getCurrentPosition(
      timeLimit: const Duration(seconds: 15),
    );
    setState(() {
      _currentPosition = LatLng(position.latitude, position.longitude);
      _locationStatus = '';
    });
    await _saveLocationToFirebase(LatLng(position.latitude, position.longitude));
    } on TimeoutException {
      setState(() {
        _locationStatus = 'Konum alınamadı (zaman aşımı).';
      });
    } catch (e) {
      setState(() {
        _locationStatus = 'Konum alınırken hata oluştu.';
      });
    }
  }

  void _listenToElderlyLocationFromFirebase() {
    // Önceki subscription'ı iptal et
    _elderlyLocationSubscription?.cancel();
    
    final selectionService = Provider.of<ElderlySelectionService>(context, listen: false);
    final elderlyDeviceId = selectionService.selectedElderly?.deviceId;
    
    if (elderlyDeviceId == null) {
      setState(() {
        _locationStatus = 'Yaşlı kişinin cihaz ID\'si bulunamadı!';
      });
      return;
  }

    final sanitizedDeviceId = elderlyDeviceId.replaceAll(RegExp(r'[.#$\[\]]'), '_');
    final dbRef = FirebaseDatabase.instance.ref('locations/$sanitizedDeviceId');
    
    debugPrint('[ANA EKRAN] Yaşlı kişinin Firebase yolu: locations/$sanitizedDeviceId');
    
    _elderlyLocationSubscription = dbRef.onValue.listen((event) async {
      debugPrint('[ANA EKRAN] Yaşlı kişinin Firebase event alındı: ${event.snapshot.value}');
      final data = event.snapshot.value;
      
      if (data != null) {
        try {
          // Kullanıcı anahtarını al
          final user = FirebaseAuth.instance.currentUser;
          if (user == null) {
            debugPrint('[ANA EKRAN] Kullanıcı girişi bulunamadı');
            return;
          }

          Map<String, dynamic>? jsonData;
          
          if (data is String) {
            // Şifreli string veriyi çöz
            final decryptedData = await AuthService.decryptData(data, user.uid);
            if (decryptedData == data) {
              // Çözme başarısız, veri şifrelenmemiş olabilir
              debugPrint('[ANA EKRAN] Veri çözülemedi, şifrelenmemiş veri olabilir');
              return;
            }
            
            try {
              jsonData = jsonDecode(decryptedData);
            } catch (jsonError) {
              debugPrint('[ANA EKRAN] JSON çözme hatası: $jsonError');
              return;
            }
          } else if (data is Map<String, dynamic> || data is Map<Object?, Object?>) {
            // Veri zaten çözülmüş durumda
            jsonData = Map<String, dynamic>.from(data as Map);
          } else {
            debugPrint('[ANA EKRAN] Bilinmeyen veri formatı: ${data.runtimeType}');
            return;
          }
          
          if (jsonData != null && jsonData['latitude'] != null && jsonData['longitude'] != null) {
            debugPrint('[ANA EKRAN] Yaşlı kişinin konum verisi bulundu: $jsonData');
        setState(() {
          _currentPosition = LatLng(
                (jsonData!['latitude'] as num).toDouble(),
                (jsonData['longitude'] as num).toDouble(),
          );
          _locationStatus = '';
        });
        debugPrint('[ANA EKRAN] Yaşlı kişinin konum güncellendi: $_currentPosition');
      } else {
            debugPrint('[ANA EKRAN] Yaşlı kişinin konum verisi bulunamadı! Data: $jsonData, deviceId: $sanitizedDeviceId');
            setState(() {
              _locationStatus = 'Yaşlı kişinin konumu henüz paylaşılmadı.';
            });
          }
        } catch (e) {
          debugPrint('[ANA EKRAN] Konum verisi çözme hatası: $e');
          setState(() {
            _locationStatus = 'Konum verisi çözülemedi: $e';
          });
        }
      } else {
        debugPrint('[ANA EKRAN] Yaşlı kişinin Firebase event data null! deviceId: $sanitizedDeviceId');
        setState(() {
          _locationStatus = 'Yaşlı kişinin konumu henüz paylaşılmadı.';
        });
      }
      }, onError: (e) {
      debugPrint('[ANA EKRAN] Yaşlı kişinin Firebase\'den konum alınamadı: $e, deviceId: $sanitizedDeviceId');
        setState(() {
        _locationStatus = 'Yaşlı kişinin konumu alınamadı: \n\n$e';
        });
      });
  }

  Future<void> _saveLocationToFirebase(LatLng position) async {
    try {
    final dbRef = FirebaseDatabase.instance.ref('locations/${_deviceId ?? 'user1'}');
    await dbRef.set({
      'latitude': position.latitude,
      'longitude': position.longitude,
      'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      setState(() {
        _locationStatus = 'Konum Firebase\'e kaydedilemedi: \n\n$e';
    });
    }
  }

 

  Future<void> _checkSilentMode() async {
    const platform = MethodChannel('com.gpstracker/silent');
    try {
      final bool result = await platform.invokeMethod('isSilent');
      setState(() {
        _isSilent = result;
      });
    } catch (e) {
      // iOS veya hata durumunda sessiz mod kontrolü yapılamaz
      setState(() {
        _isSilent = false;
      });
    }
  }

  Future<void> _checkBatteryLevel() async {
    final battery = Battery();
    final level = await battery.batteryLevel;
    if (level <= 15 && !_batteryWarned) {
      _batteryWarned = true;
      final dbRef = FirebaseDatabase.instance.ref('battery_warnings/${_deviceId ?? 'user1'}');
      await dbRef.set({
        'level': level,
        'timestamp': DateTime.now().toIso8601String(),
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Pil seviyesi %15'in altında!")),
      );
    }
    // 5 dakikada bir tekrar kontrol et
    Future.delayed(const Duration(minutes: 5), _checkBatteryLevel);
  }

  void _startInactivityCheck() {
    Future.delayed(const Duration(minutes: 5), _checkInactivity);
  }

  Future<void> _checkInactivity() async {
    if (_currentPosition != null) {
      if (_lastActivePosition == null) {
        _lastActivePosition = _currentPosition;
        _lastActiveTime = DateTime.now();
      } else {
        double distance = _calculateDistance(
          _lastActivePosition!.latitude,
          _lastActivePosition!.longitude,
          _currentPosition!.latitude,
          _currentPosition!.longitude,
        );
        if (distance > 30) { // 30 metre hareket varsa aktif say
          _lastActivePosition = _currentPosition;
          _lastActiveTime = DateTime.now();
          _inactivityWarned = false;
        } else if (_lastActiveTime != null && DateTime.now().difference(_lastActiveTime!).inMinutes >= 30 && !_inactivityWarned) {
          _inactivityWarned = true;
          final dbRef = FirebaseDatabase.instance.ref('inactivity_warnings/${_deviceId ?? 'user1'}');
          await dbRef.set({
            'timestamp': DateTime.now().toIso8601String(),
            'message': 'Kullanıcı 30 dakikadır hareketsiz.'
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('30 dakikadır hareketsizsiniz!')),
          );
        }
      }
    }
    _startInactivityCheck();
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double R = 6371000; // metre
    double dLat = _deg2rad(lat2 - lat1);
    double dLon = _deg2rad(lon2 - lon1);
    double a =
        (sin(dLat / 2) * sin(dLat / 2)) +
        cos(_deg2rad(lat1)) * cos(_deg2rad(lat2)) *
            (sin(dLon / 2) * sin(dLon / 2));
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _deg2rad(double deg) => deg * pi / 180;

  Future<void> _loadGeofenceForSelectedElderly() async {
    final selectionService = Provider.of<ElderlySelectionService>(context, listen: false);
    final elderlyId = selectionService.selectedElderly?.id;
    if (elderlyId == null) return;
    try {
      final dbRef = FirebaseDatabase.instance.ref('geofence/$elderlyId');
      final snapshot = await dbRef.get();
      if (snapshot.exists && snapshot.value != null && snapshot.value is Map) {
        final data = snapshot.value as Map;
        setState(() {
          _geofenceCenter = LatLng((data['lat'] as num).toDouble(), (data['lng'] as num).toDouble());
          _geofenceRadius = (data['radius'] as num).toDouble();
        });
      }
    } catch (e) {
      // Hata durumunda gösterme
    }
  }

  void _listenLocationServiceStatus() async {
    // Uygulama ilk açıldığında konum servisi kapalı mı?
    _wasLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
    _locationServiceStatusSub = Geolocator.getServiceStatusStream().listen((ServiceStatus status) async {
      if (status == ServiceStatus.enabled && !_wasLocationServiceEnabled) {
        // Konum servisi yeni açıldı, konumu güncelle
        await _determinePosition();
      }
      _wasLocationServiceEnabled = (status == ServiceStatus.enabled);
    });
  }

  void _listenToElderlyLocationStatus() {
    _locationStatusSubscription?.cancel();
    final selectionService = Provider.of<ElderlySelectionService>(context, listen: false);
    final deviceId = selectionService.selectedElderly?.deviceId;
    if (deviceId == null) return;
    final sanitizedDeviceId = deviceId.replaceAll(RegExp(r'[.#$\[\]]'), '_');
    final dbRef = FirebaseDatabase.instance.ref('location_status/$sanitizedDeviceId');
    _locationStatusSubscription = dbRef.onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (data != null && data['enabled'] != null) {
        setState(() {
          _elderlyLocationEnabled = data['enabled'] == true;
        });
      } else {
        setState(() {
          _elderlyLocationEnabled = null;
        });
      }
    });
  }

  void _startSilentModeTracking() {
    _checkSilentMode();
    _silentModeTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _checkSilentMode();
    });
  }

  void _startLocationUpdateTimer() {
    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (widget.deviceRole == 'family') {
        // Aile cihazı için yaşlı kişinin konumunu güncelle
        final selectionService = Provider.of<ElderlySelectionService>(context, listen: false);
        if (selectionService.hasSelectedElderly) {
          _determinePosition();
        }
      } else {
        // Yaşlı cihazı için kendi konumunu güncelle
        _determinePosition();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectionService = Provider.of<ElderlySelectionService>(context);
    
    if (widget.deviceRole == 'elderly') {
      return const EmergencyScreen();
    }

    return Scaffold(
      appBar: AppBar(
        title: widget.deviceRole == 'family'
            ? Row(
                children: [
                  Image.asset(
                    'assets/images/logo.png',
                    width: 40,
                    height: 40,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Ana Sayfa',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                      color: Colors.white,
                    ),
                  ),
                ],
              )
            : const Text('GPS Takipçi'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        toolbarHeight: widget.deviceRole == 'family' ? 64 : kToolbarHeight,
        actions: [
          if (selectionService.hasSelectedElderly)
            IconButton(
              icon: const Icon(Icons.person),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Takip Edilen Kişi'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Ad: ${selectionService.selectedElderly?.name}'),
                        Text('Telefon: ${selectionService.selectedElderly?.phoneNumber}'),
                        if (selectionService.selectedElderly?.address != null && selectionService.selectedElderly!.address.isNotEmpty)
                          Text('Adres: ${selectionService.selectedElderly!.address}'),
                        const SizedBox(height: 16),
                        const Text(
                          'Tüm özellikler bu kişi üzerinde çalışacak:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Text('• Konum takibi'),
                        const Text('• Güvenli alan kontrolü'),
                        const Text('• Acil durum bildirimleri'),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Tamam'),
                      ),
                      TextButton(
                        onPressed: () {
                          selectionService.clearSelection();
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Takip durduruldu')),
                          );
                        },
                        child: const Text('Takibi Durdur', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
              },
              tooltip: 'Takip Edilen Kişi',
            ),
          if (widget.deviceRole == 'elderly') ...[
            IconButton(
              icon: const Icon(Icons.info),
              onPressed: () => _showServiceStatus(),
              tooltip: 'Servis Durumu',
            ),
          ],
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
            tooltip: 'Çıkış Yap',
          ),
        ],
      ),
      body: Column(
        children: [
          // Servis durumu kartı (her zaman görünür)
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
                  onPressed: () => _showServiceStatus(),
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
          // Harita
          SizedBox(
            height: 200,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: selectionService.hasSelectedElderly
                  ? _currentPosition == null
                      ? Center(child: _locationStatus.isNotEmpty ? Text(_locationStatus) : const CircularProgressIndicator())
                      : FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            center: _currentPosition!,
                            zoom: 15.0,
                            minZoom: 10.0,
                            maxZoom: 18.0,
                            onMapReady: () {
                              print('Ana ekran haritası hazır');
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
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: _currentPosition!,
                                  width: 40,
                                  height: 40,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 2),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.3),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.location_on,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (_geofenceCenter != null && _geofenceRadius != null)
                              CircleLayer(
                                circles: [
                                  CircleMarker(
                                    point: _geofenceCenter!,
                                    color: Colors.green.withOpacity(0.2),
                                    borderStrokeWidth: 2,
                                    borderColor: Colors.green,
                                    radius: _geofenceRadius!,
                                  ),
                                ],
                              ),
                          ],
                        )
                  : Container(
                      color: Colors.grey[200],
                      child: const Center(
                        child: Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Text(
                            'Haritayı görüntülemek için lütfen "Yaşlı Kişiler" listesinden birini seçin.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          // Mavi konuma git kartı
          if (selectionService.hasSelectedElderly && _currentPosition != null)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              padding: const EdgeInsets.all(16),
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
                          '${selectionService.selectedElderlyName} Konumu',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Enlem: ${_currentPosition!.latitude.toStringAsFixed(6)}\nBoylam: ${_currentPosition!.longitude.toStringAsFixed(6)}',
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      _mapController.move(_currentPosition!, 15.0);
                    },
                    icon: const Icon(Icons.my_location, color: Colors.blue),
                    tooltip: 'Konuma Git',
                  ),
                ],
              ),
            ),
          // Diğer içerikler (scrollable)
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (widget.deviceRole == 'family') ...[
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 1.1,
                      children: [
                        _buildQuickAccessCard(
                          icon: Icons.people,
                          title: 'Yaşlılar',
                          subtitle: 'Liste',
                          color: Colors.orange,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const ElderlyListScreen()),
                          ),
                        ),
                        _buildQuickAccessCard(
                          icon: Icons.family_restroom,
                          title: 'Aile Paneli',
                          subtitle: 'Detaylar',
                          color: Colors.purple,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const FamilyPanelScreen()),
                          ),
                        ),
                        _buildQuickAccessCard(
                          icon: Icons.location_on,
                          title: 'Güvenli Alan',
                          subtitle: 'Alan',
                          color: Colors.green,
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const GeofenceScreen()),
                            );
                            _loadGeofenceForSelectedElderly();
                          },
                        ),
                        _buildQuickAccessCard(
                          icon: Icons.settings,
                          title: 'Ayarlar',
                          subtitle: 'Uygulama',
                          color: Colors.grey,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const SettingsScreen()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                  // Durum Kartları
                  if (widget.deviceRole == 'family' && selectionService.hasSelectedElderly) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.green.shade700, size: 24),
                              const SizedBox(width: 8),
                              Text(
                                'Durum Bilgileri',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatusCard(
                                  icon: Icons.location_on,
                                  title: 'Konum',
                                  value: _elderlyLocationEnabled == null
                                      ? 'Bilinmiyor'
                                      : (_elderlyLocationEnabled! ? 'Aktif' : 'Kapalı'),
                                  color: _elderlyLocationEnabled == null
                                      ? Colors.grey
                                      : (_elderlyLocationEnabled! ? Colors.green : Colors.red),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildStatusCard(
                                  icon: Icons.location_searching,
                                  title: 'Güvenli Alan',
                                  value: _geofenceCenter != null ? 'Aktif' : 'Pasif',
                                  color: _geofenceCenter != null ? Colors.green : Colors.orange,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (widget.deviceRole == 'elderly') ...[
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
                            onPressed: () => _showServiceStatus(),
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
                  ],
                  _buildSilentModeCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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

  @override
  void dispose() {
    _locationUpdateTimer?.cancel();
    _batteryStateSubscription?.cancel();
    _voiceMessageSubscription?.cancel();
    _inactivityTimer?.cancel();
    _audioPlayer.dispose();
    _envRecorder.dispose();
    _listenRequestSubscription?.cancel();
    _locationServiceStatusSub?.cancel();
    _locationStatusSubscription?.cancel();
    _elderlyLocationSubscription?.cancel();
    _silentModeTimer?.cancel();
    super.dispose();
  }

  // Hızlı erişim kartı widget'ı
  Widget _buildQuickAccessCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: color.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Durum kartı widget'ı
  Widget _buildStatusCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSilentModeCard() {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _isSilent ? Colors.orange.shade50 : Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _isSilent ? Colors.orange.shade200 : Colors.green.shade200),
      ),
      child: Row(
        children: [
          Icon(
            _isSilent ? Icons.volume_off : Icons.volume_up,
            color: _isSilent ? Colors.orange : Colors.green,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _isSilent
                  ? 'Telefon sessiz modda! Aile bireyleri sizi aradığında ulaşamayabilir.'
                  : 'Telefonunuzun sesi açık. Bildirimler ve aramalar ulaşabilir.',
              style: TextStyle(
                fontSize: 14,
                color: _isSilent ? Colors.orange : Colors.green,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  // Servis durumunu göster
  void _showServiceStatus() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Arka Plan Servisi Durumu'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cihaz ID: ${_deviceId ?? 'Bilinmiyor'}'),
              const SizedBox(height: 8),
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


} 