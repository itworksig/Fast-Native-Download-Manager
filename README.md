# Fast Native Download Manager

A native macOS download manager prototype inspired by IDM.

## Run

```bash
swift run FastNativeDownloadManager
```

You can also open the folder in Xcode as a Swift Package.

For the packaged `.app`, use `Packaging/FastNativeDownloadManager-Info.plist` so macOS registers the `fastndm://` URL scheme used by legacy browser handoff paths.

## Current UI Prototype

- IDM-style toolbar for adding URLs, starting, pausing, deleting, scheduling, and opening the grabber.
- Sidebar categories for active, unfinished, finished, video, archives, documents, and software downloads.
- Download task table with progress, speed, ETA, connection count, and status.
- Right inspector panel for advanced capture, detected resources, resume support, segmented connections, and capture rules.

## Download Engine

- Supports HTTP and HTTPS URLs.
- Streams downloads with `URLSessionDataTask` so progress, speed, and ETA update live.
- Probes files with `HEAD`, then uses multiple concurrent HTTP `Range` requests when the server supports byte ranges.
- Splits files into segments, writes each segment into its byte range, and finalizes by moving the preallocated partial file into place.
- Preallocates large files with Darwin `F_PREALLOCATE` plus `ftruncate`; writes use `mmap` when available and fall back to `pwrite`.
- Stores partial files under `~/Downloads/Fast Native Download Manager/.partial`.
- Pausing cancels network tasks but keeps the partial file and segment progress.
- Resuming sends HTTP `Range` requests from each segment's saved offset.
- Canceling stops the task and removes the partial file.
- Completed files are moved into `~/Downloads/Fast Native Download Manager`.
- Persists tasks and segments in SQLite at `~/Downloads/Fast Native Download Manager/tasks.sqlite`.
- Persists URL, status, progress, segment thread state, headers, cookies, save path, and timestamps.
- Monitors the clipboard for downloadable HTTP/HTTPS links and prompts with "Detected downloadable link".
- Automatically categorizes downloads as Video, Audio, Archive, App, or Document based on file extension and disposition hints.
- Accepts external browser downloads through the local bridge at `127.0.0.1:51237`.
- Supports Bilibili video pages through the yt-dlp site preset, including `BV`/`av` URLs, `b23.tv` short links, browser cookies, and `?p=` part selection such as `?p=1`, `?p=1-3`, `?p=1-`, or `?p=-3`.

## Browser Extension

The browser extension source lives in `Browser Extension`.

- `Browser Extension/chrome`: Chrome Manifest V3 extension.
- `Browser Extension/firefox`: Firefox WebExtension build.

Chrome local testing:

1. Start Fast Native Download Manager.
2. Open `chrome://extensions`.
3. Enable `Developer mode`.
4. Click `Load unpacked`.
5. Select `Browser Extension/chrome`.

After loading, right-click a link, image, video, audio item, selected URL text, or page and choose `Download with Fast Native Download Manager`.

The Chrome and Firefox extensions use the same local HTTP bridge and toolbar popup grabber.

## Next Milestones

- Keep the Chrome and Firefox browser capture paths in sync as new extractors are added.
- Build a media sniffer pipeline for HLS/DASH manifests, direct video files, archive links, and installer packages.
- Add checksum verification and retry policy per segment.
