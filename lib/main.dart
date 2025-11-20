import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/family_panel_screen.dart';
import 'screens/geofence_screen.dart';
import 'screens/emergency_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/role_selection_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/elderly_selection_service.dart';
import 'services/auth_service.dart';
import 'services/background_service.dart';
import 'services/notification_service.dart';
import 'services/cache_service.dart';
import 'services/battery_optimization_service.dart';
import 'services/network_optimization_service.dart';
import 'services/startup_optimization_service.dart';
import 'services/permission_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'services/premium_service.dart';
// import 'package:firebase_app_check/firebase_app_check.dart';

// Arka plan mesajları için üst düzey bir işleyici fonksiyon
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Burada gelen mesaja göre işlem yapabilirsiniz.
  // Örneğin, bir bildirim göstermek gibi.
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Uygulamayı sadece dikey modda çalışacak şekilde kilitle
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  await Firebase.initializeApp();
  
  // RevenueCat ayarını kontrol et ve başlat
  final prefs = await SharedPreferences.getInstance();
  final revenueCatEnabled = prefs.getBool('revenueCatEnabled') ?? true;
  
  if (revenueCatEnabled) {
    try {
  await Purchases.configure(PurchasesConfiguration('goog_xcwXYQUqPxEhaQbPVxCtaXvjXKj'));
      print('RevenueCat başlatıldı');
    } catch (e) {
      print('RevenueCat başlatma hatası: $e');
    }
  } else {
    print('RevenueCat pasif modda - test için premium özellikler aktif');
  }
  // Yukarıdaki anahtarı kendi RevenueCat panelinden alıp buraya eklemelisin.
  
  // Performans optimizasyonu servislerini başlat
  final startupService = StartupOptimizationService();
  final cacheService = CacheService();
  final batteryService = BatteryOptimizationService();
  final networkService = NetworkOptimizationService();
  
  // Başlatma progress'ini izle
  startupService.setProgressCallback((progress) {
    // print('Başlatma ilerlemesi: ${(progress * 100).toInt()}%');
  });
  
  startupService.setStepCallback((step) {
    // print('Başlatma adımı: $step');
  });
  
  startupService.setStartupCompleteCallback(() {
    // print('Uygulama başlatma tamamlandı!');
  });
  
  // Optimizasyon servislerini başlat
  await startupService.initialize();
  
  await BackgroundService.initializeService();

  // Android için özel servis başlat - şimdilik devre dışı
  // if (Platform.isAndroid) {
  //   try {
  //     await BackgroundServiceManager.startAndroidService();
  //     print('Android arka plan servisi başlatıldı');
  //   } catch (e) {
  //     print('Android servis başlatma hatası: $e');
  //   }
  // }

  // Bildirim servisini başlat
  final notificationService = NotificationService();
  await notificationService.initialize();

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await _initFCM(); // Uzak alarm ve bildirimler için FCM başlat

  // Uygulama başlatıldığında premium kontrolü ve kaydı
  await PremiumService.checkAndSavePremiumStatus();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ElderlySelectionService()),
        Provider<AuthService>(create: (_) => AuthService()),
        Provider<NotificationService>(create: (_) => notificationService),
        Provider<CacheService>(create: (_) => cacheService),
        Provider<BatteryOptimizationService>(create: (_) => batteryService),
        Provider<NetworkOptimizationService>(create: (_) => networkService),
        Provider<StartupOptimizationService>(create: (_) => startupService),
        Provider<PermissionService>(create: (_) => PermissionService()),
      ],
      child: const MyApp(),
    ),
  );
}

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

Future<void> _initFCM() async {
  // Android için bildirim kanalı oluştur
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'high_importance_channel',
    'Önemli Bildirimler',
    description: 'Acil ve önemli bildirimler için kanal',
    importance: Importance.high,
  );
  await flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);

  // Local notification ayarları
  const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // FCM foreground mesajları için listener
  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;
    final data = message.data;
    if (notification != null && android != null) {
      flutterLocalNotificationsPlugin.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            icon: 'logo_notification_24dp',
            largeIcon: const DrawableResourceAndroidBitmap('logo_notification_48dp'),
            playSound: data['play_alarm'] == 'true',
            sound: data['play_alarm'] == 'true' ? const RawResourceAndroidNotificationSound('alarm') : null,
          ),
        ),
      );
    }
    // Eğer özel veri ile alarm tetiklenirse cihazda ses çal
    if (data['play_alarm'] == 'true') {
      final player = AudioPlayer();
      await player.play(AssetSource('alarm.mp3'), volume: 1.0);
    }
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Future<String?> _getDeviceRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('device_role');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GPS Takip Sistemi',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      routes: {
        '/role_selection': (context) => const RoleSelectionScreen(),
      },
      home: FutureBuilder<String?>(
        future: _getDeviceRole(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasError) {
            return Scaffold(body: Center(child: Text('Hata: \\${snapshot.error}')));
          }
          final role = snapshot.data;
          if (role == null) {
            return const RoleSelectionScreen();
          }
          return Consumer<AuthService>(
            builder: (context, authService, child) {
              if (authService.currentUser != null) {
                return HomeScreen(deviceRole: role);
              } else {
                return const LoginScreen();
              }
            },
          );
        },
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }
        
        if (snapshot.hasData && snapshot.data != null) {
          // Kullanıcı giriş yapmış, premium kontrolü ve kaydı
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            await PremiumService.checkAndSavePremiumStatus();
            // Cihaz rolünü kontrol et
            try {
              final prefs = await SharedPreferences.getInstance();
              final deviceRole = prefs.getString('device_role');
              
              // Yaşlı cihazı ise arka plan servisini başlat
              if (deviceRole == 'elderly') {
                await BackgroundService.startService();
                print('Yaşlı cihazı için arka plan servisi başlatıldı');
              }
            } catch (e) {
              print('Arka plan servisi başlatılamadı: $e');
            }
          });
          return const MainNavigation();
        }
        
        // Kullanıcı giriş yapmamış, giriş ekranını göster
        return const LoginScreen();
      },
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;
  String? _deviceRole;

  @override
  void initState() {
    super.initState();
    _loadDeviceRole();
  }

  Future<void> _loadDeviceRole() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _deviceRole = prefs.getString('device_role') ?? 'family';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_deviceRole == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final List<Widget> pages = <Widget>[
      HomeScreen(deviceRole: _deviceRole!),
      const FamilyPanelScreen(),
      const GeofenceScreen(),
      const EmergencyScreen(),
      const SettingsScreen(),
    ];
    return Scaffold(
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Ana Sayfa',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.group),
            label: 'Aile',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.location_on),
            label: 'Güvenli Alan',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.warning),
            label: 'Acil',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Ayarlar',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
      ),
    );
  }
}
