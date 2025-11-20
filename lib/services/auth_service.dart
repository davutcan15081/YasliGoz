import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:math';
import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/material.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  DatabaseReference get database => _database;

  // Mevcut kullanıcıyı al
  User? get currentUser => _auth.currentUser;

  // Kullanıcı durumu değişikliklerini dinle
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // E-posta/şifre ile kayıt ol
  Future<UserCredential> registerWithEmailAndPassword(
      String email, String password, String familyName) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Kullanıcı bilgilerini veritabanına kaydet
      if (result.user != null) {
        final uid = result.user!.uid;
        
        // Kullanıcı anahtarını oluştur
        await getOrCreateUserKey(uid);
        
        // Email ve familyName'i şifrele
        final encryptedEmail = await encryptData(email, uid);
        final encryptedFamilyName = await encryptData(familyName, uid);
        
        await _database.child('users/$uid').set({
          'email': encryptedEmail,
          'familyName': encryptedFamilyName,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        });
      }

      return result;
    } on FirebaseAuthException {
      // Firebase kimlik doğrulama hatasını doğrudan fırlat
      rethrow;
    } catch (e) {
      // Diğer hatalar için genel bir istisna fırlat
      throw Exception('Kayıt sırasında beklenmedik bir hata oluştu: $e');
    }
  }

  // E-posta/şifre ile giriş yap
  Future<UserCredential> signInWithEmailAndPassword(
      String email, String password) async {
    try {
      final result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      // Giriş başarılıysa, mevcut verileri şifrele (güncelleme için)
      if (result.user != null) {
        // Arka planda şifreleme işlemini yap
        encryptExistingUserData(result.user!.uid).catchError((e) {
          print('🔐 [GİRİŞ] Veri şifreleme hatası: $e');
        });
      }
      
      return result;
    } on FirebaseAuthException {
      // Firebase kimlik doğrulama hatasını doğrudan fırlat
      rethrow;
    } catch (e) {
      // Diğer hatalar için genel bir istisna fırlat
      throw Exception('Giriş sırasında beklenmedik bir hata oluştu: $e');
    }
  }

  // Google ile giriş yap
  Future<UserCredential> signInWithGoogle() async {
    try {
      // Google Sign-In implementasyonu burada yapılacak
      // Şimdilik sadece placeholder
      throw UnimplementedError('Google Sign-In henüz implement edilmedi');
    } catch (e) {
      throw Exception('Google giriş hatası: $e');
    }
  }

  // Çıkış yap
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } on FirebaseAuthException {
      rethrow;
    } catch (e) {
      throw Exception('Çıkış hatası: $e');
    }
  }

  // Şifre sıfırlama
  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } catch (e) {
      throw Exception('Şifre sıfırlama hatası: $e');
    }
  }

  // Kullanıcı bilgilerini al
  Future<Map<String, dynamic>?> getUserData(String userId) async {
    try {
      DatabaseEvent event = await _database.child('users/$userId').once();
      if (event.snapshot.value != null) {
        final rawData = Map<String, dynamic>.from(event.snapshot.value as Map);
        
        // Şifreli verileri çöz
        final decryptedData = <String, dynamic>{};
        
        for (final entry in rawData.entries) {
          if (entry.key == 'email' || entry.key == 'familyName') {
            // Şifreli alanları çöz
            if (entry.value is String) {
              decryptedData[entry.key] = await decryptData(entry.value as String, userId);
            } else {
              decryptedData[entry.key] = entry.value;
            }
          } else {
            // Diğer alanları olduğu gibi kopyala
            decryptedData[entry.key] = entry.value;
          }
        }
        
        return decryptedData;
      }
      return null;
    } catch (e) {
      throw Exception('Kullanıcı bilgileri alma hatası: $e');
    }
  }

  /// Kullanıcıya özel AES anahtarı oluşturur veya var olanı döner
  Future<String> getOrCreateUserKey(String userId) async {
    try {
      String? key = await _secureStorage.read(key: 'user_key_$userId');
      if (key == null) {
        final random = Random.secure();
        final values = List<int>.generate(32, (i) => random.nextInt(256));
        key = base64UrlEncode(values);
        await _secureStorage.write(key: 'user_key_$userId', value: key);
      }
      return key;
    } catch (e) {
      // BadPaddingException veya diğer storage hataları için yeni anahtar oluştur
      print('🔐 [ANAHTAR] Storage okuma hatası, yeni anahtar oluşturuluyor: $e');
      final random = Random.secure();
      final values = List<int>.generate(32, (i) => random.nextInt(256));
      final newKey = base64UrlEncode(values);
      try {
        await _secureStorage.write(key: 'user_key_$userId', value: newKey);
      } catch (writeError) {
        print('🔐 [ANAHTAR] Storage yazma hatası: $writeError');
      }
      return newKey;
    }
  }

  /// Veriyi şifreler - Merkezi şifreleme fonksiyonu
  static Future<String> encryptData(String data, String userId) async {
    try {
      // Null veya boş veri kontrolü
      if (data.isEmpty) {
        print('Boş veri şifrelenmeye çalışılıyor');
        return data;
      }

      final storage = const FlutterSecureStorage();
      String? userKey;
      try {
        userKey = await storage.read(key: 'user_key_$userId');
      } catch (storageError) {
        print('🔐 [ŞİFRELEME] Storage okuma hatası: $storageError');
        return data;
      }

      if (userKey == null) {
        print('🔐 [ŞİFRELEME] Kullanıcı anahtarı bulunamadı, veri şifrelenmeden döndürülüyor');
        return data;
      }

      // AES şifreleme
      final key = encrypt.Key.fromBase64(userKey);
      final random = Random.secure();
      final ivBytes = Uint8List.fromList(List<int>.generate(16, (i) => random.nextInt(256)));
      final iv = encrypt.IV(ivBytes);
      final encrypter = encrypt.Encrypter(encrypt.AES(key));
      final encrypted = encrypter.encrypt(data, iv: iv);
      
      // IV ve şifreli veriyi birleştir
      final combined = '${iv.base64}:${encrypted.base64}';
      return combined;
    } catch (e) {
      print('🔐 [ŞİFRELEME] Şifreleme hatası: $e');
      return data; // Hata durumunda orijinal veriyi döndür
    }
  }

  /// Şifreli veriyi çözer - Merkezi çözme fonksiyonu
  static Future<String> decryptData(String encryptedData, String userId) async {
    try {
      // Null veya boş veri kontrolü
      if (encryptedData.isEmpty) {
        print('🔐 [ŞİFRELEME] Boş veri çözülmeye çalışılıyor');
        return encryptedData;
      }

      final storage = const FlutterSecureStorage();
      String? userKey;
      try {
        userKey = await storage.read(key: 'user_key_$userId');
      } catch (storageError) {
        print('🔐 [ŞİFRELEME] Storage okuma hatası: $storageError');
        return encryptedData;
      }

      if (userKey == null) {
        print('🔐 [ŞİFRELEME] Kullanıcı anahtarı bulunamadı, veri çözülmeden döndürülüyor');
        return encryptedData;
      }

      // Veri formatını kontrol et
      if (!encryptedData.contains(':')) {
        print('🔐 [ŞİFRELEME] Eski format veya şifrelenmemiş veri tespit edildi, olduğu gibi döndürülüyor');
        return encryptedData;
      }

      // AES çözme
      final key = encrypt.Key.fromBase64(userKey);
      final parts = encryptedData.split(':');
      
      if (parts.length != 2) {
        print('🔐 [ŞİFRELEME] Geçersiz şifreli veri formatı');
        return encryptedData;
      }

      final ivBase64 = parts[0];
      final encryptedBase64 = parts[1];
      
      // Base64 formatını kontrol et
      if (!_isValidBase64(ivBase64) || !_isValidBase64(encryptedBase64)) {
        print('🔐 [ŞİFRELEME] Geçersiz Base64 formatı');
        return encryptedData;
      }
      
      try {
        final iv = encrypt.IV.fromBase64(ivBase64);
        final encrypter = encrypt.Encrypter(encrypt.AES(key));
        final decrypted = encrypter.decrypt64(encryptedBase64, iv: iv);
        
        return decrypted;
      } catch (decryptError) {
        // Sadece hata detayını logla, veriyi loglama
        print('🔐 [ŞİFRELEME] Şifre çözme hatası: $decryptError');
        // Eski format veri olabilir, orijinal veriyi döndür
        return encryptedData;
      }
    } catch (e) {
      print('🔐 [ŞİFRELEME] Genel veri çözme hatası: $e');
      // Genel hata durumunda orijinal veriyi döndür
      return encryptedData;
    }
  }

  /// Base64 formatını kontrol eder
  static bool _isValidBase64(String str) {
    try {
      if (str.isEmpty) return false;
      base64Decode(str);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Mevcut kullanıcı verilerini şifreler (güncelleme için)
  Future<void> encryptExistingUserData(String userId) async {
    try {
      // Mevcut verileri al
      final existingData = await getUserData(userId);
      if (existingData == null) return;
      
      // Email ve familyName zaten şifreli mi kontrol et
      final email = existingData['email'] as String?;
      final familyName = existingData['familyName'] as String?;
      
      if (email != null && !email.contains(':')) {
        // Email şifrelenmemiş, şifrele
        final encryptedEmail = await encryptData(email, userId);
        await _database.child('users/$userId/email').set(encryptedEmail);
        print('🔐 [GÜNCELLEME] Email şifrelendi: $userId');
      }
      
      if (familyName != null && !familyName.contains(':')) {
        // FamilyName şifrelenmemiş, şifrele
        final encryptedFamilyName = await encryptData(familyName, userId);
        await _database.child('users/$userId/familyName').set(encryptedFamilyName);
        print('🔐 [GÜNCELLEME] FamilyName şifrelendi: $userId');
      }
    } catch (e) {
      print('🔐 [GÜNCELLEME] Veri şifreleme hatası: $e');
    }
  }

  /// Firebase'den gelen veriyi güvenli şekilde çözer
  static Future<Map<String, dynamic>?> decryptFirebaseData(
    dynamic firebaseData, 
    String userId
  ) async {
    try {
      if (firebaseData == null) {
        print('🔐 [ŞİFRELEME] Firebase verisi null');
        return null;
      }

      if (firebaseData is Map<String, dynamic>) {
        // Veri zaten çözülmüş durumda
        return firebaseData;
      }

      if (firebaseData is String) {
        // Şifreli string veriyi çöz
        final decrypted = await decryptData(firebaseData, userId);
        if (decrypted == firebaseData) {
          // Çözme başarısız, orijinal veriyi döndür
          print('🔐 [ŞİFRELEME] Firebase veri çözülemedi, orijinal veri döndürülüyor');
          return null;
        }
        
        // JSON'a çevir
        final jsonData = jsonDecode(decrypted);
        return Map<String, dynamic>.from(jsonData);
      }

      return null;
    } catch (e) {
      print('🔐 [ŞİFRELEME] Firebase veri çözme hatası: $e');
      return null;
    }
  }

  /// Giriş sonrası anahtar kontrolü ve yaşlıları silme
  static Future<bool> checkKeyAndDeleteElderlyIfMissing(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final storage = const FlutterSecureStorage();
    String? key;
    try {
      key = await storage.read(key: 'user_key_${user.uid}');
    } catch (storageError) {
      print('🔐 [KONTROL] Storage okuma hatası: $storageError');
      // Storage hatası varsa anahtarı null olarak kabul et
      key = null;
    }
    if (key == null) {
      // Anahtar yoksa yaşlıları sil
      final dbRef = FirebaseDatabase.instance.ref('users/${user.uid}/elderly_people');
      await dbRef.remove();
      // Kullanıcıya bilgi mesajı göster
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Daha önce eklediğiniz yaşlılar silindi, çünkü anahtarınız kayboldu.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return true;
    }
    return false;
  }
} 