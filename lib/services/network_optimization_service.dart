import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:firebase_database/firebase_database.dart';
import 'package:latlong2/latlong.dart';
import '../services/cache_service.dart';
import '../services/battery_optimization_service.dart';

class NetworkOptimizationService {
  static final NetworkOptimizationService _instance = NetworkOptimizationService._internal();
  factory NetworkOptimizationService() => _instance;
  NetworkOptimizationService._internal();

  final CacheService _cacheService = CacheService();
  final BatteryOptimizationService _batteryService = BatteryOptimizationService();
  
  // Ağ kullanım istatistikleri
  int _totalRequests = 0;
  int _cachedRequests = 0;
  int _batchedRequests = 0;
  int _totalDataSent = 0;
  int _totalDataReceived = 0;
  
  // İstek önbelleği
  final Map<String, dynamic> _requestCache = {};
  final Map<String, int> _requestTimestamps = {};
  static const int _requestCacheDuration = 30000; // 30 saniye
  
  // Toplu işlem kuyruğu
  final List<Map<String, dynamic>> _batchQueue = [];
  Timer? _batchTimer;
  static const int _batchInterval = 5000; // 5 saniye
  static const int _maxBatchSize = 10;
  
  // Ağ durumu
  bool _isNetworkAvailable = true;
  bool _isLowBandwidth = false;
  
  // Firebase referansları
  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  Future<void> initialize() async {
    await _startBatchProcessing();
    await _loadNetworkSettings();
  }

  Future<void> _startBatchProcessing() async {
    _batchTimer = Timer.periodic(Duration(milliseconds: _batchInterval), (timer) {
      _processBatchQueue();
    });
  }

  Future<void> _loadNetworkSettings() async {
    final cachedSettings = await _cacheService.getCachedSettings();
    if (cachedSettings != null) {
      final settings = cachedSettings['settings'] as Map<String, dynamic>?;
      if (settings != null) {
        _isLowBandwidth = settings['lowBandwidthMode'] ?? false;
      }
    }
  }

  // Konum verisi gönderme (optimize edilmiş)
  Future<void> sendLocationData(String elderlyId, Map<String, dynamic> locationData) async {
    if (!_batteryService.shouldUseNetwork()) {
      // Batarya kritik seviyede, veriyi önbellekle
      await _cacheService.cacheLocationData(
        elderlyId,
        locationData['latitude'],
        locationData,
      );
      return;
    }

    // Önbellekteki veriyi kontrol et
    final cachedData = await _cacheService.getCachedLocationData(elderlyId);
    if (cachedData != null) {
      final cachedLocation = LatLng(
        cachedData['latitude'] as double,
        cachedData['longitude'] as double,
      );
      final newLocation = LatLng(
        locationData['latitude'] as double,
        locationData['longitude'] as double,
      );
      
      // Konum değişikliği çok küçükse gönderme
      final distance = _calculateDistance(cachedLocation, newLocation);
      if (distance < 10) { // 10 metreden az değişiklik
        _cachedRequests++;
        return;
      }
    }

    // Veriyi önbellekle
    await _cacheService.cacheLocationData(
      elderlyId,
      locationData['latitude'],
      locationData,
    );

    // Toplu işlem kuyruğuna ekle
    _addToBatchQueue('location', elderlyId, locationData);
  }

  // Acil durum verisi gönderme (öncelikli)
  Future<void> sendEmergencyData(String elderlyId, Map<String, dynamic> emergencyData) async {
    // Acil durum verileri her zaman hemen gönderilir
    try {
      await _database
          .child('emergency_alerts')
          .child(elderlyId)
          .child(DateTime.now().millisecondsSinceEpoch.toString())
          .set(emergencyData);
      
      _totalRequests++;
      _totalDataSent += jsonEncode(emergencyData).length;
    } catch (e) {
      // Hata durumunda önbellekle
      await _cacheService.cacheLocationData(
        elderlyId,
        emergencyData['latitude'],
        emergencyData,
      );
    }
  }

  // Veri okuma (önbellekli)
  Future<Map<String, dynamic>?> getData(String path) async {
    final cacheKey = 'data_$path';
    
    // Önbellekteki veriyi kontrol et
    if (_requestCache.containsKey(cacheKey)) {
      final timestamp = _requestTimestamps[cacheKey] ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - timestamp < _requestCacheDuration) {
        _cachedRequests++;
        return _requestCache[cacheKey];
      } else {
        _requestCache.remove(cacheKey);
        _requestTimestamps.remove(cacheKey);
      }
    }

    // Ağdan veri al
    try {
      final snapshot = await _database.child(path).get();
      if (snapshot.value != null) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        
        // Önbellekle
        _requestCache[cacheKey] = data;
        _requestTimestamps[cacheKey] = DateTime.now().millisecondsSinceEpoch;
        
        _totalRequests++;
        _totalDataReceived += jsonEncode(data).length;
        
        return data;
      }
    } catch (e) {
      // Hata durumunda önbellekteki veriyi döndür
      return _requestCache[cacheKey];
    }

    return null;
  }

  // Toplu işlem kuyruğuna ekle
  void _addToBatchQueue(String type, String elderlyId, Map<String, dynamic> data) {
    _batchQueue.add({
      'type': type,
      'elderlyId': elderlyId,
      'data': data,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    // Kuyruk dolduğunda hemen işle
    if (_batchQueue.length >= _maxBatchSize) {
      _processBatchQueue();
    }
  }

  // Toplu işlem kuyruğunu işle
  Future<void> _processBatchQueue() async {
    if (_batchQueue.isEmpty) return;

    final batch = List<Map<String, dynamic>>.from(_batchQueue);
    _batchQueue.clear();

    // Veri türlerine göre grupla
    final locationData = <String, List<Map<String, dynamic>>>{};
    
    for (final item in batch) {
      if (item['type'] == 'location') {
        final elderlyId = item['elderlyId'] as String;
        if (!locationData.containsKey(elderlyId)) {
          locationData[elderlyId] = [];
        }
        locationData[elderlyId]!.add(item['data'] as Map<String, dynamic>);
      }
    }

    // Toplu gönderim
    try {
      final updates = <String, dynamic>{};
      
      for (final entry in locationData.entries) {
        final elderlyId = entry.key;
        final locations = entry.value;
        
        // En son konumu gönder
        if (locations.isNotEmpty) {
          final latestLocation = locations.last;
          updates['locations/$elderlyId/current_location'] = latestLocation;
          
          // Konum geçmişini de ekle (sınırlı)
          if (locations.length > 1) {
            final history = locations.take(5).toList(); // Son 5 konum
            updates['locations/$elderlyId/history'] = history;
          }
        }
      }

      if (updates.isNotEmpty) {
        await _database.update(updates);
        _batchedRequests++;
        _totalDataSent += jsonEncode(updates).length;
      }
    } catch (e) {
      // Hata durumunda verileri tekrar kuyruğa ekle
      for (final item in batch) {
        _addToBatchQueue(item['type'], item['elderlyId'], item['data']);
      }
    }
  }

  // Mesafe hesaplama
  double _calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371000; // metre
    
    final lat1Rad = point1.latitude * (pi / 180);
    final lat2Rad = point2.latitude * (pi / 180);
    final deltaLat = (point2.latitude - point1.latitude) * (pi / 180);
    final deltaLng = (point2.longitude - point1.longitude) * (pi / 180);
    
    final a = sin(deltaLat / 2) * sin(deltaLat / 2) +
        cos(lat1Rad) * cos(lat2Rad) * sin(deltaLng / 2) * sin(deltaLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    
    return earthRadius * c;
  }

  // Ağ durumunu ayarla
  void setNetworkStatus(bool isAvailable, {bool isLowBandwidth = false}) {
    _isNetworkAvailable = isAvailable;
    _isLowBandwidth = isLowBandwidth;
  }

  // Önbellek temizleme
  Future<void> clearCache() async {
    _requestCache.clear();
    _requestTimestamps.clear();
    await _cacheService.clearCache();
  }

  // Ağ kullanım istatistikleri
  Map<String, dynamic> getNetworkStats() {
    return {
      'totalRequests': _totalRequests,
      'cachedRequests': _cachedRequests,
      'batchedRequests': _batchedRequests,
      'totalDataSent': _totalDataSent,
      'totalDataReceived': _totalDataReceived,
      'cacheHitRate': _totalRequests > 0 ? (_cachedRequests / _totalRequests) * 100 : 0,
      'batchEfficiency': _totalRequests > 0 ? (_batchedRequests / _totalRequests) * 100 : 0,
      'isNetworkAvailable': _isNetworkAvailable,
      'isLowBandwidth': _isLowBandwidth,
      'batchQueueSize': _batchQueue.length,
    };
  }

  // Performans optimizasyonu
  Future<void> optimizePerformance() async {
    // Eski önbellek verilerini temizle
    final now = DateTime.now().millisecondsSinceEpoch;
    final keysToRemove = <String>[];
    
    for (final entry in _requestTimestamps.entries) {
      if (now - entry.value > _requestCacheDuration) {
        keysToRemove.add(entry.key);
      }
    }
    
    for (final key in keysToRemove) {
      _requestCache.remove(key);
      _requestTimestamps.remove(key);
    }
    
    // Bellek kullanımını optimize et
    _cacheService.optimizeMemoryUsage();
  }

  // Servisi temizle
  void dispose() {
    _batchTimer?.cancel();
    _processBatchQueue(); // Kalan verileri işle
  }
} 