import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class SoundpackInfo {
  final String id;
  final String name;
  final int fileCount;
  final int wordCount;
  final int sizeBytes;
  final bool isInstalled;

  SoundpackInfo({
    required this.id,
    required this.name,
    required this.fileCount,
    required this.wordCount,
    required this.sizeBytes,
    required this.isInstalled,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'fileCount': fileCount,
        'wordCount': wordCount,
        'sizeBytes': sizeBytes,
        'isInstalled': isInstalled,
      };
}

class SoundpackService {
  static final SoundpackService instance = SoundpackService._();
  SoundpackService._();

  Directory? _baseDir;
  final Map<String, Directory> _installedPacks = {};
  final Map<String, double> _downloadProgress = {};
  final Set<String> _activeOperations = {}; // 互斥锁：防止并发重入

  bool _initialized = false;

  Future<void> init({Directory? overrideDir}) async {
    if (_initialized && overrideDir == null) return;
    try {
      if (overrideDir != null) {
        _baseDir = overrideDir;
      } else {
        try {
          final docDir = await getApplicationDocumentsDirectory();
          _baseDir = Directory('${docDir.path}/soundpacks');
        } catch (_) {
          // 桌面测试与脱机环境兜底降级
          _baseDir = Directory('${Directory.systemTemp.path}/lazyvocab_soundpacks');
        }
      }
      if (!_baseDir!.existsSync()) {
        _baseDir!.createSync(recursive: true);
      }
      _cleanDanglingTmpDirs();
      await _scanInstalled();
      _initialized = true;
    } catch (e) {
      debugPrint('[SoundpackService] Init error: $e');
    }
  }

  /// 异常恢复：清理上次未完成解压留下的 .tmp_ 文件夹（配对操作与防裂保护）
  void _cleanDanglingTmpDirs() {
    if (_baseDir == null || !_baseDir!.existsSync()) return;
    try {
      for (final entity in _baseDir!.listSync()) {
        if (entity is Directory && entity.path.contains('.tmp_')) {
          try {
            entity.deleteSync(recursive: true);
            debugPrint('[SoundpackService] Cleaned dangling tmp dir: ${entity.path}');
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[SoundpackService] Cleanup error: $e');
    }
  }

  /// 扫描已安装词库目录
  Future<void> _scanInstalled() async {
    _installedPacks.clear();
    if (_baseDir == null || !_baseDir!.existsSync()) return;

    for (final entity in _baseDir!.listSync()) {
      if (entity is Directory) {
        final dirName = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (dirName.startsWith('.')) continue; // 跳过临时目录

        // 校验是否有 audio_cache 子目录或 manifest_index.json
        final audioDir = Directory('${entity.path}/audio_cache');
        final manifestFile = File('${entity.path}/manifest_index.json');
        if (audioDir.existsSync() || manifestFile.existsSync()) {
          _installedPacks[dirName] = entity;
        }
      }
    }
    debugPrint('[SoundpackService] Active packs: ${_installedPacks.keys.toList()}');
  }

  /// 快速检索本地已下载的音频文件（O(Packs) 秒查，支持空格自动下划线对齐）
  File? getAudioFile(String filename) {
    if (!_initialized || _installedPacks.isEmpty) return null;

    final cleanName = filename.startsWith('/') ? filename.substring(1) : filename;
    final baseName = cleanName.replaceFirst(RegExp(r'^audio_cache/'), '');
    final underName = baseName.replaceAll(RegExp(r'[\\/*?:"<>|\s]+'), '_');

    for (final packDir in _installedPacks.values) {
      var target = File('${packDir.path}/audio_cache/$baseName');
      if (target.existsSync()) {
        return target;
      }
      if (underName != baseName) {
        target = File('${packDir.path}/audio_cache/$underName');
        if (target.existsSync()) {
          return target;
        }
      }
    }
    return null;
  }

  /// 获取合并后的 manifest 索引表
  Future<Map<String, dynamic>> getMergedManifestIndex(
      Map<String, dynamic> bundledManifest) async {
    final merged = Map<String, dynamic>.from(bundledManifest);
    if (!_initialized) return merged;

    for (final packDir in _installedPacks.values) {
      final f = File('${packDir.path}/manifest_index.json');
      if (f.existsSync()) {
        try {
          final content = await f.readAsString();
          final data = jsonDecode(content);
          if (data is Map<String, dynamic>) {
            merged.addAll(data);
          }
        } catch (e) {
          debugPrint('[SoundpackService] Error reading manifest: $e');
        }
      }
    }
    return merged;
  }

  /// 获取所有语音包的就绪状态
  Future<Map<String, dynamic>> getStatus() async {
    final Map<String, dynamic> packs = {};
    const knownLexicons = {
      'primary': '小学英语必备词库',
      'junior': '初中中考大纲词库',
      'senior': '高中高考核心词库',
    };

    for (final entry in knownLexicons.entries) {
      final id = entry.key;
      final name = entry.value;
      final isInstalled = _installedPacks.containsKey(id);

      int sizeBytes = 0;
      int fileCount = 0;
      int wordCount = 0;

      if (isInstalled) {
        final dir = _installedPacks[id]!;
        final audioDir = Directory('${dir.path}/audio_cache');
        if (audioDir.existsSync()) {
          try {
            for (final f in audioDir.listSync()) {
              if (f is File) {
                fileCount++;
                sizeBytes += f.lengthSync();
              }
            }
          } catch (_) {}
        }
        final mf = File('${dir.path}/manifest_index.json');
        if (mf.existsSync()) {
          try {
            final data = jsonDecode(mf.readAsStringSync());
            if (data is Map) wordCount = data.length;
          } catch (_) {}
        }
      }

      packs[id] = {
        'id': id,
        'name': name,
        'isInstalled': isInstalled,
        'fileCount': fileCount,
        'wordCount': wordCount,
        'sizeBytes': sizeBytes,
        'progress': _downloadProgress[id] ?? (isInstalled ? 1.0 : 0.0),
        'isOperating': _activeOperations.contains(id),
      };
    }

    return {
      'packs': packs,
      'baseDir': _baseDir?.path ?? '',
    };
  }

  /// 原子解压与安全落盘
  Future<void> installFromZipBytes(String lexiconId, List<int> zipBytes) async {
    if (_baseDir == null) throw StateError('SoundpackService not initialized');
    if (_activeOperations.contains(lexiconId)) {
      throw StateError('当前词库正在操作中，请勿重复点击');
    }

    _activeOperations.add(lexiconId);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tmpDir = Directory('${_baseDir!.path}/.tmp_${lexiconId}_$timestamp');

    try {
      tmpDir.createSync(recursive: true);

      // 解压 archive
      final archive = ZipDecoder().decodeBytes(zipBytes);
      for (final file in archive) {
        final filename = file.name;
        if (file.isFile) {
          final outFile = File('${tmpDir.path}/$filename');
          outFile.parent.createSync(recursive: true);
          outFile.writeAsBytesSync(file.content as List<int>);
        }
      }

      // 如果 zip 内包了一层目录，自动展平
      final subDirs = tmpDir.listSync().whereType<Directory>().toList();
      final hasTopAudio = Directory('${tmpDir.path}/audio_cache').existsSync();
      if (!hasTopAudio && subDirs.length == 1) {
        final innerDir = subDirs.first;
        for (final item in innerDir.listSync()) {
          final target = '${tmpDir.path}/${item.uri.pathSegments.where((s) => s.isNotEmpty).last}';
          item.renameSync(target);
        }
        try { innerDir.deleteSync(); } catch (_) {}
      }

      // 原子替换正式目录
      final targetDir = Directory('${_baseDir!.path}/$lexiconId');
      if (targetDir.existsSync()) {
        targetDir.deleteSync(recursive: true);
      }
      tmpDir.renameSync(targetDir.path);

      await _scanInstalled();
      debugPrint('[SoundpackService] Successfully installed $lexiconId');
    } catch (e) {
      debugPrint('[SoundpackService] Install error: $e');
      if (tmpDir.existsSync()) {
        try { tmpDir.deleteSync(recursive: true); } catch (_) {}
      }
      rethrow;
    } finally {
      _activeOperations.remove(lexiconId);
    }
  }

  /// 从本地 zip 文件安全导入
  Future<void> installFromZipFile(String lexiconId, File file) async {
    if (!file.existsSync()) {
      throw FileSystemException('文件不存在', file.path);
    }
    final bytes = await file.readAsBytes();
    await installFromZipBytes(lexiconId, bytes);
  }

  /// 安全卸载词库语音包（释放存储空间）
  Future<void> uninstall(String lexiconId) async {
    if (_activeOperations.contains(lexiconId)) {
      throw StateError('当前词库正在操作中，请勿重复点击');
    }
    _activeOperations.add(lexiconId);
    try {
      final targetDir = Directory('${_baseDir!.path}/$lexiconId');
      if (targetDir.existsSync()) {
        targetDir.deleteSync(recursive: true);
      }
      _installedPacks.remove(lexiconId);
      await _scanInstalled();
      debugPrint('[SoundpackService] Uninstalled $lexiconId');
    } finally {
      _activeOperations.remove(lexiconId);
    }
  }
}
