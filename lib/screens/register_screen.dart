import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _familyNameController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _kvkkAccepted = false;
  bool _openConsentAccepted = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _familyNameController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (!_kvkkAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('KVKK Aydınlatma Metnini kabul etmelisiniz.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    if (!_openConsentAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Açık Rıza Metnini kabul etmelisiniz.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.registerWithEmailAndPassword(
        _emailController.text.trim(),
        _passwordController.text,
        _familyNameController.text.trim(),
      );

      if (mounted) {
        final prefs = await SharedPreferences.getInstance();
        final role = prefs.getString('device_role') ?? 'family';
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => HomeScreen(deviceRole: role)),
        );
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      switch (e.code) {
        case 'weak-password':
          errorMessage = 'Şifre çok zayıf. Lütfen daha güçlü bir şifre seçin.';
          break;
        case 'email-already-in-use':
          errorMessage = 'Bu e-posta adresi zaten başka bir hesap tarafından kullanılıyor.';
          break;
        case 'invalid-email':
          errorMessage = 'Geçersiz e-posta formatı.';
          break;
        case 'network-request-failed':
          errorMessage = 'Ağ hatası. Lütfen internet bağlantınızı kontrol edin.';
          break;
        default:
          errorMessage = 'Kayıt hatası: ${e.message}';
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bir hata oluştu: ${e.toString()}'),
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

  void _showKvkkDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('KVKK Aydınlatma Metni'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Kişisel Verilerin Korunması Kanunu (KVKK) Aydınlatma Metni',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 16),
              const Text(
                '1. Veri Sorumlusu:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Text('GPS Takip Uygulaması, kişisel verilerinizin veri sorumlusudur.'),
              const SizedBox(height: 8),
              const Text(
                '2. Toplanan Kişisel Veriler:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Text('• Ad, soyad, e-posta adresi\n• Konum verileri\n• Cihaz bilgileri\n• Kullanım istatistikleri'),
              const SizedBox(height: 8),
              const Text(
                '3. Kişisel Verilerin İşlenme Amaçları:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Text('• GPS takip hizmeti sunumu\n• Acil durum bildirimleri\n• Güvenli alan takibi\n• Uygulama performansının iyileştirilmesi'),
              const SizedBox(height: 8),
              const Text(
                '4. Kişisel Verilerin Aktarılması:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Text('Verileriniz, hizmet kalitesini artırmak amacıyla güvenli sunucularda saklanır ve üçüncü taraflarla paylaşılmaz.'),
              const SizedBox(height: 8),
              const Text(
                '5. Kişisel Veri Sahibinin Hakları:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Text('• Verilerinize erişim\n• Düzeltme talep etme\n• Silme talep etme\n• İşlemeyi sınırlama\n• Veri taşınabilirliği'),
              const SizedBox(height: 8),
              const Text(
                '6. İletişim:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Text('KVKK haklarınız için info.villagestudiotr@gmail.com adresinden bizimle iletişime geçebilirsiniz.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  void _showOpenConsentDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Açık Rıza Metni'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Açık Rıza Beyanı',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 16),
              const Text(
                'Bu uygulamayı kullanarak, aşağıdaki işlemler için açık rızanızı verdiğinizi kabul ediyorsunuz:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('• Konum verilerinizin toplanması ve işlenmesi'),
              const Text('• Acil durum durumunda yakınlarınıza bildirim gönderilmesi'),
              const Text('• Güvenli alan takibi için geofence teknolojisinin kullanılması'),
              const Text('• Uygulama performansını artırmak için anonim kullanım verilerinin toplanması'),
              const Text('• Push bildirimlerinin gönderilmesi'),
              const SizedBox(height: 8),
              const Text(
                'Bu rızanızı istediğiniz zaman geri çekebilirsiniz. Rızanızı geri çekmek için uygulama ayarlarından veya bizimle iletişime geçerek talebinizi iletebilirsiniz.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kayıt Ol'),
        backgroundColor: const Color(0xFF4A90E2),
        foregroundColor: Colors.white,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF4A90E2), Color(0xFF357ABD)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.person_add,
                          size: 80,
                          color: Color(0xFF4A90E2),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Aile Hesabı Oluştur',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF333333),
                          ),
                        ),
                        const SizedBox(height: 32),
                        TextFormField(
                          controller: _familyNameController,
                          decoration: const InputDecoration(
                            labelText: 'Aile Adı',
                            prefixIcon: Icon(Icons.family_restroom),
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Aile adı gerekli';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'E-posta',
                            prefixIcon: Icon(Icons.email),
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'E-posta gerekli';
                            }
                            if (!value.contains('@')) {
                              return 'Geçerli bir e-posta girin';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Şifre',
                            prefixIcon: const Icon(Icons.lock),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                            border: const OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Şifre gerekli';
                            }
                            if (value.length < 6) {
                              return 'Şifre en az 6 karakter olmalı';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirmPassword,
                          decoration: InputDecoration(
                            labelText: 'Şifre Tekrar',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirmPassword
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscureConfirmPassword = !_obscureConfirmPassword;
                                });
                              },
                            ),
                            border: const OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Şifre tekrarı gerekli';
                            }
                            if (value != _passwordController.text) {
                              return 'Şifreler eşleşmiyor';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        
                        // KVKK Onayı
                        Card(
                          elevation: 2,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Checkbox(
                                      value: _kvkkAccepted,
                                      onChanged: (value) {
                                        setState(() {
                                          _kvkkAccepted = value ?? false;
                                        });
                                      },
                                    ),
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: _showKvkkDialog,
                                        child: const Text(
                                          'KVKK Aydınlatma Metnini okudum ve kabul ediyorum',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Color(0xFF4A90E2),
                                            decoration: TextDecoration.underline,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Checkbox(
                                      value: _openConsentAccepted,
                                      onChanged: (value) {
                                        setState(() {
                                          _openConsentAccepted = value ?? false;
                                        });
                                      },
                                    ),
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: _showOpenConsentDialog,
                                        child: const Text(
                                          'Açık Rıza Metnini okudum ve kabul ediyorum',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Color(0xFF4A90E2),
                                            decoration: TextDecoration.underline,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _register,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4A90E2),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: _isLoading
                                ? const CircularProgressIndicator(
                                    color: Colors.white,
                                  )
                                : const Text(
                                    'Kayıt Ol',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
} 