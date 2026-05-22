# Fast Native Download Manager Chrome Extension

This extension adds a context-menu item:

`Download with Fast Native Download Manager`

It sends the selected link, media source, selected URL text, or current page URL to the macOS app through:

`fastndm://download?url=...`

## Install for local testing

1. Build and open the macOS app once so macOS registers the `fastndm://` URL scheme.
2. Open Chrome and go to `chrome://extensions`.
3. Enable `Developer mode`.
4. Click `Load unpacked`.
5. Select this folder: `Browser Extension/chrome`.

Chrome may show an external protocol confirmation the first time the menu opens the app.
