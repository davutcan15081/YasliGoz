import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';

class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  static const String _locationCacheKey = 'location_cache';
  static const String _batteryCacheKey = 'battery_cache';
  static const String _elderlyDataCacheKey = 'elderly_data_cache';
  static const String _settingsCacheKey = 'settings_cache';
  
  // Önbellek süreleri (milisaniye)
  static const int _locationCacheDuration = 30000; // 30 saniye
  static const int _batteryCacheDuration = 60000; // 1 dakika
  static const int _elderlyDataCacheDuration = 300000; // 5 dakika
  static const int _settingsCacheDuration = 3600000; // 1 saat

  late SharedPreferences _prefs;
  final Map<String, dynamic> _memoryCache = {};
  final Map<String, int> _cacheTimestamps = {};

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // Konum verisi önbellekleme
  Future<void> cacheLocationData(String elderlyId, LatLng location, Map<String, dynamic>? additionalData) async {
    final cacheData = {
      'latitude': location.latitude,
      'longitude': location.longitude,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'additionalData': additionalData,
    };

    // Bellek önbelleği
    _memoryCache['${_locationCacheKey}_$elderlyId'] = cacheData;
    _cacheTimestamps['${_locationCacheKey}_$elderlyId'] = DateTime.now().millisecondsSinceEpoch;

    // Disk önbelleği
    await _prefs.setString('${_locationCacheKey}_$elderlyId', jsonEncode(cacheData));
  }

  Future<Map<String, dynamic>?> getCachedLocationData(String elderlyId) async {
    final cacheKey = '${_locationCacheKey}_$elderlyId';
    
    // Bellek önbelleğini kontrol et
    if (_memoryCache.containsKey(cacheKey)) {
      final timestamp = _cacheTimestamps[cacheKey] ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - timestamp < _locationCacheDuration) {
        return _memoryCache[cacheKey];
      } else {
        // Süresi dolmuş, temizle
        _memoryCache.remove(cacheKey);
        _cacheTimestamps.remove(cacheKey);
      }
    }

    // Disk önbelleğini kontrol et
    final cachedString = _prefs.getString(cacheKey);
    if (cachedString != null) {
      try {
        final cachedData = jsonDecode(cachedString) as Map<String, dynamic>;
        final timestamp = cachedData['timestamp'] as int;
        
        if (DateTime.now().millisecondsSinceEpoch - timestamp < _locationCacheDuration) {
          // Bellek önbelleğine ekle
          _memoryCache[cacheKey] = cachedData;
          _cacheTimestamps[cacheKey] = timestamp;
          return cachedData;
        } else {
          // Süresi dolmuş, temizle
          await _prefs.remove(cacheKey);
        }
      } catch (e) {
        // Hatalı veri, temizle
        await _prefs.remove(cacheKey);
      }
    }

    return null;
  }

  // Batarya verisi önbellekleme
  Future<void> cacheBatteryData(int batteryLevel, String batteryState) async {
    final cacheData = {
      'level': batteryLevel,
      'state': batteryState,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _memoryCache[_batteryCacheKey] = cacheData;
    _cacheTimestamps[_batteryCacheKey] = DateTime.now().millisecondsSinceEpoch;
    await _prefs.setString(_batteryCacheKey, jsonEncode(cacheData));
  }

  Future<Map<String, dynamic>?> getCachedBatteryData() async {
    // Bellek önbelleğini kontrol et
    if (_memoryCache.containsKey(_batteryCacheKey)) {
      final timestamp = _cacheTimestamps[_batteryCacheKey] ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - timestamp < _batteryCacheDuration) {
        return _memoryCache[_batteryCacheKey];
      } else {
        _memoryCache.remove(_batteryCacheKey);
        _cacheTimestamps.remove(_batteryCacheKey);
      }
    }

    // Disk önbelleğini kontrol et
    final cachedString = _prefs.getString(_batteryCacheKey);
    if (cachedString != null) {
      try {
        final cachedData = jsonDecode(cachedString) as Map<String, dynamic>;
        final timestamp = cachedData['timestamp'] as int;
        
        if (DateTime.now().millisecondsSinceEpoch - timestamp < _batteryCacheDuration) {
          _memoryCache[_batteryCacheKey] = cachedData;
          _cacheTimestamps[_batteryCacheKey] = timestamp;
          return cachedData;
        } else {
          await _prefs.remove(_batteryCacheKey);
        }
      } catch (e) {
        await _prefs.remove(_batteryCacheKey);
      }
    }

    return null;
  }

  // Yaşlı kişi verisi önbellekleme
  Future<void> cacheElderlyData(String elderlyId, Map<String, dynamic> data) async {
    final cacheData = {
      'data': data,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    final cacheKey = '${_elderlyDataCacheKey}_$elderlyId';
    _memoryCache[cacheKey] = cacheData;
    _cacheTimestamps[cacheKey] = DateTime.now().millisecondsSinceEpoch;
    await _prefs.setString(cacheKey, jsonEncode(cacheData));
  }

  Future<Map<String, dynamic>?> getCachedElderlyData(String elderlyId) async {
    final cacheKey = '${_elderlyDataCacheKey}_$elderlyId';
    
    if (_memoryCache.containsKey(cacheKey)) {
      final timestamp = _cacheTimestamps[cacheKey] ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - timestamp < _elderlyDataCacheDuration) {
        return _memoryCache[cacheKey];
      } else {
        _memoryCache.remove(cacheKey);
        _cacheTimestamps.remove(cacheKey);
      }
    }

    final cachedString = _prefs.getString(cacheKey);
    if (cachedString != null) {
      try {
        final cachedData = jsonDecode(cachedString) as Map<String, dynamic>;
        final timestamp = cachedData['timestamp'] as int;
        
        if (DateTime.now().millisecondsSinceEpoch - timestamp < _elderlyDataCacheDuration) {
          _memoryCache[cacheKey] = cachedData;
          _cacheTimestamps[cacheKey] = timestamp;
          return cachedData;
        } else {
          await _prefs.remove(cacheKey);
        }
      } catch (e) {
        await _prefs.remove(cacheKey);
      }
    }

    return null;
  }

  // Ayarlar önbellekleme
  Future<void> cacheSettings(Map<String, dynamic> settings) async {
    final cacheData = {
      'settings': settings,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _memoryCache[_settingsCacheKey] = cacheData;
    _cacheTimestamps[_settingsCacheKey] = DateTime.now().millisecondsSinceEpoch;
    await _prefs.setString(_settingsCacheKey, jsonEncode(cacheData));
  }

  Future<Map<String, dynamic>?> getCachedSettings() async {
    if (_memoryCache.containsKey(_settingsCacheKey)) {
      final timestamp = _cacheTimestamps[_settingsCacheKey] ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - timestamp < _settingsCacheDuration) {
        return _memoryCache[_settingsCacheKey];
      } else {
        _memoryCache.remove(_settingsCacheKey);
        _cacheTimestamps.remove(_settingsCacheKey);
      }
    }

    final cachedString = _prefs.getString(_settingsCacheKey);
    if (cachedString != null) {
      try {
        final cachedData = jsonDecode(cachedString) as Map<String, dynamic>;
        final timestamp = cachedData['timestamp'] as int;
        
        if (DateTime.now().millisecondsSinceEpoch - timestamp < _settingsCacheDuration) {
          _memoryCache[_settingsCacheKey] = cachedData;
          _cacheTimestamps[_settingsCacheKey] = timestamp;
          return cachedData;
        } else {
          await _prefs.remove(_settingsCacheKey);
        }
      } catch (e) {
        await _prefs.remove(_settingsCacheKey);
      }
    }

    return null;
  }

  // Önbellek temizleme
  Future<void> clearCache() async {
    _memoryCache.clear();
    _cacheTimestamps.clear();
    
    final keys = _prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith(_locationCacheKey) || 
          key.startsWith(_batteryCacheKey) || 
          key.startsWith(_elderlyDataCacheKey) || 
          key.startsWith(_settingsCacheKey)) {
        await _prefs.remove(key);
      }
    }
  }

  // Belirli önbellek temizleme
  Future<void> clearLocationCache(String elderlyId) async {
    final cacheKey = '${_locationCacheKey}_$elderlyId';
    _memoryCache.remove(cacheKey);
    _cacheTimestamps.remove(cacheKey);
    await _prefs.remove(cacheKey);
  }

  // Önbellek istatistikleri
  Map<String, dynamic> getCacheStats() {
    return {
      'memoryCacheSize': _memoryCache.length,
      'cacheTimestampsSize': _cacheTimestamps.length,
      'memoryCacheKeys': _memoryCache.keys.toList(),
    };
  }

  // Bellek kullanımını optimize et
  void optimizeMemoryUsage() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final keysToRemove = <String>[];

    for (final entry in _cacheTimestamps.entries) {
      final key = entry.key;
      final timestamp = entry.value;
      
      int maxAge;
      if (key.startsWith(_locationCacheKey)) {
        maxAge = _locationCacheDuration;
      } else if (key.startsWith(_batteryCacheKey)) {
        maxAge = _batteryCacheDuration;
      } else if (key.startsWith(_elderlyDataCacheKey)) {
        maxAge = _elderlyDataCacheDuration;
      } else if (key.startsWith(_settingsCacheKey)) {
        maxAge = _settingsCacheDuration;
      } else {
        maxAge = 300000; // 5 dakika varsayılan
      }

      if (now - timestamp > maxAge) {
        keysToRemove.add(key);
      }
    }

    for (final key in keysToRemove) {
      _memoryCache.remove(key);
      _cacheTimestamps.remove(key);
    }
  }
} 