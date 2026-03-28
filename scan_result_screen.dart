import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:percent_indicator/percent_indicator.dart';
import 'storage_service.dart';

class ScanResultScreen extends StatefulWidget {
  final String folderName;
  final List<String> imagePaths;
  final String apiUrl;

  const ScanResultScreen({
    super.key, 
    required this.folderName, 
    required this.imagePaths, 
    required this.apiUrl
  });

  @override
  State<ScanResultScreen> createState() => _ScanResultScreenState();
}

class _ScanResultScreenState extends State<ScanResultScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool isScanning = false;
  String status = "Ready to Scan";
  int currentProgress = 0;
  
  List<dynamic> exactDuplicates = []; 
  List<dynamic> nearDuplicates = [];  
  List<String> uniqueImages = [];     
  
  // --- SELECTIVE SAVE LOGIC ---
  // Indha set-la irukura images-ah bulk delete thavirkkum
  Set<String> savedNearDuplicates = {}; 

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  // --- BULK DELETE LOGIC ---
  Future<void> bulkDeleteDuplicates() async {
    List<String> pathsToDelete = [];

    // 1. All Exact duplicates are marked for deletion
    for (var d in exactDuplicates) {
      String fileName = d['pair'][0];
      String fullPath = widget.imagePaths.firstWhere((p) => p.contains(fileName), orElse: () => "");
      if (fullPath.isNotEmpty) pathsToDelete.add(fullPath);
    }

    // 2. Near duplicates (only if NOT saved by user)
    for (var d in nearDuplicates) {
      String fileName = d['pair'][0];
      String fullPath = widget.imagePaths.firstWhere((p) => p.contains(fileName), orElse: () => "");
      if (fullPath.isNotEmpty && !savedNearDuplicates.contains(fullPath)) {
        pathsToDelete.add(fullPath);
      }
    }

    if (pathsToDelete.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No images selected for deletion")));
      return;
    }

    bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Bulk Delete"),
        content: Text("Are you sure you want to delete ${pathsToDelete.length} images from your gallery?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("CANCEL")),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text("DELETE ALL", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))
          ),
        ],
      ),
    );

    if (confirm == true) {
      bool success = await StorageService.deletePermanent(pathsToDelete);
      if (success) {
        setState(() {
          // Clear lists after deletion
          exactDuplicates.clear();
          nearDuplicates.removeWhere((d) {
             String fullPath = widget.imagePaths.firstWhere((p) => p.contains(d['pair'][0]), orElse: () => "");
             return !savedNearDuplicates.contains(fullPath);
          });
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Selected duplicates deleted successfully!")));
      }
    }
  }

  // --- SCAN LOGIC (Existing) ---
  Future<void> startScan() async {
    if (widget.imagePaths.isEmpty) return;
    setState(() {
      isScanning = true;
      currentProgress = 0;
      exactDuplicates.clear();
      nearDuplicates.clear();
      uniqueImages.clear();
      savedNearDuplicates.clear();
      status = "Starting AI Batch Analysis...";
    });

    int batchSize = 10; 
    int totalImages = widget.imagePaths.length;

    try {
      for (int i = 0; i < totalImages; i += batchSize) {
        int end = (i + batchSize < totalImages) ? i + batchSize : totalImages;
        List<String> currentBatch = widget.imagePaths.sublist(i, end);

        setState(() {
          status = "Scanning $end of $totalImages images...";
          currentProgress = end; 
        });

        var request = http.MultipartRequest('POST', Uri.parse("${widget.apiUrl}/compare"));
        for (String path in currentBatch) {
          request.files.add(await http.MultipartFile.fromPath('files', path));
        }

        var streamedResponse = await request.send().timeout(const Duration(seconds: 120));
        var response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200) {
          var data = jsonDecode(response.body);
          List<dynamic> batchDups = data['duplicates'] ?? [];
          Set<String> duplicateNamesInBatch = {};

          setState(() {
            for (var d in batchDups) {
              String fileName = d['pair'][0].toString();
              duplicateNamesInBatch.add(fileName);
              if (d['status'] == "Exact Duplicate") {
                exactDuplicates.add(d);
              } else {
                nearDuplicates.add(d);
              }
            }
            for (String fullPath in currentBatch) {
              String name = fullPath.split('/').last;
              if (!duplicateNamesInBatch.any((dup) => dup.contains(name))) {
                uniqueImages.add(fullPath);
              }
            }
          });
        }
      }
      setState(() { status = "Scan Complete!"; isScanning = false; });
    } catch (e) {
      setState(() { status = "Connection Error!"; isScanning = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    double progress = widget.imagePaths.isEmpty ? 0 : currentProgress / widget.imagePaths.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.folderName),
        actions: [
          if (!isScanning && (exactDuplicates.isNotEmpty || nearDuplicates.isNotEmpty))
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
              onPressed: bulkDeleteDuplicates,
              tooltip: "Delete All Unsaved Duplicates",
            )
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: "Exact (${exactDuplicates.length})"),
            Tab(text: "Near (${nearDuplicates.length})"),
            Tab(text: "Unique (${uniqueImages.length})"),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildProgressHeader(progress),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildGrid(exactDuplicates, isNear: false),
                _buildGrid(nearDuplicates, isNear: true),
                _buildUniqueGrid(),
              ],
            ),
          ),
          _buildBottomAction(),
        ],
      ),
    );
  }

  Widget _buildProgressHeader(double progress) {
    return Container(
      padding: const EdgeInsets.all(15),
      color: Colors.blue.withOpacity(0.05),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(status, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text("$currentProgress / ${widget.imagePaths.length}", 
                   style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 10),
          LinearPercentIndicator(
            lineHeight: 12.0,
            percent: progress,
            barRadius: const Radius.circular(10),
            progressColor: Colors.blueAccent,
            backgroundColor: Colors.grey.shade300,
            animation: true,
            animateFromLastPercent: true,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomAction() {
    if (isScanning) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.all(20),
      child: SizedBox(
        width: double.infinity,
        height: 55,
        child: ElevatedButton.icon(
          onPressed: startScan,
          icon: const Icon(Icons.psychology_outlined),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueAccent, 
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
          ),
          label: const Text("RE-SCAN FOLDER", style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildGrid(List<dynamic> items, {required bool isNear}) {
    if (items.isEmpty) return const Center(child: Text("No items found."));
    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 1, mainAxisExtent: 300, mainAxisSpacing: 15
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        String fileName = items[index]['pair'][0];
        String fullPath = widget.imagePaths.firstWhere((p) => p.contains(fileName), orElse: () => "");
        if (fullPath == "") return const SizedBox();

        bool isSaved = savedNearDuplicates.contains(fullPath);

        return Card(
          clipBehavior: Clip.antiAlias,
          elevation: isSaved ? 0 : 3,
          color: isSaved ? Colors.green.shade50 : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: BorderSide(color: isSaved ? Colors.green : Colors.transparent, width: 2)
          ),
          child: Column(
            children: [
              Expanded(child: Image.file(File(fullPath), fit: BoxFit.cover, width: double.infinity)),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(isNear ? "Near-Duplicate" : "Exact Match", 
                             style: TextStyle(color: isNear ? Colors.orange : Colors.red, fontWeight: FontWeight.bold)),
                        Text("Sim: ${items[index]['similarity']}%", style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                    if (isNear) ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          if (isSaved) savedNearDuplicates.remove(fullPath);
                          else savedNearDuplicates.add(fullPath);
                        });
                      },
                      icon: Icon(isSaved ? Icons.check : Icons.bookmark_add_outlined, size: 18),
                      label: Text(isSaved ? "KEEPING" : "SAVE"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isSaved ? Colors.green : Colors.blueGrey.shade50,
                        foregroundColor: isSaved ? Colors.white : Colors.blueGrey,
                        elevation: 0
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
        );
      },
    );
  }

  Widget _buildUniqueGrid() {
    if (uniqueImages.isEmpty) return const Center(child: Text("No unique images."));
    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 5, mainAxisSpacing: 5),
      itemCount: uniqueImages.length,
      itemBuilder: (context, index) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(File(uniqueImages[index]), fit: BoxFit.cover),
      ),
    );
  }
}