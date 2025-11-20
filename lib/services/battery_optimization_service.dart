import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:geolocator/geolocator.dart';
import '../services/cache_service.dart';

class BatteryOptimizationService {
  static final BatteryOptimizationService _instance = BatteryOptimizationService._internal();
  factory BatteryOptimizationService() => _instance;
  BatteryOptimizationService._internal();

  final Battery _battery = Battery();
  final CacheService _cacheService = CacheService();
  
  StreamSubscription<BatteryState>? _batterySubscription;
  Timer? _optimizationTimer;
  
  // Batarya seviyelerine göre ayarlar
  static const int _criticalBatteryLevel = 10;
  static const int _lowBatteryLevel = 20;
  static const int _mediumBatteryLevel = 50;
  
  // Konum güncelleme aralıkları (milisaniye)
  static const int _normalLocationInterval = 30000; // 30 saniye
  static const int _mediumBatteryLocationInterval = 60000; // 1 dakika
  static const int _lowBatteryLocationInterval = 120000; // 2 dakika
  static const int _criticalBatteryLocationInterval = 300000; // 5 dakika
  
  // Arka plan işlem aralıkları
  static const int _normalBackgroundInterval = 60000; // 1 dakika
  static const int _lowBatteryBackgroundInterval = 300000; // 5 dakika
  static const int _criticalBatteryBackgroundInterval = 600000; // 10 dakika
  
  int _currentBatteryLevel = 100;
  BatteryState _currentBatteryState = BatteryState.unknown;
  bool _isOptimizationEnabled = true;
  
  // Callback'ler
  Function(int)? _onLocationIntervalChanged;
  Function(int)? _onBackgroundIntervalChanged;
  Function(bool)? _onBatteryOptimizationChanged;

  Future<void> initialize() async {
    await _startBatteryMonitoring();
    await _loadBatterySettings();
  }

  Future<void> _startBatteryMonitoring() async {
    try {
    // Mevcut batarya durumunu al
    _currentBatteryLevel = await _battery.batteryLevel;
    _currentBatteryState = await _battery.batteryState;
    
      // Batarya durumu değişikliklerini dinle - daha az sıklıkta
      _batterySubscription = _battery.onBatteryStateChanged.listen(
        (BatteryState state) async {
          try {
      final newBatteryLevel = await _battery.batteryLevel;
      
      if (newBatteryLevel != _currentBatteryLevel || state != _currentBatteryState) {
        _currentBatteryLevel = newBatteryLevel;
        _currentBatteryState = state;
        
        // Batarya durumu değiştiğinde optimizasyonu güncelle
        await _updateOptimizationSettings();
        
        // Batarya verisini önbellekle
        await _cacheService.cacheBatteryData(_currentBatteryLevel, state.toString());
      }
          } catch (e) {
            // Battery plus hatası durumunda sessizce devam et
            print('Battery monitoring hatası: $e');
          }
        },
        onError: (error) {
          // Stream hatası durumunda sessizce devam et
          print('Battery stream hatası: $error');
        },
      );
    
      // Periyodik optimizasyon kontrolü - daha az sıklıkta
      _optimizationTimer = Timer.periodic(const Duration(minutes: 10), (timer) {
      _updateOptimizationSettings();
    });
    } catch (e) {
      print('Battery monitoring başlatılamadı: $e');
    }
  }

  Future<void> _loadBatterySettings() async {
    // Kullanıcı ayarlarını yükle
    final cachedSettings = await _cacheService.getCachedSettings();
    if (cachedSettings != null) {
      final settings = cachedSettings['settings'] as Map<String, dynamic>?;
      if (settings != null) {
        _isOptimizationEnabled = settings['batteryOptimization'] ?? true;
      }
    }
  }

  Future<void> _updateOptimizationSettings() async {
    if (!_isOptimizationEnabled) return;
    
    final newLocationInterval = _getOptimalLocationInterval();
    final newBackgroundInterval = _getOptimalBackgroundInterval();
    final shouldReduceProcessing = _shouldReduceProcessing();
    
    // Callback'leri çağır
    _onLocationIntervalChanged?.call(newLocationInterval);
    _onBackgroundIntervalChanged?.call(newBackgroundInterval);
    _onBatteryOptimizationChanged?.call(shouldReduceProcessing);
    
    // Optimizasyon ayarlarını kaydet
    await _saveOptimizationSettings(newLocationInterval, newBackgroundInterval, shouldReduceProcessing);
  }

  int _getOptimalLocationInterval() {
    if (_currentBatteryLevel <= _criticalBatteryLevel) {
      return _criticalBatteryLocationInterval;
    } else if (_currentBatteryLevel <= _lowBatteryLevel) {
      return _lowBatteryLocationInterval;
    } else if (_currentBatteryLevel <= _mediumBatteryLevel) {
      return _mediumBatteryLocationInterval;
    } else {
      return _normalLocationInterval;
    }
  }

  int _getOptimalBackgroundInterval() {
    if (_currentBatteryLevel <= _criticalBatteryLevel) {
      return _criticalBatteryBackgroundInterval;
    } else if (_currentBatteryLevel <= _lowBatteryLevel) {
      return _lowBatteryBackgroundInterval;
    } else {
      return _normalBackgroundInterval;
    }
  }

  bool _shouldReduceProcessing() {
    return _currentBatteryLevel <= _lowBatteryLevel;
  }

  Future<void> _saveOptimizationSettings(int locationInterval, int backgroundInterval, bool reduceProcessing) async {
    final settings = {
      'locationInterval': locationInterval,
      'backgroundInterval': backgroundInterval,
      'reduceProcessing': reduceProcessing,
      'batteryLevel': _currentBatteryLevel,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    
    await _cacheService.cacheSettings(settings);
  }

  // Konum servisi ayarlarını optimize et
  LocationSettings getOptimizedLocationSettings() {
    final accuracy = _getOptimalLocationAccuracy();
    final distanceFilter = _getOptimalDistanceFilter();
    
    return LocationSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilter,
      timeLimit: Duration(milliseconds: _getOptimalLocationInterval()),
    );
  }

  LocationAccuracy _getOptimalLocationAccuracy() {
    if (_currentBatteryLevel <= _criticalBatteryLevel) {
      return LocationAccuracy.low;
    } else if (_currentBatteryLevel <= _lowBatteryLevel) {
      return LocationAccuracy.medium;
    } else {
      return LocationAccuracy.high;
    }
  }

  int _getOptimalDistanceFilter() {
    if (_currentBatteryLevel <= _criticalBatteryLevel) {
      return 100; // 100 metre
    } else if (_currentBatteryLevel <= _lowBatteryLevel) {
      return 50; // 50 metre
    } else {
      return 10; // 10 metre
    }
  }

  // Arka plan işlemlerini optimize et
  bool shouldProcessInBackground() {
    if (_currentBatteryLevel <= _criticalBatteryLevel) {
      return false; // Kritik batarya seviyesinde arka plan işlemlerini durdur
    }
    return true;
  }

  // Ses dinleme işlemlerini optimize et
  bool shouldListenToAudio() {
    if (_currentBatteryLevel <= _criticalBatteryLevel) {
      return false; // Kritik batarya seviyesinde ses dinlemeyi durdur
    } else if (_currentBatteryLevel <= _lowBatteryLevel) {
      return true; // Düşük batarya seviyesinde sınırlı dinleme
    }
    return true; // Normal seviyede tam dinleme
  }

  // Firebase dinleme sıklığını optimize et
  int getOptimalFirebaseListenInterval() {
    if (_currentBatteryLevel <= _criticalBatteryLevel) {
      return 300000; // 5 dakika
    } else if (_currentBatteryLevel <= _lowBatteryLevel) {
      return 120000; // 2 dakika
    } else {
      return 60000; // 1 dakika
    }
  }

  // Bildirim sıklığını optimize et
  bool shouldSendNotification(String notificationType) {
    if (_currentBatteryLevel <= _criticalBatteryLevel) {
      // Kritik batarya seviyesinde sadece SOS bildirimleri
      return notificationType == 'sos';
    } else if (_currentBatteryLevel <= _lowBatteryLevel) {
      // Düşük batarya seviyesinde önemli bildirimler
      return ['sos', 'location_update', 'geofence'].contains(notificationType);
    }
    return true; // Normal seviyede tüm bildirimler
  }

  // Ağ kullanımını optimize et
  bool shouldUseNetwork() {
    if (_currentBatteryLevel <= _criticalBatteryLevel) {
      return false; // Kritik seviyede ağ kullanımını durdur
    } else if (_currentBatteryLevel <= _lowBatteryLevel) {
      return true; // Düşük seviyede sınırlı kullanım
    }
    return true; // Normal seviyede tam kullanım
  }

  // Optimizasyon ayarlarını değiştir
  Future<void> setOptimizationEnabled(bool enabled) async {
    _isOptimizationEnabled = enabled;
    
    if (enabled) {
      await _updateOptimizationSettings();
    } else {
      // Optimizasyonu devre dışı bırak - normal ayarları kullan
      _onLocationIntervalChanged?.call(_normalLocationInterval);
      _onBackgroundIntervalChanged?.call(_normalBackgroundInterval);
      _onBatteryOptimizationChanged?.call(false);
    }
  }

  // Callback'leri ayarla
  void setLocationIntervalCallback(Function(int) callback) {
    _onLocationIntervalChanged = callback;
  }

  void setBackgroundIntervalCallback(Function(int) callback) {
    _onBackgroundIntervalChanged = callback;
  }

  void setBatteryOptimizationCallback(Function(bool) callback) {
    _onBatteryOptimizationChanged = callback;
  }

  // Mevcut durumu al
  Map<String, dynamic> getCurrentStatus() {
    return {
      'batteryLevel': _currentBatteryLevel,
      'batteryState': _currentBatteryState.toString(),
      'isOptimizationEnabled': _isOptimizationEnabled,
      'locationInterval': _getOptimalLocationInterval(),
      'backgroundInterval': _getOptimalBackgroundInterval(),
      'shouldReduceProcessing': _shouldReduceProcessing(),
      'locationAccuracy': _getOptimalLocationAccuracy().toString(),
      'distanceFilter': _getOptimalDistanceFilter(),
    };
  }

  // Optimizasyon istatistikleri
  Map<String, dynamic> getOptimizationStats() {
    return {
      'currentBatteryLevel': _currentBatteryLevel,
      'currentBatteryState': _currentBatteryState.toString(),
      'isOptimizationEnabled': _isOptimizationEnabled,
      'locationInterval': _getOptimalLocationInterval(),
      'backgroundInterval': _getOptimalBackgroundInterval(),
      'locationAccuracy': _getOptimalLocationAccuracy().toString(),
      'distanceFilter': _getOptimalDistanceFilter(),
      'shouldProcessInBackground': shouldProcessInBackground(),
      'shouldUseNetwork': shouldUseNetwork(),
    };
  }

  // Servisi temizle
  void dispose() {
    try {
    _batterySubscription?.cancel();
    _optimizationTimer?.cancel();
      _batterySubscription = null;
      _optimizationTimer = null;
    } catch (e) {
      print('Battery service dispose hatası: $e');
    }
  }
} 