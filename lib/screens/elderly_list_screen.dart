import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import '../models/elderly_person.dart';
import '../services/elderly_selection_service.dart';
import 'elderly_detail_screen.dart';
import 'add_elderly_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

class ElderlyListScreen extends StatefulWidget {
  const ElderlyListScreen({super.key});

  @override
  State<ElderlyListScreen> createState() => _ElderlyListScreenState();
}

class _ElderlyListScreenState extends State<ElderlyListScreen> {
  List<ElderlyPerson> _elderlyPeople = [];
  bool _isLoading = true;
  String? _error;
  final DatabaseReference _dbRef =
      FirebaseDatabase.instance.ref('users/${FirebaseAuth.instance.currentUser!.uid}/elderly_people');

  @override
  void initState() {
    super.initState();
    _loadElderlyPeople();
  }

  Future<void> _loadElderlyPeople() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _error = 'Kullanıcı girişi bulunamadı';
          _isLoading = false;
        });
        return;
      }

      // Kullanıcı anahtarını al
      final storage = const FlutterSecureStorage();
      String? key = await storage.read(key: 'user_key_${user.uid}');
      if (key == null) {
        setState(() {
          _error = 'Kullanıcı anahtarı bulunamadı';
          _isLoading = false;
        });
        return;
      }

      final snapshot = await _dbRef.get();

      if (snapshot.exists) {
        final List<ElderlyPerson> elderlyPeople = [];
        for (var child in snapshot.children) {
          try {
            final data = child.value;
            if (data is String) {
              // Şifreli veriyi çöz
              final decryptedData = decryptData(data, key);
              final jsonData = jsonDecode(decryptedData);
              if (jsonData is Map) {
                final Map<String, dynamic> convertedData = {};
                jsonData.forEach((key, value) {
                  if (key != null) {
                    convertedData[key.toString()] = value;
                  }
                });
                // id alanını child.key ile güncelle
                convertedData['id'] = child.key;
                elderlyPeople.add(ElderlyPerson.fromMap(convertedData));
              }
            }
          } catch (e) {
            print('Veri çözme hatası: $e');
            continue; // Bu veriyi atla, diğerlerini yüklemeye devam et
          }
        }
        setState(() {
          _elderlyPeople = elderlyPeople;
          _isLoading = false;
        });
      } else {
        setState(() {
          _elderlyPeople = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Yaşlı kişiler yüklenirken hata: $e';
        _isLoading = false;
      });
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

  Future<void> _deleteElderlyPerson(String id) async {
    if (id.isEmpty) return;
    
    try {
      // Önce yaşlı kişinin bilgilerini al
      final elderlySnapshot = await _dbRef.child(id).get();
      if (!elderlySnapshot.exists) {
        throw Exception('Yaşlı kişi bulunamadı');
      }
      
      // Güvenli tip dönüşümü
      Map<String, dynamic> elderlyData;
      try {
        final rawData = elderlySnapshot.value;
        if (rawData is Map) {
          elderlyData = Map<String, dynamic>.from(rawData);
        } else if (rawData is String) {
          // Şifreli veri ise çöz
          final user = FirebaseAuth.instance.currentUser;
          if (user == null) throw Exception('Kullanıcı bulunamadı');
          final storage = const FlutterSecureStorage();
          String? key = await storage.read(key: 'user_key_${user.uid}');
          if (key == null) throw Exception('Kullanıcı anahtarı bulunamadı');
          final decryptedData = decryptData(rawData, key);
          final jsonData = jsonDecode(decryptedData);
          elderlyData = Map<String, dynamic>.from(jsonData);
        } else {
          throw Exception('Geçersiz veri formatı');
        }
      } catch (e) {
        print('❌ [YAŞLI SİLME] Veri dönüştürme hatası: $e');
        throw Exception('Yaşlı kişi verisi okunamadı');
      }
      
      final deviceId = elderlyData['deviceId'] as String?;
      
      // 1. Yaşlı kişiyi ana listeden sil
      await _dbRef.child(id).remove();
      
      // 2. Eğer deviceId varsa, o cihaza ait tüm verileri sil
      if (deviceId != null && deviceId.isNotEmpty) {
        final sanitizedDeviceId = deviceId.replaceAll(RegExp(r'[.#$\[\]]'), '_');
        
        print('🗑️ [YAŞLI SİLME] Device ID: $sanitizedDeviceId');
        print('🗑️ [YAŞLI SİLME] Tüm veriler siliniyor...');
        
        // SOS bildirimlerini sil
        await FirebaseDatabase.instance.ref('sos_alerts/$sanitizedDeviceId').remove();
        print('🗑️ [YAŞLI SİLME] SOS bildirimleri silindi');
        
        // Konum verilerini sil
        await FirebaseDatabase.instance.ref('locations/$sanitizedDeviceId').remove();
        print('🗑️ [YAŞLI SİLME] Konum verileri silindi');
        
        // Sesli mesajları sil
        await FirebaseDatabase.instance.ref('voice_messages/$sanitizedDeviceId').remove();
        print('🗑️ [YAŞLI SİLME] Sesli mesajlar silindi');
        
        // Ortam seslerini sil
        await FirebaseDatabase.instance.ref('env_sounds/$sanitizedDeviceId').remove();
        print('🗑️ [YAŞLI SİLME] Ortam sesleri silindi');
        
        // Ortam sesi isteklerini sil
        await FirebaseDatabase.instance.ref('listen_requests/$sanitizedDeviceId').remove();
        print('🗑️ [YAŞLI SİLME] Ortam sesi istekleri silindi');
        
        // Güvenli alan verilerini sil
        await FirebaseDatabase.instance.ref('geofence/$id').remove();
        print('🗑️ [YAŞLI SİLME] Güvenli alan verileri silindi');
        
        // Eşleştirme kodunu sil
        try {
          final pairingCodesSnapshot = await FirebaseDatabase.instance.ref('pairing_codes').get();
          if (pairingCodesSnapshot.exists && pairingCodesSnapshot.value != null) {
            final pairingCodesData = pairingCodesSnapshot.value as Map;
            for (var entry in pairingCodesData.entries) {
              final codeData = entry.value as Map?;
              if (codeData != null && codeData['deviceId'] == deviceId) {
                await FirebaseDatabase.instance.ref('pairing_codes/${entry.key}').remove();
                print('🗑️ [YAŞLI SİLME] Eşleştirme kodu silindi: ${entry.key}');
                break; // İlk eşleşen kodu bulduk, döngüden çık
              }
            }
          }
        } catch (e) {
          print('⚠️ [YAŞLI SİLME] Eşleştirme kodu silinirken hata: $e');
          // Bu hata kritik değil, devam et
        }
        
        // Pil uyarılarını sil
        await FirebaseDatabase.instance.ref('battery_warnings/$sanitizedDeviceId').remove();
        print('🗑️ [YAŞLI SİLME] Pil uyarıları silindi');
        
        // Hareketsizlik uyarılarını sil
        await FirebaseDatabase.instance.ref('inactivity_warnings/$sanitizedDeviceId').remove();
        print('🗑️ [YAŞLI SİLME] Hareketsizlik uyarıları silindi');
      }
      
      // 3. Eğer bu yaşlı seçili ise, seçimi kaldır ve SOS takibini durdur
      final selectionService = Provider.of<ElderlySelectionService>(context, listen: false);
      if (selectionService.selectedElderly?.id == id) {
        // SOS takibini durdur
        final notificationService = Provider.of<NotificationService>(context, listen: false);
        await notificationService.stopSOSTracking();
        print('🛑 [YAŞLI SİLME] SOS takibi durduruldu');
        
        // Seçimi kaldır
        selectionService.clearSelection();
        print('🗑️ [YAŞLI SİLME] Seçili yaşlı seçimi kaldırıldı');
      }
      
      // 4. SharedPreferences'dan da temizle
      final prefs = await SharedPreferences.getInstance();
      final selectedElderlyId = prefs.getString('selected_elderly_id');
      if (selectedElderlyId == id) {
        await prefs.remove('selected_elderly_id');
        await prefs.remove('selected_elderly_name');
        print('🗑️ [YAŞLI SİLME] SharedPreferences temizlendi');
      }
      
      // 5. Listeyi yenile
      await _loadElderlyPeople();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Yaşlı kişi ve tüm verileri başarıyla silindi'),
            backgroundColor: Colors.green,
          ),
        );
      }
      
      print('✅ [YAŞLI SİLME] Tüm işlemler tamamlandı');
      
    } catch (e) {
      print('❌ [YAŞLI SİLME] Hata: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Silme hatası: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _selectElderly(ElderlyPerson elderly) async {
    debugPrint('🔍 [YAŞLI SEÇİM] ${elderly.name} seçildi');
    debugPrint('🔍 [YAŞLI SEÇİM] Device ID: ${elderly.deviceId}');
    final selectionService = Provider.of<ElderlySelectionService>(context, listen: false);
    selectionService.selectElderly(elderly);
    // Seçilen yaşlıyı SharedPreferences'a kaydet
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_elderly_id', elderly.id);
    await prefs.setString('selected_elderly_name', elderly.name);
    debugPrint('🔍 [YAŞLI SEÇİM] SharedPreferences kaydedildi');
    // Aile cihazında SOS takibini başlat
    if (elderly.deviceId != null && elderly.deviceId!.isNotEmpty) {
      debugPrint('🔍 [YAŞLI SEÇİM] SOS takibi başlatılıyor...');
      final notificationService = Provider.of<NotificationService>(context, listen: false);
      await notificationService.startSOSTracking(elderly.deviceId!);
      debugPrint('✅ [YAŞLI SEÇİM] SOS takibi başlatıldı!');
      // Test bildirimi gönder
      await notificationService.showLocationUpdateNotification(
        elderly.name,
        'Takip başlatıldı'
      );
      debugPrint('✅ [YAŞLI SEÇİM] Test bildirimi gönderildi!');
      // pairing_codes altında deviceId eşleşen kodu bulup family_connected true yap
      final pairingCodesSnapshot = await FirebaseDatabase.instance.ref('pairing_codes').get();
      if (pairingCodesSnapshot.exists && pairingCodesSnapshot.value != null) {
        final pairingCodesData = pairingCodesSnapshot.value as Map;
        for (var entry in pairingCodesData.entries) {
          final codeData = entry.value as Map?;
          if (codeData != null && codeData['deviceId'] == elderly.deviceId) {
            await FirebaseDatabase.instance.ref('pairing_codes/${entry.key}/family_connected').set(true);
            debugPrint('✅ [YAŞLI SEÇİM] pairing_codes/${entry.key}/family_connected TRUE yapıldı');
            break;
          }
        }
      }
    } else {
      debugPrint('❌ [YAŞLI SEÇİM] Device ID boş, SOS takibi başlatılamadı!');
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${elderly.name} seçildi ve takip ediliyor'),
        backgroundColor: Colors.green,
        action: SnackBarAction(
          label: 'Geri Al',
          textColor: Colors.white,
          onPressed: () {
            selectionService.clearSelection();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Seçim kaldırıldı')),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectionService = Provider.of<ElderlySelectionService>(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yaşlı Kişiler'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          if (selectionService.hasSelectedElderly)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () async {
                // SOS takibini durdur
                final notificationService = Provider.of<NotificationService>(context, listen: false);
                await notificationService.stopSOSTracking();
                print('🛑 [SEÇİM KALDIRMA] SOS takibi durduruldu');
                // pairing_codes altında deviceId eşleşen kodu bulup family_connected false yap
                final elderly = selectionService.selectedElderly;
                if (elderly != null && elderly.deviceId != null && elderly.deviceId!.isNotEmpty) {
                  final pairingCodesSnapshot = await FirebaseDatabase.instance.ref('pairing_codes').get();
                  if (pairingCodesSnapshot.exists && pairingCodesSnapshot.value != null) {
                    final pairingCodesData = pairingCodesSnapshot.value as Map;
                    for (var entry in pairingCodesData.entries) {
                      final codeData = entry.value as Map?;
                      if (codeData != null && codeData['deviceId'] == elderly.deviceId) {
                        await FirebaseDatabase.instance.ref('pairing_codes/${entry.key}/family_connected').set(false);
                        print('🛑 [SEÇİM KALDIRMA] pairing_codes/${entry.key}/family_connected FALSE yapıldı');
                        break;
                      }
                    }
                  }
                }
                // Seçimi kaldır
                selectionService.clearSelection();
                // SharedPreferences'dan temizle
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('selected_elderly_id');
                await prefs.remove('selected_elderly_name');
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Seçim kaldırıldı ve takip durduruldu'),
                    backgroundColor: Colors.orange,
                  ),
                );
              },
              tooltip: 'Seçimi Kaldır',
            ),
        ],
      ),
      body: Column(
        children: [
          // Seçili kişi bilgisi
          if (selectionService.hasSelectedElderly)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.green.shade100,
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Takip Edilen: ${selectionService.selectedElderlyName}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Tüm özellikler bu kişi üzerinde çalışacak',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          
          // Liste
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(_error!, style: const TextStyle(color: Colors.red)),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _loadElderlyPeople,
                              child: const Text('Tekrar Dene'),
                            ),
                          ],
                        ),
                      )
                    : _elderlyPeople.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.people_outline, size: 64, color: Colors.grey),
                                SizedBox(height: 16),
                                Text(
                                  'Henüz yaşlı kişi eklenmemiş',
                                  style: TextStyle(fontSize: 18, color: Colors.grey),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Yeni yaşlı kişi eklemek için + butonuna basın',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadElderlyPeople,
                            child: ListView.builder(
                              itemCount: _elderlyPeople.length,
                              itemBuilder: (context, index) {
                                final elderly = _elderlyPeople[index];
                                
                                return _buildElderlyCard(elderly);
                              },
                            ),
                          ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddElderlyScreen()),
          );
          if (result == true) {
            _loadElderlyPeople();
          }
        },
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildElderlyCard(ElderlyPerson elderly) {
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: Colors.grey.shade100,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.grey,
          child: Text(
            elderly.name.substring(0, 1).toUpperCase(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(
          elderly.name,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(elderly.phoneNumber),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  elderly.deviceId != null ? Icons.phone_android : Icons.phone_android_outlined,
                  size: 16,
                  color: elderly.deviceId != null ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${elderly.deviceId != null ? 'Cihaz Eşleştirildi' : 'Cihaz Eşleştirilmemiş'} ${elderly.deviceName != null && elderly.deviceName!.isNotEmpty ? '(${elderly.deviceName})' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      color: elderly.deviceId != null ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: SizedBox(
          width: 96, // Genişliği azalttım
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (elderly.deviceId == null)
                IconButton(
                  icon: const Icon(Icons.link, color: Colors.orange),
                  iconSize: 20,
                  tooltip: 'Cihaz Eşleştir',
                  onPressed: () => _showDevicePairingDialog(elderly),
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                iconSize: 20,
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(),
                onSelected: (value) {
                  if (value == 'info') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ElderlyDetailScreen(elderlyPerson: elderly),
                      ),
                    );
                  } else if (value == 'delete') {
                    _showDeleteDialog(elderly);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'info',
                    child: Row(
                      children: [
                        Icon(Icons.info, color: Colors.blue, size: 18),
                        SizedBox(width: 8),
                        Text('Detaylar'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, color: Colors.red, size: 18),
                        SizedBox(width: 8),
                        Text('Sil'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        onTap: () => _selectElderly(elderly),
      ),
    );
  }

  void _showDevicePairingDialog(ElderlyPerson elderly) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cihaz Eşleştirme'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${elderly.name} için cihaz eşleştirmek istiyor musunuz?'),
            const SizedBox(height: 16),
            const Text(
              'Bu işlem için:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('• Yaşlı kişinin telefonunda uygulama açık olmalı'),
            const Text('• İnternet bağlantısı olmalı'),
            const Text('• Konum izinleri verilmiş olmalı'),
            const SizedBox(height: 16),
            const Text(
              'Cihaz eşleştirme işlemi "Yeni Yaşlı Kişi" ekranından yapılmalıdır.',
              style: TextStyle(fontStyle: FontStyle.italic, color: Colors.orange),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _navigateToAddElderlyWithDevice(elderly);
            },
            child: const Text('Cihaz Eşleştir'),
          ),
        ],
      ),
    );
  }

  void _navigateToAddElderlyWithDevice(ElderlyPerson elderly) {
    // Mevcut yaşlı kişiyi sil ve yeniden ekleme ekranına yönlendir
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cihaz Eşleştirme'),
        content: const Text(
          'Cihaz eşleştirmek için yaşlı kişiyi yeniden eklemeniz gerekiyor. '
          'Mevcut bilgiler korunacak ve sadece cihaz bilgileri eklenecek.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              // Yaşlı kişiyi sil
              await _deleteElderlyPerson(elderly.id);
              // Yeniden ekleme ekranına yönlendir
              if (mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AddElderlyScreen(),
                  ),
                );
              }
            },
            child: const Text('Devam Et'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(ElderlyPerson elderly) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Silme Onayı'),
        content: Text('${elderly.name} kişisini silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ).then((value) async {
      if (value == true) {
        await _deleteElderlyPerson(elderly.id);
      }
    });
  }
} 