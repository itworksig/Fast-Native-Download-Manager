# Fast Native Download Manager Firefox Extension

Firefox WebExtension build for Fast Native Download Manager.

It sends links and detected resources to the local app bridge:

`http://127.0.0.1:51237`

## Features

- Right-click menu: `Download with Fast Native Download Manager`
- Automatic handoff for normal Firefox download links
- Page grabber button: `Download N`
- Resource sniffing for media, archives, app packages, torrents, eD2K, HLS, and DASH
- Site preset handoff for YouTube, Bilibili, Vimeo, X, Instagram, TikTok, Facebook, Twitch, Dailymotion, Reddit, SoundCloud, Pinterest, LinkedIn, and IMDb
- Sends cookies, Referer, Origin, User-Agent, file name hints, and engine hints to the app

## Load Temporarily

1. Start Fast Native Download Manager.
2. Open Firefox and go to `about:debugging#/runtime/this-firefox`.
3. Click `Load Temporary Add-on...`.
4. Select `Browser Extension/firefox/manifest.json`.

Firefox uses the local HTTP bridge, so no native messaging host install is required for this build.
