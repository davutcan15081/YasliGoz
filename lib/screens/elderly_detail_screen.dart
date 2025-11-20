import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/elderly_person.dart';
import '../services/notification_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';

class ElderlyDetailScreen extends StatefulWidget {
  final ElderlyPerson elderlyPerson;

  const ElderlyDetailScreen({super.key, required this.elderlyPerson});

  @override
  State<ElderlyDetailScreen> createState() => _ElderlyDetailScreenState();
}

class _ElderlyDetailScreenState extends State<ElderlyDetailScreen> {
  bool _isEditing = false;
  bool _isLoading = false;
  
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _addressController;
  late TextEditingController _notesController;
  late TextEditingController _deviceIdController;
  
  late List<EmergencyContact> _emergencyContacts;
  late List<String> _allergies;
  late List<String> _medications;
  late List<String> _chronicDiseases;

  LatLng? _currentLocation;
  StreamSubscription<DatabaseEvent>? _locationSubscription;
  final MapController _mapController = MapController();
  DateTime? _lastLocationUpdate;
  String? _locationSource;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.elderlyPerson.name);
    _phoneController = TextEditingController(text: widget.elderlyPerson.phoneNumber);
    _addressController = TextEditingController(text: widget.elderlyPerson.address);
    _notesController = TextEditingController(text: widget.elderlyPerson.notes);
    _deviceIdController = TextEditingController(text: widget.elderlyPerson.deviceId ?? '');
    
    _emergencyContacts = List.from(widget.elderlyPerson.emergencyContacts);
    _allergies = List.from(widget.elderlyPerson.allergies);
    _medications = List.from(widget.elderlyPerson.medications);
    _chronicDiseases = List.from(widget.elderlyPerson.chronicDiseases);
    _listenToLocationUpdates();
  }

  void _listenToLocationUpdates() {
    final deviceId = widget.elderlyPerson.deviceId;
    if (deviceId == null || deviceId.isEmpty) {
      debugPrint('[KONUM DINLEME] Cihaz ID\'si bulunamadığı için konum dinlenemiyor.');
      return;
    }
    
    // Seçili yaşlının deviceId'si ile dinle
    String safeDeviceId = deviceId.replaceAll(RegExp(r'[.#$\[\]]'), '_');
    final dbRef = FirebaseDatabase.instance.ref('locations/$safeDeviceId');
    debugPrint('[KONUM DINLEME] Firebase yolu: locations/$safeDeviceId');
    
    _locationSubscription = dbRef.onValue.listen((event) {
      debugPrint('[KONUM DINLEME] Firebase event alındı: \\${event.snapshot.value}');
      final data = event.snapshot.value;
      
      if (data != null) {
        debugPrint('[KONUM DINLEME] Data null değil, tip: \\${data.runtimeType}');
        
        // Farklı veri yapılarını kontrol et
        Map<String, dynamic>? locationData;
        
        if (data is Map) {
          // Doğrudan konum verisi
          if (data['latitude'] != null && data['longitude'] != null) {
            locationData = Map<String, dynamic>.from(data);
          }
          // current_location altında konum verisi
          else if (data['current_location'] != null && data['current_location'] is Map) {
            final currentLocation = data['current_location'] as Map;
            if (currentLocation['latitude'] != null && currentLocation['longitude'] != null) {
              locationData = Map<String, dynamic>.from(currentLocation);
            }
          }
        }
        
        if (locationData != null) {
          debugPrint('[KONUM DINLEME] Konum verisi bulundu: $locationData');
          final lat = (locationData['latitude'] as num).toDouble();
          final lng = (locationData['longitude'] as num).toDouble();
          
          if (mounted) {
            setState(() {
              _currentLocation = LatLng(lat, lng);
              _lastLocationUpdate = DateTime.now();
              _locationSource = safeDeviceId;
            });
            debugPrint('[KONUM DINLEME] Konum güncellendi: $_currentLocation');
            
            // Haritayı yeni konuma hareket ettir
            WidgetsBinding.instance.addPostFrameCallback((_) {
              debugPrint('[KONUM DINLEME] Harita yeni konuma odaklanıyor: $_currentLocation');
              _mapController.move(_currentLocation!, 15.0);
            });
            
            // Konum güncelleme bildirimi gönder
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final notificationService = Provider.of<NotificationService>(context, listen: false);
              notificationService.showLocationUpdateNotification(
                widget.elderlyPerson.name,
                'Yeni konum alındı',
              );
            });
          }
        } else {
          debugPrint('[KONUM DINLEME] Konum verisi bulunamadı! Data: $data, deviceId: $safeDeviceId');
        }
      } else {
        debugPrint('[KONUM DINLEME] Firebase event data null! deviceId: $safeDeviceId');
      }
    }, onError: (error) {
      debugPrint("[KONUM DINLEME] Konum dinlenirken hata oluştu: $error, deviceId: $safeDeviceId");
      if (mounted) {
        setState(() {
          _currentLocation = LatLng(41.0082, 28.9784); // İstanbul varsayılan konum
          _locationSource = 'Varsayılan';
        });
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    _deviceIdController.dispose();
    _locationSubscription?.cancel();
    super.dispose();
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

  Future<void> _saveChanges() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('Kullanıcı girişi bulunamadı');
      }

      // Kullanıcı anahtarını al
      final storage = const FlutterSecureStorage();
      String? key = await storage.read(key: 'user_key_${user.uid}');
      if (key == null) {
        throw Exception('Kullanıcı anahtarı bulunamadı');
      }

      final updatedElderlyPerson = ElderlyPerson(
        id: widget.elderlyPerson.id,
        name: _nameController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        address: _addressController.text.trim(),
        emergencyContacts: _emergencyContacts,
        allergies: _allergies,
        medications: _medications,
        chronicDiseases: _chronicDiseases,
        notes: _notesController.text.trim(),
        createdAt: widget.elderlyPerson.createdAt,
        deviceId: widget.elderlyPerson.deviceId,
      );

      // Veriyi şifrele
      final personData = updatedElderlyPerson.toMap();
              final encryptedData = await AuthService.encryptData(jsonEncode(personData), user.uid);

      // Şifreli veriyi Firebase'e kaydet
      await FirebaseDatabase.instance
          .ref('users/${user.uid}/elderly_people/${widget.elderlyPerson.id}')
          .set(encryptedData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Değişiklikler kaydedildi')),
        );
        setState(() {
          _isEditing = false;
        });
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kaydetme hatası: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }



  void _callEmergencyContact(EmergencyContact contact) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${contact.name} ile İletişim'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Telefon: ${contact.phoneNumber}'),
            Text('İlişki: ${contact.relationship}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              // TODO: Telefon arama özelliği eklenecek
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${contact.name} aranıyor...')),
              );
            },
            child: const Text('Ara'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Düzenle' : widget.elderlyPerson.name),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () {
                setState(() {
                  _isEditing = true;
                });
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Temel Bilgiler
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Temel Bilgiler',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 16),
                          if (_isEditing) ...[
                            _buildTextFormField(
                              controller: _nameController,
                              label: 'Ad Soyad',
                              icon: Icons.person,
                            ),
                            const SizedBox(height: 16),
                            _buildTextFormField(
                              controller: _phoneController,
                              label: 'Telefon Numarası',
                              icon: Icons.phone,
                              keyboardType: TextInputType.phone,
                            ),
                            const SizedBox(height: 16),
                            _buildTextFormField(
                              controller: _addressController,
                              label: 'Adres',
                              icon: Icons.home,
                            ),
                            const SizedBox(height: 16),
                            
                            // Cihaz Kimliği Alanı (Sadece Okunur)
                            TextFormField(
                              controller: _deviceIdController,
                              readOnly: true,
                              decoration: InputDecoration(
                                labelText: 'Eşleştirilmiş Cihaz Kimliği',
                                prefixIcon: const Icon(Icons.perm_device_information),
                                border: const OutlineInputBorder(),
                                filled: true,
                                fillColor: Colors.grey[200],
                              ),
                            ),
                          ] else ...[
                            _buildInfoRow('Ad Soyad', widget.elderlyPerson.name),
                            _buildInfoRow('Telefon', widget.elderlyPerson.phoneNumber),
                            if (widget.elderlyPerson.address.isNotEmpty)
                              _buildInfoRow('Adres', widget.elderlyPerson.address),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Konum Bilgisi
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                           const Text(
                            'Anlık Konum',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 16),
                          _currentLocation == null
                              ? Container(
                                  height: 250,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[100],
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.grey[300]!),
                                  ),
                                  child: const Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        CircularProgressIndicator(),
                                        SizedBox(height: 16),
                                        Text(
                                          "Konum bilgisi bekleniyor...",
                                          style: TextStyle(
                                            fontSize: 16,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          "Cihazın konum servisi açık olmalı",
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.location_on, color: Colors.green),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Son güncelleme: ${_lastLocationUpdate?.toString().substring(11, 19) ?? "Zaman bilgisi bulunamadı"}',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                              if (_locationSource != null)
                                                Text(
                                                  'Kaynak: $_locationSource',
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.blue,
                                                    fontStyle: FontStyle.italic,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      height: 250,
                                      child: FlutterMap(
                                        mapController: _mapController,
                                        options: MapOptions(
                                          initialCenter: _currentLocation!,
                                          initialZoom: 15.0,
                                          minZoom: 10.0,
                                          maxZoom: 18.0,
                                          onMapReady: () {
                                            print('Yaşlı detay haritası hazır');
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
                                          MarkerLayer(
                                            markers: [
                                              Marker(
                                                width: 80.0,
                                                height: 80.0,
                                                point: _currentLocation!,
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    color: Colors.red,
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
                                                    size: 40.0,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

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
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                              if (_isEditing)
                                IconButton(
                                  onPressed: _addEmergencyContact,
                                  icon: const Icon(Icons.add),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (_emergencyContacts.isEmpty)
                            const Text('Henüz kontak eklenmemiş', style: TextStyle(color: Colors.grey))
                          else
                            ..._emergencyContacts.map((contact) => ListTile(
                              leading: const Icon(Icons.phone, color: Colors.green),
                              title: Text(contact.name),
                              subtitle: Text('${contact.phoneNumber} - ${contact.relationship}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!_isEditing)
                                    IconButton(
                                      icon: const Icon(Icons.call, color: Colors.blue),
                                      onPressed: () => _callEmergencyContact(contact),
                                    ),
                                  if (_isEditing)
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () {
                                        setState(() {
                                          _emergencyContacts.remove(contact);
                                        });
                                      },
                                    ),
                                ],
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
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 16),

                          // Alerjiler
                          _buildHealthSection(
                            'Alerjiler',
                            _allergies,
                            _isEditing,
                            () => _addItem(_allergies, 'Alerji Ekle', 'Alerji'),
                            (item) {
                              setState(() {
                                _allergies.remove(item);
                              });
                            },
                          ),

                          const SizedBox(height: 16),

                          // İlaçlar
                          _buildHealthSection(
                            'İlaçlar',
                            _medications,
                            _isEditing,
                            () => _addItem(_medications, 'İlaç Ekle', 'İlaç'),
                            (item) {
                              setState(() {
                                _medications.remove(item);
                              });
                            },
                          ),

                          const SizedBox(height: 16),

                          // Kronik Hastalıklar
                          _buildHealthSection(
                            'Kronik Hastalıklar',
                            _chronicDiseases,
                            _isEditing,
                            () => _addItem(_chronicDiseases, 'Hastalık Ekle', 'Hastalık'),
                            (item) {
                              setState(() {
                                _chronicDiseases.remove(item);
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Notlar
                  if (widget.elderlyPerson.notes.isNotEmpty || _isEditing)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Notlar',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 16),
                            if (_isEditing)
                              TextFormField(
                                controller: _notesController,
                                decoration: const InputDecoration(
                                  labelText: 'Notlar',
                                  border: OutlineInputBorder(),
                                ),
                                maxLines: 3,
                              )
                            else
                              Text(widget.elderlyPerson.notes),
                          ],
                        ),
                      ),
                    ),

                  if (_isEditing) ...[
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _isEditing = false;
                                // Değişiklikleri geri al
                                _nameController.text = widget.elderlyPerson.name;
                                _phoneController.text = widget.elderlyPerson.phoneNumber;
                                _addressController.text = widget.elderlyPerson.address;
                                _notesController.text = widget.elderlyPerson.notes;
                                _deviceIdController.text = widget.elderlyPerson.deviceId ?? '';
                                _emergencyContacts = List.from(widget.elderlyPerson.emergencyContacts);
                                _allergies = List.from(widget.elderlyPerson.allergies);
                                _medications = List.from(widget.elderlyPerson.medications);
                                _chronicDiseases = List.from(widget.elderlyPerson.chronicDiseases);
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('İptal'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _saveChanges,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Kaydet'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildHealthSection(
    String title,
    List<String> items,
    bool isEditing,
    VoidCallback onAdd,
    Function(String) onDelete,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            if (isEditing)
              TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('Ekle'),
              ),
          ],
        ),
        if (items.isEmpty)
          Text('Henüz $title eklenmemiş', style: const TextStyle(color: Colors.grey))
        else
          Wrap(
            spacing: 8,
            children: items.map((item) => Chip(
              label: Text(item),
              onDeleted: isEditing ? () => onDelete(item) : null,
            )).toList(),
          ),
      ],
    );
  }

  Widget _buildTextFormField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
      keyboardType: keyboardType,
    );
  }
} 