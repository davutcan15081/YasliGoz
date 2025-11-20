import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/elderly_person.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/premium_service.dart';
import 'premium_screen.dart';
import 'dart:convert';
import '../services/auth_service.dart';

class AddElderlyScreen extends StatefulWidget {
  const AddElderlyScreen({super.key});

  @override
  State<AddElderlyScreen> createState() => _AddElderlyScreenState();
}

class _AddElderlyScreenState extends State<AddElderlyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _notesController = TextEditingController();
  final _pairingCodeController = TextEditingController();
  
  final List<EmergencyContact> _emergencyContacts = [];
  final List<String> _allergies = [];
  final List<String> _medications = [];
  final List<String> _chronicDiseases = [];
  
  bool _isLoading = false;
  String? _resolvedDeviceId;
  bool _isVerifyingCode = false;
  bool _isPremium = false;
  int _elderlyCount = 0;

  @override
  void initState() {
    super.initState();
    _checkPremiumAndCount();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    _pairingCodeController.dispose();
    super.dispose();
  }

  Future<void> _checkPremiumAndCount() async {
    final isPremium = await PremiumService.isUserPremium();
    setState(() {
      _isPremium = isPremium ?? false;
    });
    // Kullanıcının eklediği yaşlı kişi sayısını çek
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final dbRef = FirebaseDatabase.instance.ref('users/${user.uid}/elderly_people');
      final snapshot = await dbRef.get();
      if (snapshot.exists && snapshot.value is Map) {
        setState(() {
          _elderlyCount = (snapshot.value as Map).length;
        });
      }
    }
  }

  void _addEmergencyContact() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Acil Durum Kontağı Ekle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(labelText: 'Ad Soyad'),
              onSubmitted: (name) {
                Navigator.pop(context);
                _showPhoneDialog(name);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
        ],
      ),
    );
  }

  void _showPhoneDialog(String name) {
    final phoneController = TextEditingController();
    final relationshipController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('İletişim Bilgileri'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(labelText: 'Telefon'),
              keyboardType: TextInputType.phone,
            ),
            TextField(
              controller: relationshipController,
              decoration: const InputDecoration(labelText: 'İlişki (Örn: Oğul, Kız, Doktor)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () {
              if (phoneController.text.isNotEmpty) {
                setState(() {
                  _emergencyContacts.add(EmergencyContact(
                    name: name,
                    phoneNumber: phoneController.text,
                    relationship: relationshipController.text,
                  ));
                });
                Navigator.pop(context);
              }
            },
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
  }

  void _addItem(List<String> list, String title, String hint) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                setState(() {
                  list.add(controller.text);
                });
                Navigator.pop(context);
              }
            },
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
  }

  Future<void> _verifyPairingCode() async {
    final code = _pairingCodeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lütfen bir kod girin.')));
      return;
    }

    setState(() {
      _isVerifyingCode = true;
      _resolvedDeviceId = null;
    });

    try {
      final dbRef = FirebaseDatabase.instance.ref('pairing_codes/$code');
      final snapshot = await dbRef.get();

      if (snapshot.exists && snapshot.value != null) {
        final data = snapshot.value as Map;
        final deviceId = data['deviceId'] as String?;
        if (deviceId != null) {
          setState(() {
            _resolvedDeviceId = deviceId;
          });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cihaz başarıyla doğrulandı!'), backgroundColor: Colors.green));
          // İsteğe bağlı: Eşleştirme sonrası kodu sil
          // dbRef.remove();
        } else {
          throw Exception('Kodda cihaz kimliği bulunamadı.');
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Geçersiz veya süresi dolmuş kod.'), backgroundColor: Colors.red));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Doğrulama hatası: ${e.toString()}'), backgroundColor: Colors.red));
    } finally {
      setState(() {
        _isVerifyingCode = false;
      });
    }
  }

  Future<void> _saveElderlyPerson() async {
    if (!_formKey.currentState!.validate()) return;

    // Premium değilse ve zaten 1 yaşlı varsa ekleme engellensin
    if (!_isPremium && _elderlyCount > 0) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Premium Gerekli'),
            content: const Text('Birden fazla yaşlı eklemek için premium üyelik gereklidir.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('İptal'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const PremiumScreen()),
                  );
                },
                child: const Text('Premium Ol'),
              ),
            ],
          ),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // O anki giriş yapmış kullanıcının kimliğini al
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('Yaşlı kişi eklemek için giriş yapmış olmalısınız.');
      }

      final newPerson = ElderlyPerson(
        id: '', // Firebase oluşturacak
        name: _nameController.text,
        phoneNumber: _phoneController.text,
        address: _addressController.text,
        notes: _notesController.text,
        deviceId: _resolvedDeviceId,
        emergencyContacts: _emergencyContacts,
        allergies: _allergies,
        medications: _medications,
        chronicDiseases: _chronicDiseases,
        createdAt: DateTime.now(),
      );

      // Kullanıcı anahtarını AuthService ile al
      final authService = AuthService();
      await authService.getOrCreateUserKey(user.uid);
      
      // Şifreli veriyi Firebase'e kaydet
      final dbRef = FirebaseDatabase.instance.ref('users/${user.uid}/elderly_people').push();
      final updatedPerson = ElderlyPerson(
        id: dbRef.key ?? '',
        name: newPerson.name,
        phoneNumber: newPerson.phoneNumber,
        address: newPerson.address,
        notes: newPerson.notes,
        deviceId: newPerson.deviceId,
        emergencyContacts: newPerson.emergencyContacts,
        allergies: newPerson.allergies,
        medications: newPerson.medications,
        chronicDiseases: newPerson.chronicDiseases,
        createdAt: newPerson.createdAt,
        deviceName: newPerson.deviceName,
        fcmToken: newPerson.fcmToken,
        isDeviceActive: newPerson.isDeviceActive,
      );
      final updatedPersonData = updatedPerson.toMap();
      final encryptedData = await AuthService.encryptData(jsonEncode(updatedPersonData), user.uid);
      await dbRef.set(encryptedData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_nameController.text} başarıyla eklendi.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true); // Geri dönerken listeyi yenilemesi için true gönder
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kişi kaydedilirken hata oluştu: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yeni Yaşlı Kişi'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Ad Soyad *',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Ad soyad gerekli';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _phoneController,
                      decoration: const InputDecoration(
                        labelText: 'Telefon *',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.phone,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Telefon gerekli';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _addressController,
                      decoration: const InputDecoration(
                        labelText: 'Adres',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 24),
                    
                    // Acil Durum Kontakları
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Acil Durum Kontakları',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                IconButton(
                                  onPressed: _addEmergencyContact,
                                  icon: const Icon(Icons.add),
                                ),
                              ],
                            ),
                            if (_emergencyContacts.isEmpty)
                              const Text('Henüz kontak eklenmemiş', style: TextStyle(color: Colors.grey))
                            else
                              ..._emergencyContacts.map((contact) => ListTile(
                                title: Text(contact.name),
                                subtitle: Text('${contact.phoneNumber} - ${contact.relationship}'),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () {
                                    setState(() {
                                      _emergencyContacts.remove(contact);
                                    });
                                  },
                                ),
                              )),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Sağlık Bilgileri
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Sağlık Bilgileri',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 16),
                            
                            // Alerjiler
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Alerjiler'),
                                TextButton.icon(
                                  onPressed: () => _addItem(_allergies, 'Alerji Ekle', 'Alerji'),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Ekle'),
                                ),
                              ],
                            ),
                            if (_allergies.isNotEmpty)
                              Wrap(
                                spacing: 8,
                                children: _allergies.map((allergy) => Chip(
                                  label: Text(allergy),
                                  onDeleted: () {
                                    setState(() {
                                      _allergies.remove(allergy);
                                    });
                                  },
                                )).toList(),
                              ),
                            
                            const SizedBox(height: 16),
                            
                            // İlaçlar
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('İlaçlar'),
                                TextButton.icon(
                                  onPressed: () => _addItem(_medications, 'İlaç Ekle', 'İlaç'),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Ekle'),
                                ),
                              ],
                            ),
                            if (_medications.isNotEmpty)
                              Wrap(
                                spacing: 8,
                                children: _medications.map((medication) => Chip(
                                  label: Text(medication),
                                  onDeleted: () {
                                    setState(() {
                                      _medications.remove(medication);
                                    });
                                  },
                                )).toList(),
                              ),
                            
                            const SizedBox(height: 16),
                            
                            // Kronik Hastalıklar
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Kronik Hastalıklar'),
                                TextButton.icon(
                                  onPressed: () => _addItem(_chronicDiseases, 'Hastalık Ekle', 'Hastalık'),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Ekle'),
                                ),
                              ],
                            ),
                            if (_chronicDiseases.isNotEmpty)
                              Wrap(
                                spacing: 8,
                                children: _chronicDiseases.map((disease) => Chip(
                                  label: Text(disease),
                                  onDeleted: () {
                                    setState(() {
                                      _chronicDiseases.remove(disease);
                                    });
                                  },
                                )).toList(),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    TextFormField(
                      controller: _notesController,
                      decoration: const InputDecoration(
                        labelText: 'Notlar',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 24),
                    
                    // Eşleştirme Kodu Alanı
                    TextFormField(
                      controller: _pairingCodeController,
                      decoration: InputDecoration(
                        labelText: 'Eşleştirme Kodu (Zorunlu)',
                        prefixIcon: const Icon(Icons.qr_code_2),
                        hintText: 'Yaşlı cihazındaki 6 haneli kod',
                        border: const OutlineInputBorder(),
                        suffixIcon: _isVerifyingCode 
                          ? const Padding(padding: EdgeInsets.all(12.0), child: CircularProgressIndicator(strokeWidth: 2)) 
                          : IconButton(
                              icon: const Icon(Icons.check_circle_outline),
                              tooltip: 'Kodu Doğrula',
                              onPressed: _verifyPairingCode,
                            ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Lütfen 6 haneli eşleştirme kodunu girin.';
                        }
                        if (_resolvedDeviceId == null) {
                          return 'Lütfen kodu doğrulayın.';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),
                    
                    ElevatedButton(
                      onPressed: _saveElderlyPerson,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Kaydet'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
} 