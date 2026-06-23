# Fast Native Download Manager Chrome Extension

Chrome Manifest V3 WebExtension build for Fast Native Download Manager.

It sends links and detected resources to the local app bridge:

`http://127.0.0.1:51237`

## Features

- Right-click menu: `Download with Fast Native Download Manager`
- Automatic handoff for normal Chrome download links
- Toolbar popup grabber with resource count badge
- Resource sniffing for media, archives, app packages, torrents, eD2K, HLS, and DASH
- Site preset handoff for YouTube, Bilibili, Vimeo, X, Instagram, TikTok, Facebook, Twitch, Dailymotion, Reddit, SoundCloud, Pinterest, LinkedIn, and IMDb
- Sends cookies, Referer, Origin, User-Agent, file name hints, and engine hints to the app

## Install for local testing

1. Start Fast Native Download Manager.
2. Open Chrome and go to `chrome://extensions`.
3. Enable `Developer mode`.
4. Click `Load unpacked`.
5. Select this folder: `Browser Extension/chrome`.

Chrome uses the local HTTP bridge, so no native messaging host install is required for this build.
