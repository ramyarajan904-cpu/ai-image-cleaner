import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:percent_indicator/percent_indicator.dart';
import 'storage_service.dart';
import 'scan_result_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AICleanerApp());
}

class AICleanerApp extends StatelessWidget {
  const AICleanerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AI Storage Cleaner',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blueAccent,
        fontFamily: 'Poppins', 
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // --- CONFIGURATION ---
  // Browser-la work aana adhe IP inga irukannu check pannikonga
  static const String serverIp = "192.168.166.178"; 
  static const String serverPort = "8000";
  final String apiBaseUrl = "http://$serverIp:$serverPort";

  Map<String, int> counts = {"Camera": 0, "WhatsApp": 0, "Screenshots": 0, "Others": 0};
  double _storagePercent = 0.0; 
  bool isLoading = true;
  bool isServerOnline = false;

  @override
  void initState() {
    super.initState();
    _initApp(); 
  }

  Future<void> _initApp() async {
    bool hasPermission = await StorageService.requestPermissions();
    if (hasPermission) {
      _loadData();
    } else {
      setState(() => isLoading = false);
      if (mounted) {
        _showPermissionError();
      }
    }
  }

  void _showPermissionError() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text("Storage access required!"),
        action: SnackBarAction(label: "Retry", onPressed: () => _initApp()),
      ),
    );
  }

  // UPDATED: Timeout increased to 10s for better connectivity
  Future<void> _checkServerStatus() async {
    try {
      final response = await http.get(Uri.parse("$apiBaseUrl/reset_session"))
          .timeout(const Duration(seconds: 10)); // Increased timeout
      setState(() => isServerOnline = response.statusCode == 200);
    } catch (_) {
      setState(() => isServerOnline = false);
    }
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    
    // Server check and data fetch happening together
    await _checkServerStatus();
    double percent = await StorageService.getStorageUsagePercentage();
    var res = await StorageService.getFolderCounts();
    
    setState(() {
      _storagePercent = percent;
      counts = res;
      isLoading = false;
    });
  }

  Future<bool> _resetBackendSession() async {
    try {
      final response = await http.get(Uri.parse("$apiBaseUrl/reset_session"))
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBFBFB),
      appBar: AppBar(
        title: const Text("AI Cleaner Dashboard", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: false,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Chip(
              label: Text(
                isServerOnline ? "Server Online" : "Server Offline", 
                style: TextStyle(fontSize: 10, color: isServerOnline ? Colors.green[800] : Colors.red[800])
              ),
              backgroundColor: isServerOnline ? Colors.green[50] : Colors.red[50],
              side: BorderSide.none,
              avatar: CircleAvatar(radius: 4, backgroundColor: isServerOnline ? Colors.green : Colors.red),
            ),
          ),
          IconButton(onPressed: _loadData, icon: const Icon(Icons.refresh_rounded))
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildStorageCard(), 
                    const SizedBox(height: 30),
                    const Row(
                      children: [
                        Icon(Icons.analytics_outlined, size: 20, color: Colors.blueGrey),
                        SizedBox(width: 8),
                        Text(
                          "Gallery Categories",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 1.0,
                      children: [
                        _folderCard(Icons.camera_alt_rounded, "Camera", counts["Camera"] ?? 0, Colors.blue),
                        _folderCard(Icons.chat_bubble_rounded, "WhatsApp", counts["WhatsApp"] ?? 0, Colors.green),
                        _folderCard(Icons.screenshot_rounded, "Screenshots", counts["Screenshots"] ?? 0, Colors.orange),
                        _folderCard(Icons.folder_copy_rounded, "Others", counts["Others"] ?? 0, Colors.purple),
                      ],
                    ),
                    const SizedBox(height: 40),
                    const Text(
                      "MSc COMPUTER SCIENCE PROJECT • 2026",
                      style: TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildStorageCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: Colors.blue.withOpacity(0.25), blurRadius: 20, offset: const Offset(0, 10))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Device Health", style: TextStyle(color: Colors.white70, fontSize: 14)),
              Icon(Icons.info_outline, color: Colors.white70, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "${(_storagePercent * 100).toStringAsFixed(1)}% Full",
            style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          LinearPercentIndicator(
            lineHeight: 10,
            percent: _storagePercent > 1.0 ? 1.0 : _storagePercent, 
            progressColor: Colors.white,
            backgroundColor: Colors.white24,
            barRadius: const Radius.circular(10),
            padding: EdgeInsets.zero,
            animation: true,
          ),
          const SizedBox(height: 12),
          const Text(
            "AI Scan recommended for duplicate optimization.",
            style: TextStyle(color: Colors.white60, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _folderCard(IconData icon, String title, int count, Color color) {
    return InkWell(
      onTap: () async {
        if (count == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Folder is empty!")),
          );
          return;
        }

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (c) => Center(
            child: Card(
              elevation: 5,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 25),
                    const Text("Handshaking with AI Server...", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Text("Fetching $count images", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
            ),
          ),
        );

        // Try to reset session before moving forward
        bool resetOk = await _resetBackendSession();
        List<String> paths = await StorageService.getImagePathsForFolder(title);

        if (!mounted) return;
        Navigator.pop(context);

        if (!resetOk) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("AI Server is Offline! Check Wi-Fi."), backgroundColor: Colors.redAccent),
          );
          return;
        }

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (c) => ScanResultScreen(
              folderName: title,
              imagePaths: paths,
              apiUrl: apiBaseUrl,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.grey.withOpacity(0.1)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 4),
            Text("$count Files", style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }
}
