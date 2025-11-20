import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart'; // Added for debugPrint

class PremiumService {
  static Future<bool?> isUserPremium() async {
    try {
      final purchaserInfo = await Purchases.getCustomerInfo();
      // RevenueCat'te "premium" olarak tanımladığın entitlement ID'yi buraya yazmalısın
      return purchaserInfo.entitlements.active.containsKey('Premium');
    } catch (e) {
      // Hata durumunda null döndür (bağlantı yok, RevenueCat hatası vs.)
      debugPrint('Premium kontrolü sırasında hata: $e');
      return null;
    }
  }

  static Future<void> checkAndSavePremiumStatus() async {
    final isPremium = await isUserPremium();
    // Local kaydet
    final prefs = await SharedPreferences.getInstance();
    if (isPremium != null) {
      await prefs.setBool('is_premium', isPremium);
    }
    // Firebase'e kaydet
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && isPremium != null) {
      final dbRef = FirebaseDatabase.instance.ref('users/${user.uid}');
      await dbRef.update({'premium': isPremium});
    }
  }
} 