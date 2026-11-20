# DropLoad

Flutter cross-platform downloader starter for Android, Windows, macOS and Linux.

## Implemented
- Dark futuristic-style interface
- Direct HTTP/HTTPS file downloads with progress display
- Multiple direct URLs queued sequentially
- Paste links from clipboard
- Copy downloaded file paths and remove history entries
- Cancel active download
- Persist completed download paths in local JSON and reload on app start
- YouTube video download with real quality selection (see below)
- GitHub Actions builds for four platforms

## YouTube downloads

Paste a YouTube video link (watch, youtu.be, Shorts, live, embed). The app
fetches the formats YouTube actually returns for that video and shows a
picker — nothing is invented:

- **Video + audio** — muxed streams, ready to watch. YouTube caps these at
  360p, so this list is short on purpose.
- **Video only** — up to the highest quality YouTube returns (1080p, 4K,
  …). These files have **no sound**.
- **Audio only** — highest bitrate first, in the stream's real container.

Honest limits:

- Only YouTube. Other video sites (Instagram, TikTok, Facebook, X,
  Vimeo, …) are not supported yet — the app says so instead of saving
  their web page as a file.
- No FFmpeg is bundled, so video-only and audio-only streams are not
  merged. Higher video + audio quality needs FFmpeg merging (planned).
- Age-restricted, private, removed, paywalled/premium and live videos
  cannot be downloaded with this method. The app reports that plainly
  and never tries to work around it.
- No API key, no account, no paid service. Extraction uses
  `youtube_explode_dart` (pure Dart, BSD-3-Clause — see
  THIRD_PARTY_NOTICES.md), which reads YouTube's public pages.
- YouTube sometimes throttles or rate-limits extraction; a failed video
  shows the real reason. Download only content you are authorized to save.

## Not yet implemented
- Video downloads from sites other than YouTube (no yt-dlp sidecar yet;
  there is no official yt-dlp standalone binary for Android)
- Playlist parsing
- Audio conversion, pause/resume, parallel queue, full 3D rendering

## Builds
See [GitHub Actions](https://github.com/aveshk278-glitch/DropLoad/actions) for the latest run and downloadable artifacts. Build success does not guarantee runtime correctness; test on target devices. Only download content you are authorized to save.
