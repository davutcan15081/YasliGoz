import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:math';
import 'package:provider/provider.dart';
import '../services/elderly_selection_service.dart';
import 'dart:async';
import '../services/notification_service.dart';
import '../services/premium_service.dart';
import 'premium_screen.dart';

class GeofenceScreen extends StatefulWidget {
  const GeofenceScreen({super.key});

  @override
  State<GeofenceScreen> createState() => _GeofenceScreenState();
}

class _GeofenceScreenState extends State<GeofenceScreen> {
  MapController? _mapController;
  LatLng? _center;
  double _radius = 200; // metre
  LatLng? _currentPosition;
  bool _isOutside = false;
  String? _elderlyId;
  String? _elderlyName;
  StreamSubscription<DatabaseEvent>? _locationSubscription;
  bool _mapCenteredOnce = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkPremium();
    _mapController = MapController();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _mapController?.dispose();
    _mapController = null;
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final selectionService = Provider.of<ElderlySelectionService>(context);
    print('[GÜVENLI ALAN] didChangeDependencies çağrıldı');
    print('[GÜVENLI ALAN] hasSelectedElderly: ${selectionService.hasSelectedElderly}');
    print('[GÜVENLI ALAN] selectedElderly: ${selectionService.selectedElderly}');
    
    if (selectionService.hasSelectedElderly) {
      _elderlyId = selectionService.selectedElderly?.id ?? 'user1';
      _elderlyName = selectionService.selectedElderly?.name ?? '';
      print('[GÜVENLI ALAN] Yaşlı seçildi - ID: $_elderlyId, Name: $_elderlyName');
      print('[GÜVENLI ALAN] DeviceId: ${selectionService.selectedElderly?.deviceId}');
      _loadGeofence();
      _listenToElderlyPosition();
    } else {
      _elderlyId = null;
      _elderlyName = null;
      print('[GÜVENLI ALAN] Yaşlı seçimi kaldırıldı');
      _locationSubscription?.cancel();
    }
  }

  Future<void> _checkPremium() async {
    final isPremium = await PremiumService.isUserPremium();
    if (isPremium == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Premium durumu doğrulanamadı. Lütfen internet bağlantınızı kontrol edin.')),
        );
      }
      return;
    }
    if (!isPremium && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const PremiumScreen()),
      );
    }
  }

  void _listenToElderlyPosition() {
    _locationSubscription?.cancel();
    _mapCenteredOnce = false;
    
    // Seçili yaşlının deviceId'si ile dinle
    final selectionService = Provider.of<ElderlySelectionService>(context, listen: false);
    final selectedElderly = selectionService.selectedElderly;
    
    if (selectedElderly == null || selectedElderly.deviceId == null) {
      print('[GÜVENLI ALAN] Seçili yaşlı veya deviceId bulunamadı');
      print('[GÜVENLI ALAN] selectedElderly: $selectedElderly');
      print('[GÜVENLI ALAN] deviceId: ${selectedElderly?.deviceId}');
      return;
    }
    
    String deviceId = selectedElderly.deviceId!.replaceAll(RegExp(r'[.#$\[\]]'), '_');
    final dbRef = FirebaseDatabase.instance.ref('locations/$deviceId');
    print('[GÜVENLI ALAN] Firebase yolu: locations/$deviceId');
    print('[GÜVENLI ALAN] Seçili yaşlı: ${selectedElderly.name}');
    print('[GÜVENLI ALAN] Orijinal deviceId: ${selectedElderly.deviceId}');
    print('[GÜVENLI ALAN] Temizlenmiş deviceId: $deviceId');
    
    _locationSubscription = dbRef.onValue.listen((event) {
      print('[GÜVENLI ALAN] Firebase event alındı: ${event.snapshot.value}');
      print('[GÜVENLI ALAN] Event data tipi: ${event.snapshot.value.runtimeType}');
      final data = event.snapshot.value;
      Map<String, dynamic>? locationData;
      
      if (data is Map) {
        print('[GÜVENLI ALAN] Data Map tipinde, anahtarlar: ${data.keys.toList()}');
        // Doğrudan konum verisi
        if (data['latitude'] != null && data['longitude'] != null) {
          locationData = Map<String, dynamic>.from(data);
          print('[GÜVENLI ALAN] Doğrudan konum verisi bulundu');
        }
        // current_location altında konum verisi
        else if (data['current_location'] != null && data['current_location'] is Map) {
          final currentLocation = data['current_location'] as Map;
          print('[GÜVENLI ALAN] current_location altında veri var: $currentLocation');
          if (currentLocation['latitude'] != null && currentLocation['longitude'] != null) {
            locationData = Map<String, dynamic>.from(currentLocation);
            print('[GÜVENLI ALAN] current_location altında konum verisi bulundu');
          }
        }
      } else {
        print('[GÜVENLI ALAN] Data Map tipinde değil: ${data.runtimeType}');
      }
      
      if (locationData != null) {
        print('[GÜVENLI ALAN] Konum verisi bulundu: $locationData');
        final pos = LatLng(
          (locationData['latitude'] as num).toDouble(),
          (locationData['longitude'] as num).toDouble(),
        );
        
        if (mounted) {
          setState(() {
            _currentPosition = pos;
          });
          
          if (!_mapCenteredOnce) {
            _mapController?.move(pos, 15);
            _mapCenteredOnce = true;
          }
          
          // Güvenli alan kontrolü yap
          _checkIfOutside();
        }
      } else {
        print('[GÜVENLI ALAN] Konum verisi bulunamadı! deviceId: $deviceId');
        print('[GÜVENLI ALAN] Data içeriği: $data');
      }
    }, onError: (error) {
      print('[GÜVENLI ALAN] Konum dinleme hatası: $error');
    });
  }

  Future<void> _loadGeofence() async {
    if (_elderlyId == null) return;
    
    try {
      final dbRef = FirebaseDatabase.instance.ref('geofence/$_elderlyId');
      final snapshot = await dbRef.get();
      
      if (snapshot.exists && snapshot.value != null && snapshot.value is Map) {
        final data = snapshot.value as Map;
        final center = LatLng((data['lat'] as num).toDouble(), (data['lng'] as num).toDouble());
        
        if (mounted) {
          setState(() {
            _center = center;
            _radius = (data['radius'] as num).toDouble();
          });
          
          // Eğer yaşlının konumu yoksa haritayı güvenli alan merkezine odakla
          if (_currentPosition == null) {
            _mapController?.move(center, 15);
          }
          
          _checkIfOutside();
        }
      } else {
        print('Güvenli Alan - Kayıtlı güvenli alan bulunamadı');
      }
    } catch (e) {
      print('Güvenli Alan - Güvenli alan yükleme hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Güvenli alan verisi alınamadı: $e')),
        );
      }
    }
  }

  Future<void> _saveGeofence() async {
    if (_center == null || _elderlyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Önce haritada bir nokta seçin!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      final dbRef = FirebaseDatabase.instance.ref('geofence/$_elderlyId');
      await dbRef.set({
        'lat': _center!.latitude,
        'lng': _center!.longitude,
        'radius': _radius,
        'created_at': DateTime.now().toIso8601String(),
        'elderly_name': _elderlyName,
      });
      
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Güvenli alan başarıyla kaydedildi!\nMerkez: ${_center!.latitude.toStringAsFixed(6)}, ${_center!.longitude.toStringAsFixed(6)}\nYarıçap: ${_radius.toInt()}m'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('Güvenli Alan - Kaydetme hatası: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Güvenli alan kaydedilemedi: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onMapTap(LatLng pos) {
    // Eğer zaten bir merkez seçiliyse onay iste
    if (_center != null) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Güvenli Alan Merkezi Değiştir'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Zaten bir güvenli alan merkezi seçili.'),
                const SizedBox(height: 8),
                Text(
                  'Mevcut: ${_center!.latitude.toStringAsFixed(6)}, ${_center!.longitude.toStringAsFixed(6)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Text(
                  'Yeni: ${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}',
                  style: const TextStyle(fontSize: 12, color: Colors.blue),
                ),
                const SizedBox(height: 8),
                const Text('Merkezi değiştirmek istiyor musunuz?'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('İptal'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _updateGeofenceCenter(pos);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Değiştir'),
              ),
            ],
          );
        },
      );
    } else {
      // İlk kez seçiliyorsa direkt güncelle
      _updateGeofenceCenter(pos);
    }
  }

  void _updateGeofenceCenter(LatLng pos) {
    setState(() {
      _center = pos;
    });
    
    // Kullanıcıya geri bildirim ver
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Güvenli alan merkezi seçildi!\nEnlem: ${pos.latitude.toStringAsFixed(6)}\nBoylam: ${pos.longitude.toStringAsFixed(6)}'),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 2),
      ),
    );
    
    _checkIfOutside();
  }

  void _checkIfOutside() async {
    if (_center == null || _currentPosition == null) return;
    
    double distance = _calculateDistance(
      _center!.latitude,
      _center!.longitude,
      _currentPosition!.latitude,
      _currentPosition!.longitude,
    );
    
    final wasOutside = _isOutside;
    setState(() {
      _isOutside = distance > _radius;
    });
    
    // Eğer yeni dışarı çıktıysa bildirim ve backend kaydı yap
    if (_isOutside && !wasOutside) {
      print('Güvenli Alan - Kişi güvenli alanın dışına çıktı');
      // Bildirim gönder
      final notificationService = Provider.of<NotificationService>(context, listen: false);
      await notificationService.showGeofenceNotification(_elderlyName ?? 'Takip edilen kişi', 'exit', 'Güvenli Alan');
      
      // Backend kaydı
      if (_elderlyId != null) {
        final dbRef = FirebaseDatabase.instance.ref('geofence_events/$_elderlyId');
        await dbRef.push().set({
          'event': 'exit',
          'timestamp': DateTime.now().toIso8601String(),
          'lat': _currentPosition!.latitude,
          'lng': _currentPosition!.longitude,
          'distance': distance,
        });
      }
    } else if (!_isOutside && wasOutside) {
      print('Güvenli Alan - Kişi güvenli alana geri döndü');
      // İçeri giriş bildirimi ve backend kaydı
      final notificationService = Provider.of<NotificationService>(context, listen: false);
      await notificationService.showGeofenceNotification(_elderlyName ?? 'Takip edilen kişi', 'enter', 'Güvenli Alan');
      
      if (_elderlyId != null) {
        final dbRef = FirebaseDatabase.instance.ref('geofence_events/$_elderlyId');
        await dbRef.push().set({
          'event': 'enter',
          'timestamp': DateTime.now().toIso8601String(),
          'lat': _currentPosition!.latitude,
          'lng': _currentPosition!.longitude,
          'distance': distance,
        });
      }
    }
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double R = 6371000; // metre
    double dLat = _deg2rad(lat2 - lat1);
    double dLon = _deg2rad(lon2 - lon1);
    double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) * cos(_deg2rad(lat2)) *
            sin(dLon / 2) * sin(dLon / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _deg2rad(double deg) => deg * pi / 180;

  @override
  Widget build(BuildContext context) {
    if (_elderlyId == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Güvenli Alan'),
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_off, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Lütfen önce takip edilecek bir yaşlı seçin.',
                style: TextStyle(fontSize: 18, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Güvenli Alan'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          if (_center != null)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      title: const Text('Güvenli Alan Merkezini Temizle'),
                      content: const Text('Seçili güvenli alan merkezini kaldırmak istiyor musunuz?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('İptal'),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            setState(() {
                              _center = null;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Güvenli alan merkezi temizlendi'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Temizle'),
                        ),
                      ],
                    );
                  },
                );
              },
              tooltip: 'Merkezi Temizle',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  SizedBox(
                    height: 250,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: FlutterMap(
                        mapController: _mapController!,
                        options: MapOptions(
                          center: _currentPosition ?? _center ?? LatLng(39.92, 32.85),
                          zoom: 15.0,
                          minZoom: 10.0,
                          maxZoom: 18.0,
                          onTap: (tapPosition, point) => _onMapTap(point),
                          onMapReady: () {
                            print('Güvenli alan haritası hazır');
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
                          if (_center != null)
                            CircleLayer(
                              circles: [
                                CircleMarker(
                                  point: _center!,
                                  color: Colors.green.withOpacity(0.2),
                                  borderStrokeWidth: 2,
                                  borderColor: Colors.green,
                                  radius: _radius, // metre cinsinden
                                ),
                              ],
                            ),
                          MarkerLayer(
                            markers: [
                              if (_center != null)
                                Marker(
                                  point: _center!,
                                  width: 50,
                                  height: 50,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.green,
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
                                      size: 30,
                                    ),
                                  ),
                                ),
                              if (_currentPosition != null)
                                Marker(
                                  point: _currentPosition!,
                                  width: 40,
                                  height: 40,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.blue,
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
                                      Icons.person_pin_circle,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
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
                                '${_elderlyName ?? "Takip Edilen Kişi"} Konumu',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _currentPosition != null
                                    ? 'Enlem: ${_currentPosition!.latitude.toStringAsFixed(6)}\nBoylam: ${_currentPosition!.longitude.toStringAsFixed(6)}'
                                    : 'Konum alınamıyor',
                                style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: _currentPosition != null
                              ? () {
                                  _mapController?.move(_currentPosition!, 15.0);
                                }
                              : null,
                          icon: const Icon(Icons.my_location, color: Colors.blue),
                          tooltip: 'Konuma Git',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('Yarıçap:', style: TextStyle(fontSize: 18)),
                      Expanded(
                        child: Slider(
                          min: 50,
                          max: 1000,
                          divisions: 19,
                          value: _radius,
                          label: '${_radius.toInt()} m',
                          onChanged: (val) {
                            setState(() {
                              _radius = val;
                            });
                            _checkIfOutside();
                          },
                        ),
                      ),
                      Text('${_radius.toInt()} m', style: const TextStyle(fontSize: 18)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.save),
                      label: Text(_center == null ? 'Haritada Nokta Seçin' : 'Güvenli Alanı Kaydet'),
                      onPressed: _saveGeofence,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _center == null ? Colors.grey : Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  if (_center == null)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.orange, size: 16),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Güvenli alan kaydetmek için haritada bir noktaya dokunun',
                              style: TextStyle(fontSize: 12, color: Colors.orange),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (_isOutside)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.warning, color: Colors.red),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Dikkat! Güvenli alanın dışındasınız.',
                              style: TextStyle(fontSize: 16, color: Colors.red, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (!_isOutside && _center != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Güvenli alan içindesiniz.',
                              style: TextStyle(fontSize: 16, color: Colors.green, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
} 