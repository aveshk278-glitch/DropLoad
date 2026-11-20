import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// A YouTube video with the formats YouTube actually returned for it.
/// Nothing here is invented: the lists come straight from the manifest.
class YouTubeVideo {
  YouTubeVideo({required this.video, required this.manifest});

  /// Metadata (title, author, duration) from the watch page.
  final Video video;

  /// The stream manifest returned by YouTube for this video.
  final StreamManifest manifest;

  /// Muxed (video + audio) streams, best quality first.
  /// These are the only ready-to-watch downloads; YouTube caps them
  /// at 360p, so this list is short on purpose.
  List<MuxedStreamInfo> get muxed => manifest.muxed.sortByVideoQuality();

  /// Video-only streams, best quality first. No audio in these files.
  List<VideoOnlyStreamInfo> get videoOnly =>
      manifest.videoOnly.sortByVideoQuality();

  /// Audio-only streams, highest bitrate first.
  List<AudioOnlyStreamInfo> get audioOnly => manifest.audioOnly.sortByBitrate();
}

/// Talks to YouTube with youtube_explode_dart (pure Dart, no binary,
/// no API key, no account) and downloads the stream the user picked.
///
/// Limits, stated honestly:
/// * Only YouTube. Other video sites are not supported yet.
/// * Only formats YouTube returns for that video; nothing is invented.
/// * Muxed (video + audio) streams stop at 360p. Higher qualities are
///   video-only and have no sound until FFmpeg merging is added.
/// * Age-restricted, private, removed, paywalled and live videos cannot
///   be downloaded with this method, and are never worked around.
class VideoService {
  YoutubeExplode? _client;

  /// True when [raw] is a YouTube video link (watch, youtu.be, Shorts,
  /// live, embed) with an id that can be read from it.
  bool isYouTubeUrl(String raw) => extractVideoId(raw) != null;

  /// Reads the 11-character video id out of a YouTube link, or null when
  /// the link is not a YouTube video link.
  String? extractVideoId(String raw) {
    final trimmed = raw.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    final isYouTubeHost = host == 'youtube.com' ||
        host.endsWith('.youtube.com') ||
        host == 'youtu.be' ||
        host.endsWith('.youtu.be') ||
        host == 'youtube-nocookie.com' ||
        host.endsWith('.youtube-nocookie.com');
    if (!isYouTubeHost) return null;
    final parsed = VideoId.parseVideoId(trimmed);
    if (parsed != null) return parsed;
    // Shorts / live / embed links with a query string defeat the
    // library's end-anchored patterns, so read the id from the path.
    final segments = uri.pathSegments;
    if (segments.length >= 2 &&
        (segments[0] == 'shorts' ||
            segments[0] == 'live' ||
            segments[0] == 'embed')) {
      final id = segments[1];
      if (VideoId.validateVideoId(id)) return id;
    }
    return null;
  }

  /// True when [raw] points at a known video site other than YouTube and
  /// does not look like a direct file link. Those sites are not
  /// supported yet, and saying so beats saving their HTML page as a file.
  bool isUnsupportedVideoSite(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) return false;
    if (_looksLikeDirectFile(uri)) return false;
    final host = uri.host.toLowerCase();
    return _unsupportedVideoHosts
        .any((site) => host == site || host.endsWith('.$site'));
  }

  static const _unsupportedVideoHosts = <String>[
    'instagram.com',
    'tiktok.com',
    'facebook.com',
    'fb.watch',
    'x.com',
    'twitter.com',
    'vimeo.com',
    'dailymotion.com',
    'dai.ly',
    'reddit.com',
    'twitch.tv',
    'snapchat.com',
    'pinterest.com',
    'rumble.com',
  ];

  static bool _looksLikeDirectFile(Uri uri) {
    final path = uri.path.toLowerCase();
    return _directFileExtensions.any(path.endsWith);
  }

  static const _directFileExtensions = <String>[
    '.mp4',
    '.webm',
    '.mkv',
    '.mov',
    '.avi',
    '.mp3',
    '.m4a',
    '.aac',
    '.ogg',
    '.flac',
    '.wav',
    '.zip',
    '.pdf',
    '.apk',
    '.exe',
    '.dmg',
  ];

  /// Fetches the video metadata and the real format list for [url].
  /// Throws the library's own exceptions on unplayable, paywalled or
  /// unavailable videos; the UI turns those into plain-language messages.
  /// A fresh client is opened per video: the library notes that YouTube
  /// often refuses a second download from the same manifest.
  Future<YouTubeVideo> fetchVideo(String url) async {
    closeCurrent();
    final client = YoutubeExplode();
    _client = client;
    try {
      final video = await client.videos.get(url);
      final manifest = await client.videos.streams.getManifest(video.id);
      return YouTubeVideo(video: video, manifest: manifest);
    } catch (_) {
      closeCurrent();
      rethrow;
    }
  }

  /// Downloads [stream] into [directory] under a safe file name built
  /// from the video title and the chosen quality. Calls [onProgress]
  /// with (bytesReceived, totalBytes) as chunks arrive. Throws a
  /// [SocketException] with 'Download cancelled' when [isCancelled]
  /// becomes true, matching the direct-download behaviour.
  Future<File> downloadStream({
    required YouTubeVideo video,
    required StreamInfo stream,
    required Directory directory,
    required void Function(int received, int total) onProgress,
    required bool Function() isCancelled,
  }) async {
    final client = _client;
    if (client == null) {
      throw StateError('No YouTube client is open');
    }
    final file = File(
        '${directory.path}/${fileNameFor(video.video.title, stream)}');
    final sink = file.openWrite();
    var received = 0;
    final total = stream.size.totalBytes;
    try {
      await for (final chunk in client.videos.streams.get(stream)) {
        if (isCancelled()) {
          throw const SocketException('Download cancelled');
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress(received, total);
      }
      await sink.flush();
      await sink.close();
      return file;
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {}
      try {
        await file.delete();
      } catch (_) {}
      rethrow;
    }
  }

  /// File name for a picked format, e.g. `1700000000000_My_Video_360p.mp4`
  /// or `1700000000000_My_Video_audio.mp4` for audio-only streams.
  /// The extension is the stream's real container, never a guess.
  String fileNameFor(String title, StreamInfo stream) {
    String label;
    if (stream is MuxedStreamInfo) {
      label = stream.qualityLabel;
    } else if (stream is VideoOnlyStreamInfo) {
      label = '${stream.qualityLabel}_video-only';
    } else if (stream is AudioOnlyStreamInfo) {
      label = 'audio';
    } else {
      label = 'video';
    }
    final clean = title
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final base = clean.isEmpty ? 'youtube_video' : clean;
    final short = base.length > 60 ? base.substring(0, 60) : base;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return '${stamp}_${short}_$label.${stream.container.name}';
  }

  /// Plain-language explanation of a YouTube failure. Paywalled and
  /// restricted videos are reported as unsupported, never worked around.
  String friendlyError(Object error) {
    if (error is VideoRequiresPurchaseException) {
      return 'This video is paywalled or a paid preview and cannot be downloaded here.';
    }
    if (error is VideoUnavailableException) {
      return 'This video is unavailable (removed or private).';
    }
    if (error is VideoUnplayableException) {
      return 'This video cannot be played here (age-restricted, region-blocked, private or a live stream).';
    }
    if (error is RequestLimitExceededException) {
      return 'YouTube is rate-limiting requests right now. Try again later.';
    }
    if (error is ArgumentError) {
      return 'That is not a valid YouTube video link.';
    }
    return error.toString();
  }

  /// Aborts an in-flight manifest fetch or stream download and releases
  /// the YouTube client. Safe to call when nothing is running.
  void closeCurrent() {
    final client = _client;
    _client = null;
    client?.close();
  }

  /// Cancels any in-flight YouTube work. Called from Cancel and dispose.
  void cancelCurrent() => closeCurrent();

  void dispose() => closeCurrent();
}
