import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../services/premium_service.dart';

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  bool _isLoading = false;
  bool _isPremium = false;
  String? _error;
  List<Package> _packages = [];

  @override
  void initState() {
    super.initState();
    _checkPremiumStatus();
    _fetchPackages();
  }

  Future<void> _checkPremiumStatus() async {
    final isPremium = await PremiumService.isUserPremium();
    if (isPremium == null) {
      setState(() {
        _error = 'Premium durumu doğrulanamadı. Lütfen internet bağlantınızı kontrol edin.';
      });
      return;
    }
    setState(() {
      _isPremium = isPremium;
    });
    if (isPremium && mounted) {
      Navigator.of(context).pop(); // Premium olduysa sayfadan çık
    }
  }

  Future<void> _fetchPackages() async {
    try {
      final offerings = await Purchases.getOfferings();
      if (offerings.current != null && offerings.current!.availablePackages.isNotEmpty) {
        setState(() {
          _packages = offerings.current!.availablePackages;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Paketler yüklenemedi: $e';
      });
    }
  }

  Future<void> _buy(Package package) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await Purchases.purchasePackage(package);
      await _checkPremiumStatus();
    } catch (e) {
      setState(() {
        _error = 'Satın alma başarısız: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Premium Üyelik')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 16),
                    // Premium başlık ve ikon
                    Icon(Icons.workspace_premium, color: Colors.amber, size: 64),
                    const SizedBox(height: 12),
                    const Text(
                      'Premium Avantajları',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.amber),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Daha fazla yaşlı ekle, sınırsız aile üyesi ve gelişmiş özelliklere eriş!',
                      style: TextStyle(fontSize: 16, color: Colors.black87),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    // Avantajlar listesi
                    Card(
                      color: Colors.yellow[50],
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        children: const [
                          ListTile(
                            leading: Icon(Icons.person_add_alt_1, color: Colors.amber),
                            title: Text('Birden fazla yaşlı ekleme'),
                          ),
                          ListTile(
                            leading: Icon(Icons.group, color: Colors.amber),
                            title: Text('Sınırsız aile üyesi ekleme'),
                          ),
                          ListTile(
                            leading: Icon(Icons.location_on, color: Colors.amber),
                            title: Text('Coğrafi sınır (Geofence) tanımlama'),
                          ),
                          ListTile(
                            leading: Icon(Icons.notifications_active, color: Colors.amber),
                            title: Text('Akıllı uyarılar (düşük pil vb.)'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_isPremium)
                      Card(
                        color: Colors.green,
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: const ListTile(
                          leading: Icon(Icons.verified, color: Colors.white),
                          title: Text('Premium Üyelik Aktif', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    if (!_isPremium && _packages.isNotEmpty)
                      ..._packages.map((package) => Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              title: Text(package.storeProduct.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(package.storeProduct.description),
                              trailing: ElevatedButton.icon(
                                icon: const Icon(Icons.lock_open),
                                onPressed: () => _buy(package),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.amber,
                                  foregroundColor: Colors.black,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                label: Text('${package.storeProduct.priceString} Satın Al'),
                              ),
                            ),
                          )),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(_error!, style: const TextStyle(color: Colors.red)),
                      ),
                    if (!_isPremium && _packages.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text('Satın alınabilir paket bulunamadı.'),
                      ),
                    const SizedBox(height: 32),
                    // Güvenli ödeme vurgusu
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.verified_user, color: Colors.green, size: 20),
                        SizedBox(width: 8),
                        Text('Güvenli ödeme ve anında premium erişim', style: TextStyle(color: Colors.green)),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
    );
  }
} 