import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'soundpack_service.dart';

const _ttsChannel = MethodChannel('lazyvocab/tts');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0B1020),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const LazyVocabApp());
}

class LazyVocabApp extends StatelessWidget {
  const LazyVocabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '懒得记单词',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF080D1A),
      ),
      home: const SplashGate(),
    );
  }
}

/// 闪屏展示 2.8 秒，可点击跳过直接进 UI
class SplashGate extends StatefulWidget {
  const SplashGate({super.key});

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool _done = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 2800), () {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _skip() {
    _timer?.cancel();
    if (mounted) setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return const DashboardShell();
    return Scaffold(
      backgroundColor: const Color(0xFF080D1A),
      body: GestureDetector(
        onTap: _skip,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/splash.png',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const _FallbackSplash(),
            ),
            const Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: 36),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFFFFD166),
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      '初中中考全量词库 · 纯正双语原声装载中...',
                      style: TextStyle(color: Color(0xFF5C6784), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FallbackSplash extends StatelessWidget {
  const _FallbackSplash();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF080D1A),
      child: const Center(
        child: Text(
          '懒得记单词',
          style: TextStyle(
            color: Color(0xFFFFD166),
            fontSize: 42,
            fontWeight: FontWeight.w800,
            letterSpacing: 4,
          ),
        ),
      ),
    );
  }
}

class DashboardShell extends StatefulWidget {
  const DashboardShell({super.key});

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell>
    with WidgetsBindingObserver {
  HttpServer? _server;
  WebViewController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ttsChannel.setMethodCallHandler((call) async {
      if (call.method == 'ttsDone') {
        _controller?.runJavaScript(
            'try{if(window.__ttsDone){var f=window.__ttsDone;window.__ttsDone=null;clearTimeout(window.__ttsWatchdog);f();}}catch(e){}');
      }
    });
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ttsChannel.invokeMethod('stop');
    _server?.close(force: true);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _ttsChannel.invokeMethod('stop');
      _controller?.runJavaScript(
          'try{window.speechSynthesis&&speechSynthesis.cancel();sharedAudio&&sharedAudio.pause();}catch(e){}');
    } else if (state == AppLifecycleState.resumed) {
      _controller?.runJavaScript(
          'try{window.__lazyResume&&window.__lazyResume();}catch(e){}');
    }
  }

  Future<void> _boot() async {
    try {
      await SoundpackService.instance.init();
      // 固定端口：localStorage 绑定 origin，随机端口会导致每次启动进度/设置全丢
      HttpServer? server;
      try {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 18787);
      } catch (_) {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      }
      _server = server;
      server.listen(_handleRequest);
      final uri = Uri.parse('http://127.0.0.1:${server.port}/dashboard.html?edition=junior');
      
      late final PlatformWebViewControllerCreationParams params;
      if (WebViewPlatform.instance is WebKitWebViewPlatform) {
        params = WebKitWebViewControllerCreationParams(
          allowsInlineMediaPlayback: true,
          mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
        );
      } else {
        params = const PlatformWebViewControllerCreationParams();
      }

      final c = WebViewController.fromPlatformCreationParams(params)
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF0B1020))
        ..setNavigationDelegate(
          NavigationDelegate(
            onWebResourceError: (e) {
              debugPrint('web error: ${e.errorCode} ${e.description}');
            },
          ),
        )
        ..addJavaScriptChannel(
          'NativeTTS',
          onMessageReceived: (msg) async {
            try {
              final data = jsonDecode(msg.message) as Map<String, dynamic>;
              final text = (data['text'] as String?) ?? '';
              final lang = (data['lang'] as String?) ?? 'zh-CN';
              await _ttsChannel
                  .invokeMethod('speak', {'text': text, 'lang': lang});
            } catch (e) {
              debugPrint('NativeTTS error: $e');
              _controller?.runJavaScript(
                  'try{if(window.__ttsDone){var f=window.__ttsDone;window.__ttsDone=null;f();}}catch(e){}');
            }
          },
        )
        ..loadRequest(uri);

      if (c.platform is AndroidWebViewController) {
        try {
          (c.platform as AndroidWebViewController).setMediaPlaybackRequiresUserGesture(false);
        } catch (e) {
          debugPrint('android webview settings: $e');
        }
      }

      setState(() => _controller = c);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _handleRequest(HttpRequest req) async {
    try {
      var path = req.uri.path;
      if (path == '/' || path.isEmpty) path = '/dashboard.html';
      if (path.contains('..')) {
        req.response.statusCode = 400;
        await req.response.close();
        return;
      }
      if (path == '/api/soundpacks/status') {
        final status = await SoundpackService.instance.getStatus();
        req.response.statusCode = 200;
        req.response.headers.contentType =
            ContentType('application', 'json', charset: 'utf-8');
        req.response.write(jsonEncode(status));
        await req.response.close();
        return;
      }
      if (path == '/api/soundpacks/uninstall' && req.method == 'POST') {
        final body = await utf8.decoder.bind(req).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final id = (json['lexiconId'] as String?) ?? '';
        if (id.isNotEmpty) {
          await SoundpackService.instance.uninstall(id);
        }
        req.response.statusCode = 200;
        req.response.headers.contentType =
            ContentType('application', 'json', charset: 'utf-8');
        req.response.write(jsonEncode({'ok': true}));
        await req.response.close();
        return;
      }
      if (path == '/api/soundpacks/import_local' && req.method == 'POST') {
        final body = await utf8.decoder.bind(req).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final id = (json['lexiconId'] as String?) ?? '';
        final filePath = (json['filePath'] as String?) ?? '';
        if (id.isNotEmpty && filePath.isNotEmpty) {
          await SoundpackService.instance.installFromZipFile(id, File(filePath));
        }
        req.response.statusCode = 200;
        req.response.headers.contentType =
            ContentType('application', 'json', charset: 'utf-8');
        req.response.write(jsonEncode({'ok': true}));
        await req.response.close();
        return;
      }
      if (path == '/api/audio_cache_index') {
        Map<String, dynamic> bundled = {};
        try {
          final data = await rootBundle.load('assets/www/audio_cache/manifest_index.json');
          final str = utf8.decode(data.buffer.asUint8List());
          bundled = jsonDecode(str) as Map<String, dynamic>;
        } catch (_) {}
        final merged = await SoundpackService.instance.getMergedManifestIndex(bundled);
        req.response.statusCode = 200;
        req.response.headers.contentType =
            ContentType('application', 'json', charset: 'utf-8');
        req.response.write(jsonEncode(merged));
        await req.response.close();
        return;
      }
      // 优先级 1: 检查沙盒已下载的词库语音包切片
      if (path.startsWith('/audio_cache/')) {
        final localFile = SoundpackService.instance.getAudioFile(path);
        if (localFile != null && localFile.existsSync()) {
          req.response.statusCode = 200;
          req.response.headers.contentType = _mime(path);
          req.response.headers.set('Cache-Control', 'public, max-age=86400');
          await req.response.addStream(localFile.openRead());
          await req.response.close();
          return;
        }
      }
      // 优先级 2: 兜底检索 APK 内置 assets
      final data = await rootBundle.load('assets/www$path');
      final bytes = data.buffer.asUint8List();
      req.response.statusCode = 200;
      req.response.headers.contentType = _mime(path);
      req.response.headers.set('Cache-Control', 'no-cache');
      req.response.add(bytes);
      await req.response.close();
    } catch (_) {
      try {
        req.response.statusCode = 404;
        await req.response.close();
      } catch (_) {}
    }
  }

  ContentType _mime(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.html')) return ContentType.html;
    if (p.endsWith('.js')) {
      return ContentType('text', 'javascript', charset: 'utf-8');
    }
    if (p.endsWith('.css')) return ContentType('text', 'css', charset: 'utf-8');
    if (p.endsWith('.json')) {
      return ContentType('application', 'json', charset: 'utf-8');
    }
    if (p.endsWith('.png')) return ContentType('image', 'png');
    if (p.endsWith('.mp3')) return ContentType('audio', 'mpeg');
    if (p.endsWith('.opus') || p.endsWith('.ogg')) {
      return ContentType('audio', 'ogg');
    }
    if (p.endsWith('.m4a') || p.endsWith('.aac')) {
      return ContentType('audio', 'mp4');
    }
    if (p.endsWith('.ttf')) return ContentType('font', 'ttf');
    return ContentType.binary;
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Text(_error!, style: const TextStyle(color: Colors.red)),
        ),
      );
    }
    if (_controller == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF080D1A),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFFFD166)),
        ),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0B1020),
      body: SafeArea(
        child: WebViewWidget(controller: _controller!),
      ),
    );
  }
}
