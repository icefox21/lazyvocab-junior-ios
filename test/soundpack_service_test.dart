import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_player/soundpack_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SoundpackService install, query and uninstall test', () async {
    final zipFile = File(r'I:\AI\懒得记单词mimo\dist\soundpacks\pack_primary.zip');
    expect(zipFile.existsSync(), isTrue, reason: 'pack_primary.zip must exist');

    final service = SoundpackService.instance;
    await service.init();

    // 1. 测试安装
    await service.installFromZipFile('primary', zipFile);

    // 2. 测试状态查询
    final status = await service.getStatus();
    final packs = status['packs'] as Map<String, dynamic>;
    expect(packs.containsKey('primary'), isTrue);
    expect(packs['primary']['isInstalled'], isTrue);
    expect(packs['primary']['wordCount'], equals(1229));
    expect(packs['primary']['fileCount'], equals(9832));

    // 3. 测试音频文件检索
    final audioFile = service.getAudioFile('audio_cache/bag_step1_word.mp3');
    expect(audioFile, isNotNull);
    expect(audioFile!.existsSync(), isTrue);
    expect(audioFile.lengthSync(), greaterThan(1000));

    // 4. 测试 Manifest 索引合并
    final merged = await service.getMergedManifestIndex({'sample': true});
    expect(merged['sample'], isTrue);
    expect(merged['bag'], isTrue);
    expect(merged['crayon'], isTrue);

    // 5. 测试安全卸载
    await service.uninstall('primary');
    final afterStatus = await service.getStatus();
    final afterPacks = afterStatus['packs'] as Map<String, dynamic>;
    expect(afterPacks['primary']['isInstalled'], isFalse);

    // 验证文件已彻底移除
    final audioAfter = service.getAudioFile('audio_cache/bag_step1_word.mp3');
    expect(audioAfter, isNull);
  });
}
