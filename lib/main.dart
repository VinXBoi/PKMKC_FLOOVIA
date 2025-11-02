import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:floovia/providers/flood_data_provider.dart';
import 'package:floovia/providers/map_data_provider.dart';
import 'package:floovia/providers/routes_provider.dart';
import 'package:floovia/providers/user_location_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'pages/floovia_dashboard.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🔥 LOAD DOTENV FIRST - before using any env variables!
  await dotenv.load(fileName: ".env");
  debugPrint('✅ Environment variables loaded');

  try {
    await Firebase.initializeApp(
      options: FirebaseOptionsManual.currentPlatform,
    );
    debugPrint('✅ Firebase initialized successfully');
  } catch (e) {
    debugPrint('❌ Firebase initialization error: $e');
  }

  // Configure Firestore settings
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  runApp(const FlooviApp());
}

class FlooviApp extends StatelessWidget {
  const FlooviApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserLocationProvider()),
        ChangeNotifierProvider(create: (_) => FloodDataProvider()),
        ChangeNotifierProvider(create: (_) => MapDataProvider()),
        ChangeNotifierProvider(create: (_) => RoutesProvider()),
      ],
      child: MaterialApp(
        title: 'Floovia',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
        ),
        home: const SplashScreen(),
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _hasNavigated = false;
  String _statusMessage = 'Menginisialisasi...';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp();
    });
  }

  Future<void> _initializeApp() async {
    if (!mounted) return;

    try {
      setState(() => _statusMessage = 'Mendapatkan lokasi...');
      
      final locationProvider = context.read<UserLocationProvider>();
      
      // Timeout yang lebih pendek - 5 detik
      await locationProvider.initializeLocation().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('⚠️ Location initialization timeout - continuing with default');
          // Tidak throw error, biarkan lanjut dengan default location
        },
      );

      debugPrint('✅ Location initialized');
    } catch (e) {
      debugPrint('⚠️ Location initialization error: $e');
      // Tidak masalah, lanjutkan saja dengan default location
    }

    // Tunggu sebentar untuk smooth transition
    await Future.delayed(const Duration(milliseconds: 500));

    // Navigate to dashboard
    if (mounted && !_hasNavigated) {
      _hasNavigated = true;
      
      setState(() => _statusMessage = 'Memuat aplikasi...');
      
      // Gunakan pushReplacement dengan fade transition
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) {
            return const FlooviaDashboard();
          },
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 300),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue[600],
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // App Logo from assets
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset(
                  'assets/logo.png',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    // Fallback if logo.png not found
                    return Icon(
                      Icons.water_drop,
                      size: 60,
                      color: Colors.blue[600],
                    );
                  },
                ),
              ),
            ),
            
            const SizedBox(height: 32),
            
            // App Name
            const Text(
              'Floovia',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1.2,
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Tagline
            Text(
              'Flood Navigation Assistant',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.8),
                letterSpacing: 0.5,
              ),
            ),
            
            const SizedBox(height: 48),
            
            // Loading Indicator
            const CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 3,
            ),
            
            const SizedBox(height: 24),
            
            // Status Message
            Text(
              _statusMessage,
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}