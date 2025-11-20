import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:convert';
import '../services/auth_service.dart';

class AddEmergencyContactScreen extends StatefulWidget {
  final Map<String, dynamic>? contact;

  const AddEmergencyContactScreen({super.key, this.contact});

  @override
  State<AddEmergencyContactScreen> createState() => _AddEmergencyContactScreenState();
}

class _AddEmergencyContactScreenState extends State<AddEmergencyContactScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isSaving = false;
  bool get _isEditing => widget.contact != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _nameController.text = widget.contact!['name'] ?? '';
      _phoneController.text = widget.contact!['phone'] ?? '';
    }
  }

  Future<void> _saveContact() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('Kullanıcı girişi yapılmamış.');
      }

      // Kullanıcı anahtarını AuthService ile al
      final authService = AuthService();
      await authService.getOrCreateUserKey(user.uid);

      final contactData = {
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      };

      if (_isEditing) {
        // Mevcut kişiyi güncelle
        final contactId = widget.contact!['id'];
        final encryptedData = await AuthService.encryptData(jsonEncode(contactData), user.uid);
        await FirebaseDatabase.instance
            .ref('users/${user.uid}/emergency_contacts/$contactId')
            .set(encryptedData);
      } else {
        // Yeni kişi ekle
        final newContactRef = FirebaseDatabase.instance
            .ref('users/${user.uid}/emergency_contacts')
            .push();

        contactData['id'] = newContactRef.key!;
        final encryptedData = await AuthService.encryptData(jsonEncode(contactData), user.uid);
        await newContactRef.set(encryptedData);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Acil durum kişisi başarıyla kaydedildi!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true); // Başarılı olduğunu belirtmek için true döndür
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kişi kaydedilirken hata oluştu: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }


  
  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Kişiyi Düzenle' : 'Yeni Acil Durum Kişisi'),
        backgroundColor: Colors.red.shade800,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'İsim Soyisim',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Lütfen isim giriniz.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Telefon Numarası',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                  hintText: 'Örn: 5551234567'
                ),
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Lütfen telefon numarası giriniz.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveContact,
                icon: _isSaving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white))
                    : Icon(_isEditing ? Icons.check_circle : Icons.save),
                label: Text(_isSaving ? 'KAYDEDİLİYOR...' : (_isEditing ? 'GÜNCELLE' : 'KAYDET')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 