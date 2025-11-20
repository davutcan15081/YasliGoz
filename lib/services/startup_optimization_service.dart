import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/cache_service.dart';
import '../services/battery_optimization_service.dart';
import '../services/network_optimization_service.dart';

class StartupOptimizationService {
  static final StartupOptimizationService _instance = StartupOptimizationService._internal();
  factory StartupOptimizationService() => _instance;
  StartupOptimizationService._internal();

  final CacheService _cacheService = CacheService();
  final BatteryOptimizationService _batteryService = BatteryOptimizationService();
  final NetworkOptimizationService _networkService = NetworkOptimizationService();
  
  // Başlatma durumu
  bool _isInitialized = false;
  final bool _isEssentialDataLoaded = false;
  
  // Başlatma süresi takibi
  final Stopwatch _startupTimer = Stopwatch();
  final List<String> _startupSteps = [];
  
  // Önceden yüklenecek veriler
  Map<String, dynamic>? _preloadedUserData;
  Map<String, dynamic>? _preloadedElderlyData;
  Map<String, dynamic>? _preloadedSettings;
  
  // Lazy loading için gerekli veriler
  final Set<String> _lazyLoadedData = <String>{};
  
  // Başlatma callback'leri
  Function(double)? _onProgressUpdate;
  Function(String)? _onStepComplete;
  Function()? _onStartupComplete;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    _startupTimer.start();
    _addStartupStep('Servis başlatma başladı');
    
    try {
      // 1. Temel servisleri başlat
      await _initializeCoreServices();
      _addStartupStep('Temel servisler başlatıldı');
      
      // 2. Önbellek verilerini yükle
      await _loadCachedData();
      _addStartupStep('Önbellek verileri yüklendi');
      
      // 3. Kullanıcı oturumunu kontrol et
      await _checkUserSession();
      _addStartupStep('Kullanıcı oturumu kontrol edildi');
      
      // 4. Gerekli verileri önceden yükle
      await _preloadEssentialData();
      _addStartupStep('Gerekli veriler önceden yüklendi');
      
      // 5. Performans optimizasyonlarını uygula
      await _applyPerformanceOptimizations();
      _addStartupStep('Performans optimizasyonları uygulandı');
      
      _isInitialized = true;
      _startupTimer.stop();
      
      _addStartupStep('Başlatma tamamlandı (${_startupTimer.elapsedMilliseconds}ms)');
      _onStartupComplete?.call();
      
    } catch (e) {
      _addStartupStep('Başlatma hatası: $e');
      rethrow;
    }
  }

  Future<void> _initializeCoreServices() async {
    // Cache servisini başlat
    await _cacheService.initialize();
    _updateProgress(0.2);
    
    // Batarya optimizasyon servisini başlat
    await _batteryService.initialize();
    _updateProgress(0.4);
    
    // Ağ optimizasyon servisini başlat
    await _networkService.initialize();
    _updateProgress(0.6);
  }

  Future<void> _loadCachedData() async {
    // Kullanıcı ayarlarını yükle
    _preloadedSettings = await _cacheService.getCachedSettings();
    _updateProgress(0.7);
    
    // Batarya verilerini yükle
    await _cacheService.getCachedBatteryData();
    _updateProgress(0.8);
  }

  Future<void> _checkUserSession() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // Kullanıcı giriş yapmış, temel verileri yükle
      await _loadUserData(user.uid);
    }
    _updateProgress(0.9);
  }

  Future<void> _loadUserData(String userId) async {
    try {
      // Kullanıcı verilerini önbellekten yükle
      _preloadedUserData = await _cacheService.getCachedElderlyData(userId);
      
      // Eğer önbellekte yoksa Firebase'den yükle
      if (_preloadedUserData == null) {
        final snapshot = await FirebaseDatabase.instance
            .ref('users/$userId')
            .get();
        
        if (snapshot.value != null) {
          final data = Map<String, dynamic>.from(snapshot.value as Map);
          _preloadedUserData = data;
          
          // Önbellekle
          await _cacheService.cacheElderlyData(userId, data);
        }
      }
    } catch (e) {
      // Hata durumunda varsayılan veriler kullan
      _preloadedUserData = {};
    }
  }

  Future<void> _preloadEssentialData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    try {
      // Yaşlı kişi listesini önceden yükle
      final elderlySnapshot = await FirebaseDatabase.instance
          .ref('elderly_people')
          .orderByChild('userId')
          .equalTo(user.uid)
          .limitToFirst(5) // İlk 5 kişiyi yükle
          .get();
      
      if (elderlySnapshot.value != null) {
        final elderlyData = Map<String, dynamic>.from(elderlySnapshot.value as Map);
        _preloadedElderlyData = elderlyData;
        
        // Her yaşlı kişi için temel verileri önbellekle
        for (final entry in elderlyData.entries) {
          final elderlyId = entry.key;
          final data = entry.value as Map<String, dynamic>;
          
          await _cacheService.cacheElderlyData(elderlyId, data);
          
          // Konum verilerini de önbellekle
          final locationData = await _cacheService.getCachedLocationData(elderlyId);
          if (locationData == null) {
            // Konum verisi yoksa Firebase'den al
            try {
              final locationSnapshot = await FirebaseDatabase.instance
                  .ref('locations/$elderlyId/current_location')
                  .get();
              
              if (locationSnapshot.value != null) {
                final location = Map<String, dynamic>.from(locationSnapshot.value as Map);
                await _cacheService.cacheLocationData(
                  elderlyId,
                  location['latitude'],
                  location,
                );
              }
            } catch (e) {
              // Konum verisi alınamadı, devam et
            }
          }
        }
      }
    } catch (e) {
      // Hata durumunda devam et
    }
  }

  Future<void> _applyPerformanceOptimizations() async {
    // Bellek kullanımını optimize et
    _cacheService.optimizeMemoryUsage();
    
    // Ağ performansını optimize et
    await _networkService.optimizePerformance();
    
    // Batarya optimizasyonlarını uygula
    final batteryStats = _batteryService.getOptimizationStats();
    if (batteryStats['shouldReduceProcessing'] == true) {
      // Düşük batarya modunda ek optimizasyonlar
    }
  }

  // Lazy loading - veri gerektiğinde yükle
  Future<Map<String, dynamic>?> getLazyLoadedData(String dataType, String id) async {
    final cacheKey = '${dataType}_$id';
    
    if (_lazyLoadedData.contains(cacheKey)) {
      // Zaten yüklenmiş
      return await _cacheService.getCachedElderlyData(id);
    }
    
    try {
      // Veriyi yükle
      final data = await _loadDataFromFirebase(dataType, id);
      
      if (data != null) {
        _lazyLoadedData.add(cacheKey);
        await _cacheService.cacheElderlyData(id, data);
      }
      
      return data;
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _loadDataFromFirebase(String dataType, String id) async {
    try {
      final snapshot = await FirebaseDatabase.instance
          .ref('$dataType/$id')
          .get();
      
      if (snapshot.value != null) {
        return Map<String, dynamic>.from(snapshot.value as Map);
      }
    } catch (e) {
      // Hata durumunda null döndür
    }
    
    return null;
  }

  // Başlatma durumunu kontrol et
  bool get isInitialized => _isInitialized;
  bool get isEssentialDataLoaded => _isEssentialDataLoaded;
  
  // Önceden yüklenen verileri al
  Map<String, dynamic>? get preloadedUserData => _preloadedUserData;
  Map<String, dynamic>? get preloadedElderlyData => _preloadedElderlyData;
  Map<String, dynamic>? get preloadedSettings => _preloadedSettings;
  
  // Başlatma istatistikleri
  Map<String, dynamic> getStartupStats() {
    return {
      'isInitialized': _isInitialized,
      'isEssentialDataLoaded': _isEssentialDataLoaded,
      'startupTime': _startupTimer.elapsedMilliseconds,
      'startupSteps': _startupSteps,
      'lazyLoadedDataCount': _lazyLoadedData.length,
      'preloadedDataCount': _preloadedElderlyData?.length ?? 0,
    };
  }

  // Progress callback'lerini ayarla
  void setProgressCallback(Function(double) callback) {
    _onProgressUpdate = callback;
  }

  void setStepCallback(Function(String) callback) {
    _onStepComplete = callback;
  }

  void setStartupCompleteCallback(Function() callback) {
    _onStartupComplete = callback;
  }

  void _updateProgress(double progress) {
    _onProgressUpdate?.call(progress);
  }

  void _addStartupStep(String step) {
    _startupSteps.add('${DateTime.now().millisecondsSinceEpoch}: $step');
    _onStepComplete?.call(step);
  }

  // Başlatma verilerini temizle
  Future<void> clearStartupData() async {
    _preloadedUserData = null;
    _preloadedElderlyData = null;
    _preloadedSettings = null;
    _lazyLoadedData.clear();
    _startupSteps.clear();
    _startupTimer.reset();
  }

  // Performans izleme
  void startPerformanceMonitoring() {
    // Performans metriklerini izlemeye başla
    Timer.periodic(const Duration(minutes: 5), (timer) {
      _monitorPerformance();
    });
  }

  void _monitorPerformance() {
    final cacheStats = _cacheService.getCacheStats();
    final batteryStats = _batteryService.getOptimizationStats();
    final networkStats = _networkService.getNetworkStats();
    
    // Performans metriklerini logla veya analitik servise gönder
    debugPrint('Performance Stats:');
    debugPrint('Cache: $cacheStats');
    debugPrint('Battery: $batteryStats');
    debugPrint('Network: $networkStats');
  }
} 