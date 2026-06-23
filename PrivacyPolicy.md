# Privacy Policy

Effective date: June 24, 2026

Fast Native Download Manager is a browser extension and desktop app companion that helps users send downloadable links and page resources from Chrome to the Fast Native Download Manager desktop application.

## Single Purpose

The extension has a single purpose: to help users capture downloadable links and resources from Chrome and send them to the local Fast Native Download Manager desktop app for downloading.

## Information the Extension Handles

The extension may handle the following information only when needed to perform a user-requested download or page scan:

- The URL of a link, media source, selected URL text, or current page that the user chooses to send.
- Download metadata such as file name hints, content type, and content disposition.
- Request context such as Referer, Origin, User-Agent, and cookies for the target URL when they are needed to start the download successfully.
- Detected page resources such as media files, HLS or DASH manifests, archive links, installers, torrents, eD2K links, and supported video page URLs.

## How Information Is Used

This information is used only to:

- Send the selected download request to the local Fast Native Download Manager desktop app.
- Detect downloadable resources on the active tab when the user chooses to scan the page.
- Preserve the browser request context needed by some websites so the local desktop app can start the user-requested download reliably.
- Show local status notifications, such as whether a link was sent successfully or whether the desktop app is not reachable.

## Local Communication

The extension communicates with the Fast Native Download Manager desktop app through a local bridge at:

`http://127.0.0.1:51237`

This bridge runs on the user's own computer. The extension does not send browsing data, download data, cookies, or detected resources to any external server operated by us.

## Data Collection and Sharing

Fast Native Download Manager does not collect, sell, rent, or share personal information with third parties.

The extension does not use analytics, advertising trackers, remote logging, or behavioral profiling.

## Cookies

The extension may read cookies for a target download URL when they are required to complete a user-requested download. Some downloads require the same signed-in browser session as the website. Cookie information is passed only to the local desktop app for that download request and is not sent to our servers.

## Permissions

The extension requests permissions only for its download-capture features:

- `activeTab` and `scripting` are used when the user scans the current tab for downloadable resources.
- `contextMenus` is used to provide the right-click "Download with Fast Native Download Manager" menu item.
- `downloads` is used to detect Chrome downloads and hand them off to the desktop app.
- `cookies` is used to preserve required session context for user-requested downloads.
- `notifications` is used to show local success or error messages.
- `tabs` is used to identify the active tab and associate detected resources with the correct tab.
- `webRequest` is used to observe response headers and detect downloadable resources and filename hints. The extension does not modify network requests.
- Host permissions are used to detect downloadable resources on pages the user visits and to communicate with the local app bridge on `127.0.0.1` or `localhost`.

## Remote Code

The extension does not use remote code. All JavaScript is packaged inside the extension. It does not load external scripts, external modules, WebAssembly, or code evaluated from a remote source.

## Data Retention

The extension does not maintain a remote database and does not retain user data on our servers. Any download tasks, preferences, or local app data are stored locally on the user's device by the desktop application.

## User Control

Users can stop using the extension at any time by disabling or removing it from Chrome. Users can also stop local communication by closing the Fast Native Download Manager desktop app.

## Changes to This Policy

We may update this Privacy Policy when the extension's functionality changes or when legal or platform requirements change. Updates will be published in this repository.

## Contact

For questions about this Privacy Policy, please contact the project maintainer through the GitHub repository:

https://github.com/itworksig/Fast-Native-Download-Manager
