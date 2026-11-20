import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

void main() => runApp(const DropLoadApp());

class DropLoadApp extends StatelessWidget {
  const DropLoadApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'DropLoad',
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: const Color(0xFF080B1D),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8D78FF), brightness: Brightness.dark),
    ),
    home: const DownloadPage(),
  );
}

class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key});
  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  final controller = TextEditingController();
  final downloads = <String>[];
  String status = 'Ready';
  double? progress;
  bool busy = false;
  bool cancelled = false;
  http.Client? activeClient;
  File? activeFile;

  @override
  void initState() {
    super.initState();
    loadHistory();
  }

  Future<File> historyFile() async => File('${(await getApplicationDocumentsDirectory()).path}/dropload_history.json');

  Future<void> loadHistory() async {
    try {
      final file = await historyFile();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return;
      final existing = <String>[];
      for (final item in decoded) {
        if (item is String && await File(item).exists()) existing.add(item);
      }
      if (mounted) setState(() => downloads.addAll(existing));
    } catch (_) {
      if (mounted) setState(() => status = 'Could not load saved history');
    }
  }

  Future<void> saveHistory() async {
    final file = await historyFile();
    await file.writeAsString(jsonEncode(downloads));
  }

  void cancelDownload() {
    if (!busy) return;
    cancelled = true;
    activeClient?.close();
    setState(() => status = 'Cancelling...');
  }


  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> startDownload() async {
    final uri = Uri.tryParse(controller.text.trim());
    if (uri == null || !['https', 'http'].contains(uri.scheme) || uri.host.isEmpty) {
      setState(() => status = 'Enter a valid direct HTTP/HTTPS file link');
      return;
    }
    cancelled = false;
    setState(() { busy = true; status = 'Connecting...'; progress = null; });
    final client = http.Client();
    activeClient = client;
    IOSink? sink;
    try {
      final response = await client.send(http.Request('GET', uri));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('HTTP ${response.statusCode}');
      }
      if ((response.headers['content-type'] ?? '').toLowerCase().contains('text/html')) {
        throw Exception('This is a webpage, not a direct file link');
      }
      final directory = Directory('${(await getApplicationDocumentsDirectory()).path}/DropLoad');
      await directory.create(recursive: true);
      final raw = uri.pathSegments.isEmpty ? 'download.bin' : uri.pathSegments.last;
      final safe = raw.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final filename = safe.isEmpty ? 'download.bin' : safe;
      final file = File('${directory.path}/${DateTime.now().millisecondsSinceEpoch}_$filename');
      activeFile = file;
      sink = file.openWrite();
      var received = 0;
      await for (final chunk in response.stream) {
        if (cancelled) throw const SocketException('Download cancelled');
        sink.add(chunk);
        received += chunk.length;
        if (mounted) {
          setState(() {
            status = 'Downloading...';
            final total = response.contentLength;
            progress = total == null || total == 0 ? null : received / total;
          });
        }
      }
      if (cancelled) throw const SocketException('Download cancelled');
      await sink.flush();
      await sink.close();
      sink = null;
      if (mounted) setState(() { status = 'Download complete'; progress = 1; downloads.insert(0, file.path); });
      await saveHistory();
    } catch (error) {
      if (activeFile != null) {
        try { await sink?.close(); sink = null; await activeFile!.delete(); } catch (_) {}
      }
      if (mounted) setState(() => status = cancelled ? 'Download cancelled' : 'Failed: $error');
    } finally {
      await sink?.close();
      client.close();
      activeClient = null;
      activeFile = null;
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('◈ DropLoad'), backgroundColor: Colors.transparent),
    body: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: ListView(padding: const EdgeInsets.all(24), children: [
        const SizedBox(height: 32),
        const Icon(Icons.view_in_ar_rounded, size: 92, color: Color(0xFF9D8BFF)),
        const SizedBox(height: 16),
        const Text('Download Studio', textAlign: TextAlign.center,
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('A futuristic home for your downloads', textAlign: TextAlign.center),
        const SizedBox(height: 32),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(colors: [Color(0xFF29305C), Color(0xFF12182D)]),
            border: Border.all(color: const Color(0xFF666DA5)),
            boxShadow: const [BoxShadow(color: Color(0x442D208E), blurRadius: 30)],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Paste a direct file URL', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            TextField(controller: controller, enabled: !busy,
              decoration: const InputDecoration(border: OutlineInputBorder(),
                hintText: 'https://example.com/video.mp4')),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: busy ? null : startDownload,
              icon: const Icon(Icons.download_rounded), label: const Text('Download')),
            if (busy) TextButton.icon(onPressed: cancelDownload,
              icon: const Icon(Icons.cancel_outlined), label: const Text('Cancel download')),
            const SizedBox(height: 16),
            Text(status),
            if (busy || progress != null) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(value: progress),
            ],
          ]),
        ),
        const SizedBox(height: 24),
        const Text('This version supports direct downloadable HTTP/HTTPS files only. Website video extraction, playlists, format conversion and quality selection are planned features.'),
        const SizedBox(height: 24),
        const Text('Saved downloads', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        for (final path in downloads) ListTile(
          leading: const Icon(Icons.check_circle_outline),
          title: Text(path.split(Platform.pathSeparator).last),
          subtitle: SelectableText(path),
        ),
      ]),
    )),
  );
}
