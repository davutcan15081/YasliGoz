import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  Future<void> _selectRole(BuildContext context, String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('device_role', role);
    // Ana ekrana yönlendir
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => MyApp()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cihaz Rolü Seçin')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/logo.png',
              height: 120,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return const SizedBox.shrink();
              },
            ),
            const SizedBox(height: 32),
            const Text('Bu cihaz kimin için kullanılacak?', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => _selectRole(context, 'elderly'),
              icon: const Icon(Icons.elderly),
              label: const Text('Yaşlı (Takip Edilen)'),
              style: ElevatedButton.styleFrom(minimumSize: const Size(200, 48)),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _selectRole(context, 'family'),
              icon: const Icon(Icons.family_restroom),
              label: const Text('Aile Üyesi'),
              style: ElevatedButton.styleFrom(minimumSize: const Size(200, 48)),
            ),
          ],
        ),
      ),
    );
  }
} 