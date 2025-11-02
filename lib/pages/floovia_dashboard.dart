import 'dart:async';
import 'package:floovia/pages/about_page.dart';
import 'package:floovia/providers/flood_data_provider.dart';
import 'package:floovia/providers/map_data_provider.dart';
import 'package:floovia/providers/user_location_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'home_page.dart';
import 'map_page.dart';
import 'details_page.dart';
import 'routes_page.dart';

class FlooviaDashboard extends StatefulWidget {
  const FlooviaDashboard({super.key});

  @override
  State<FlooviaDashboard> createState() => _FlooviaDashboardState();
}

class _FlooviaDashboardState extends State<FlooviaDashboard> {
  int _currentIndex = 0;
  late final List<Widget> _pages;
  bool _isRefreshing = false;

  Timer? _syncTimer;
  Timer? _periodicTimer;
  
  @override
  void initState() {
    super.initState();
    _initializePages();
    _startSyncTimer();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _periodicTimer?.cancel();
    super.dispose();
  }

  void _initializePages() {
    _pages = [
      HomePage(
        onNavigateToMap: () => _navigateToTab(1),
        onNavigateToDetails: () => _navigateToTab(2),
        onNavigateToRoutes: () => _navigateToTab(3),
      ),
      const MapPage(),
      const DetailsPage(),
      RoutesPage(),
      const AboutPage()
    ];
  }

  void _navigateToTab(int index) {
    if (index >= 0 && index < _pages.length) {
      setState(() => _currentIndex = index);
    }
  }

  void _showNotifications() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Fitur notifikasi segera hadir'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // BARU (TIMER): Logika timer untuk sinkronisasi menit
  void _startSyncTimer() {
    DateTime sekarang = DateTime.now();
    
    // Hitung berapa detik lagi menuju menit berikutnya
    int detikMenujuMenitBerikutnya = 60 - sekarang.second;

    debugPrint("Timer sinkronisasi akan berjalan dalam $detikMenujuMenitBerikutnya detik");

    // Jalankan Timer satu kali untuk sinkronisasi
    _syncTimer = Timer(Duration(seconds: detikMenujuMenitBerikutnya), () {
      debugPrint("Tersinkronisasi! Memulai refresh periodik.");
      
      // Lakukan refresh global pertama tepat di awal menit
      _handleGlobalRefresh(); 

      // Setelah sinkron, jalankan refresh global setiap 1 menit
      _periodicTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
        // Ini akan berjalan setiap menit (10:02:00, 10:03:00, dst.)
        debugPrint("TIMER: Melakukan refresh global periodik...");
        _handleGlobalRefresh();
      });
    });
  }

  Future<void> _handleGlobalRefresh() async {
    // Flag _isRefreshing akan mencegah timer dan tombol manual 
    // berjalan bersamaan
    if (_isRefreshing) {
      debugPrint("Refresh dibatalkan, proses refresh lain sedang berjalan.");
      return; 
    }

    setState(() => _isRefreshing = true);

    try {
      // 1. Ambil semua provider
      final locationProvider = context.read<UserLocationProvider>();
      final mapProvider = context.read<MapDataProvider>();
      final floodProvider = context.read<FloodDataProvider>();

      // --- INI ADALAH LOGIKA BARU YANG PENTING ---
      
      // Cek apakah lokasi saat ini adalah lokasi GPS?
      // isUsingDefaultLocation bernilai true jika itu lokasi default ATAU hasil search
      // jadi !isUsingDefaultLocation berarti itu adalah lokasi GPS
      final bool isCurrentlyGps = !locationProvider.isUsingDefaultLocation;

      if (isCurrentlyGps) {
        // 1A. Jika sedang pakai GPS, refresh lokasi GPS-nya
        await locationProvider.refreshGpsLocation();
        debugPrint("Refresh: Lokasi GPS diperbarui.");
      } else {
        // 1B. Jika sedang pakai lokasi pencarian (misal "Mikroskil"), JANGAN refresh GPS.
        // Kita akan pakai lokasi pencarian yang sudah ada.
        debugPrint("Refresh: Menggunakan lokasi pencarian yang ada (${locationProvider.activeAddress}).");
      }

      // 2. Ambil lokasi aktif (bisa jadi hasil GPS baru, atau lokasi pencarian yg tadi)
      final newLocation = locationProvider.activeLocation; 

      // 3. Refresh provider lain menggunakan lokasi tersebut
      await Future.wait([
        mapProvider.refreshData(),
        floodProvider.fetchFloodDetails(newLocation, forceRefresh: true),
      ]);
      
      // --- AKHIR LOGIKA BARU ---

      debugPrint("Refresh global berhasil untuk lokasi: $newLocation");

    } catch (e) {
      debugPrint("Refresh global GAGAL: ${e.toString()}");
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memperbarui data: ${e.toString()}'),
            backgroundColor: Colors.red[700],
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: _buildBody(),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    const titles = [
      'Floovia',
      'Peta',
      'Detail Banjir',
      'Perencanaan Rute',
      'About Us'
    ];

    return AppBar(
      title: Text(
        titles[_currentIndex],
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      backgroundColor: Colors.blue[600],
      foregroundColor: Colors.white,
      elevation: 0,
      actions: [
        if (_isRefreshing)
          const Padding(
            padding: EdgeInsets.all(14.0),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2.5,
              ),
            ),
          )
        else
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _handleGlobalRefresh, // Tetap bisa refresh manual
            tooltip: 'Perbarui Semua Data',
          ),
        IconButton(
          icon: const Icon(Icons.notifications_outlined),
          onPressed: _showNotifications,
          tooltip: 'Notifikasi',
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildBody() {
    return SafeArea(
      child: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: _currentIndex,
      onTap: _navigateToTab,
      selectedItemColor: Colors.blue[700],
      unselectedItemColor: Colors.grey[600],
      selectedFontSize: 12,
      unselectedFontSize: 12,
      elevation: 8,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          activeIcon: Icon(Icons.home),
          label: 'Home',
          tooltip: 'Halaman Utama',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.map_outlined),
          activeIcon: Icon(Icons.map),
          label: 'Peta',
          tooltip: 'Peta Banjir',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.list_alt_outlined),
          activeIcon: Icon(Icons.list_alt),
          label: 'Detail',
          tooltip: 'Detail Banjir',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.alt_route_outlined),
          activeIcon: Icon(Icons.alt_route),
          label: 'Rute',
          tooltip: 'Perencanaan Rute',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.info_outline),
          activeIcon: Icon(Icons.info),
          label: 'About Us',
          tooltip: 'About Us Floovia Team',
        ),
      ],
    );
  }
}