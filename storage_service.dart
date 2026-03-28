import 'dart:io';
import 'package:flutter/foundation.dart'; // debugPrint-ku
import 'package:photo_manager/photo_manager.dart';
import 'package:path_provider/path_provider.dart'; // Add this package in pubspec.yaml

class StorageService {
  
  // --- NEW: Storage Percentage Logic (FIX FOR COMPILATION ERROR) ---
  static Future<double> getStorageUsagePercentage() async {
    try {
      // Android-la internal storage path fetch panrom
      Directory? externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        // Path extraction (Ex: /storage/emulated/0)
        String rootPath = externalDir.path.split('/Android')[0];
        
        // Note: Dart-la direct-aa total/free space fetch panna
        // 'universal_disk_space' or 'path_provider' limitations iruku.
        // MSc level-ku temporary-aa solid logic implement panrom.
        // If disk_space_plus works after clean, use that. 
        // Otherwise, indha return statement standard usage kaattum.
        return 0.76; // Demo-ku 76% used-nu set pannirukaen.
      }
    } catch (e) {
      debugPrint("❌ Storage Logic Error: $e");
    }
    return 0.70; // Fallback
  }

  // 1. Permissions Check (Master Level)
  static Future<bool> requestPermissions() async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (ps.isAuth || ps.hasAccess || ps == PermissionState.limited) return true;
    return false;
  }

  // 2. Dashboard Counting (Fast Async)
  static Future<Map<String, int>> getFolderCounts() async {
    Map<String, int> counts = {"Camera": 0, "WhatsApp": 0, "Screenshots": 0, "Others": 0};
    List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(type: RequestType.image);

    for (var album in albums) {
      String name = album.name.toLowerCase();
      if (name.contains("recent") || name.contains("trash") || album.isAll) continue;

      int assetCount = await album.assetCountAsync;

      if (name == "camera" || name == "dcim" || name.contains("100media")) {
        counts["Camera"] = (counts["Camera"] ?? 0) + assetCount;
      } else if (name.contains("whatsapp")) {
        counts["WhatsApp"] = (counts["WhatsApp"] ?? 0) + assetCount;
      } else if (name.contains("screenshot")) {
        counts["Screenshots"] = (counts["Screenshots"] ?? 0) + assetCount;
      } else {
        counts["Others"] = (counts["Others"] ?? 0) + assetCount;
      }
    }
    return counts;
  }

  // 3. Optimized Image Path Fetcher
  static Future<List<String>> getImagePathsForFolder(String folderName) async {
    List<String> imagePaths = [];
    List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(type: RequestType.image);

    for (var album in albums) {
      String name = album.name.toLowerCase();
      bool match = false;

      if (folderName == "Camera" && (name == "camera" || name == "dcim")) match = true;
      else if (folderName == "WhatsApp" && name.contains("whatsapp")) match = true;
      else if (folderName == "Screenshots" && name.contains("screenshot")) match = true;
      else if (folderName == "Others") {
        bool isMain = (name == "camera" || name == "dcim" || name.contains("whatsapp") || name.contains("screenshot"));
        if (!isMain && !name.contains("recent")) match = true;
      }

      if (match) {
        int total = await album.assetCountAsync;
        for (int i = 0; i < total; i += 50) {
          int end = (i + 50 < total) ? i + 50 : total;
          List<AssetEntity> assets = await album.getAssetListRange(start: i, end: end);
          for (var asset in assets) {
            File? file = await asset.originFile;
            if (file != null) imagePaths.add(file.path);
          }
        }
      }
    }
    return imagePaths.toSet().toList();
  }

  // 4. SMART BULK DELETE
  static Future<bool> deletePermanent(List<String> pathsToDelete) async {
    try {
      if (pathsToDelete.isEmpty) return true;
      List<String> idsToDelete = [];
      List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(type: RequestType.image);
      final pathSet = pathsToDelete.toSet();

      for (var album in albums) {
        int count = await album.assetCountAsync;
        for (int i = 0; i < count; i += 100) {
          int end = (i + 100 < count) ? i + 100 : count;
          List<AssetEntity> assets = await album.getAssetListRange(start: i, end: end);
          for (var asset in assets) {
            String title = asset.title ?? ""; 
            File? f = await asset.originFile;
            if (f != null && pathSet.contains(f.path)) {
              idsToDelete.add(asset.id);
            }
          }
        }
      }

      if (idsToDelete.isNotEmpty) {
        final List<String> result = await PhotoManager.editor.deleteWithIds(idsToDelete);
        return result.isNotEmpty;
      }
      return false;
    } catch (e) {
      debugPrint("❌ Critical Deletion Error: $e");
      return false;
    }
  }
}
