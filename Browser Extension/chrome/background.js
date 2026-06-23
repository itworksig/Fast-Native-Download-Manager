const api = typeof browser !== "undefined" ? browser : chrome;
const menuAPI = api.menus || api.contextMenus;
const MENU_ID = "download-with-fast-native-download-manager";
const BRIDGE_URL = "http://127.0.0.1:51237/download";
const RESOURCES_URL = "http://127.0.0.1:51237/resources";
const EXTRACT_URL = "http://127.0.0.1:51237/extract";
const ENGINE_HEADER = "X-FNDM-Engine";
const SITE_PRESET_HEADER = "X-FNDM-Site-Preset";
const YTDLP_FORMAT_HEADER = "X-FNDM-YTDLP-Format";
const headerHintsByUrl = new Map();
const sentDownloadIds = new Set();
const sentResourceUrls = new Set();
const resourcesByTabId = new Map();
const isChrome = typeof browser === "undefined";

api.runtime.onInstalled.addListener(registerContextMenu);
api.runtime.onStartup?.addListener(registerContextMenu);
registerContextMenu();

function registerContextMenu() {
  removeContextMenu(MENU_ID).finally(() => {
    menuAPI.create({
      id: MENU_ID,
      title: "Download with Fast Native Download Manager",
      contexts: ["link", "image", "video", "audio", "page", "selection"]
    });
  });
}

function removeContextMenu(id) {
  if (!isChrome) {
    return Promise.resolve(menuAPI.remove(id)).catch(() => {});
  }
  return new Promise((resolve) => {
    chrome.contextMenus.remove(id, () => {
      chrome.runtime.lastError;
      resolve();
    });
  });
}

function cancelDownload(id) {
  if (!isChrome) {
    return Promise.resolve(api.downloads.cancel(id)).catch(() => {});
  }
  return new Promise((resolve) => {
    chrome.downloads.cancel(id, () => {
      chrome.runtime.lastError;
      resolve();
    });
  });
}

function eraseDownload(id) {
  if (!isChrome) {
    return Promise.resolve(api.downloads.erase({ id })).catch(() => {});
  }
  return new Promise((resolve) => {
    chrome.downloads.erase({ id }, () => {
      chrome.runtime.lastError;
      resolve();
    });
  });
}

function getTab(tabId) {
  if (!isChrome) {
    return api.tabs.get(tabId);
  }
  return new Promise((resolve, reject) => {
    chrome.tabs.get(tabId, (tab) => {
      const error = chrome.runtime.lastError;
      if (error) {
        reject(new Error(error.message));
        return;
      }
      resolve(tab);
    });
  });
}

function queryTabs(query) {
  if (!isChrome) {
    return api.tabs.query(query);
  }
  return new Promise((resolve, reject) => {
    chrome.tabs.query(query, (tabs) => {
      const error = chrome.runtime.lastError;
      if (error) {
        reject(new Error(error.message));
        return;
      }
      resolve(tabs);
    });
  });
}

function executeTabScript(tabId, func) {
  if (!isChrome) {
    return api.tabs.executeScript(tabId, {
      code: `(${func.toString()})();`
    });
  }
  return chrome.scripting.executeScript({
    target: { tabId },
    func
  }).then((results) => results.map((result) => result.result));
}

function sendTabMessage(tabId, message) {
  if (!isChrome) {
    return api.tabs.sendMessage(tabId, message);
  }
  return new Promise((resolve, reject) => {
    chrome.tabs.sendMessage(tabId, message, (response) => {
      const error = chrome.runtime.lastError;
      if (error) {
        reject(new Error(error.message));
        return;
      }
      resolve(response);
    });
  });
}

function setActionBadgeText(details) {
  if (!isChrome) {
    const actionAPI = api.action || api.browserAction;
    return actionAPI.setBadgeText(details);
  }
  return chrome.action.setBadgeText(details);
}

function setActionBadgeBackgroundColor(details) {
  if (!isChrome) {
    const actionAPI = api.action || api.browserAction;
    return actionAPI.setBadgeBackgroundColor(details);
  }
  return chrome.action.setBadgeBackgroundColor(details);
}

function getCookies(details) {
  if (!isChrome) {
    return api.cookies.getAll(details);
  }
  return chrome.cookies.getAll(details);
}

function createNotification(details) {
  if (!isChrome) {
    return api.notifications.create(details);
  }
  return chrome.notifications.create(details);
}

menuAPI.onClicked.addListener(async (info, tab) => {
  if (info.menuItemId !== MENU_ID) {
    return;
  }

  const targetUrl = findDownloadUrl(info);
  if (!targetUrl) {
    notify("Fast Native Download Manager", "No downloadable HTTP/HTTPS, magnet, torrent, or eD2K link was found here.");
    return;
  }

  await sendToLocalApp(await buildRequest(targetUrl, {
    referer: info.pageUrl || tab?.url,
    fileName: fileNameFromContext(info)
  }));
});

api.downloads.onCreated.addListener((downloadItem) => {
  if (!isHttpUrl(downloadItem.url) || sentDownloadIds.has(downloadItem.id)) {
    return;
  }

  sentDownloadIds.add(downloadItem.id);
  cancelDownload(downloadItem.id).finally(() => {
    eraseDownload(downloadItem.id).catch(() => {});
  });

  buildRequest(downloadItem.url, {
    referer: downloadItem.referrer,
    fileName: fileNameFromDownload(downloadItem)
  }).then(sendToLocalApp).catch(() => {});
});

api.runtime.onMessage.addListener((message, sender, sendResponse) => {
  const respond = handleRuntimeMessage(message, sender);
  if (!isChrome) {
    return respond;
  }
  if (respond === false) {
    return false;
  }
  respond.then(sendResponse).catch((error) => {
    sendResponse({ ok: false, error: error.message || "Request failed." });
  });
  return true;
});

async function handleRuntimeMessage(message, sender) {
  if (message?.type === "fndm-scan-tab") {
    return tabFromMessage(message).then(scanTabForResources).then((resources) => {
      return { ok: true, resources };
    }).catch((error) => {
      console.error("Grabber page scan failed:", error);
      return { ok: false, error: error.message || "Unable to scan this page.", resources: [] };
    });
  }

  if (message?.type === "fndm-download-resource" && message.resource?.url) {
    return sendToLocalApp(resourceToDownloadRequest(message.resource)).then(() => {
      return { ok: true };
    }).catch((error) => {
      return { ok: false, error: error.message || "Unable to send download request." };
    });
  }

  if (message?.type === "fndm-get-resources") {
    const tabId = typeof message.tabId === "number" ? message.tabId : sender.tab?.id;
    return Promise.resolve({ resources: tabId == null ? [] : resourcesByTabId.get(tabId) || [] });
  }

  return false;
}

api.tabs.onRemoved?.addListener((tabId) => {
  resourcesByTabId.delete(tabId);
  updateBrowserActionBadge(tabId);
});

api.tabs.onUpdated?.addListener((tabId, changeInfo) => {
  if (changeInfo.status === "loading") {
    resourcesByTabId.delete(tabId);
    updateBrowserActionBadge(tabId);
  }
});

api.webRequest.onHeadersReceived.addListener(
  (details) => {
    if (!isHttpUrl(details.url)) {
      return;
    }

    const headers = Object.fromEntries(
      (details.responseHeaders || []).map((header) => [header.name.toLowerCase(), header.value || ""])
    );
    const contentDisposition = headers["content-disposition"];
    const contentType = headers["content-type"];

    if (contentDisposition || looksDownloadable(details.url, contentType)) {
      rememberHeaderHint(details.url, {
        fileName: fileNameFromContentDisposition(contentDisposition),
        contentType
      });

      if (details.tabId >= 0) {
        getTab(details.tabId).then((tab) => {
          platformPageResource(tab).then((resource) => {
            if (resource) {
              sendResources([resource]);
              return;
            }
            sendRawResourceFromDetails(details, contentType);
          });
        }).catch(() => sendRawResourceFromDetails(details, contentType));
        return;
      }

      sendRawResourceFromDetails(details, contentType);
    }
  },
  { urls: ["http://*/*", "https://*/*"] },
  ["responseHeaders"]
);

function sendRawResourceFromDetails(details, contentType) {
  buildResource(details.url, {
    referer: details.originUrl || details.initiator || details.documentUrl,
    contentType,
    source: "network",
    tabId: details.tabId
  }).then((resource) => sendResources([resource])).catch(() => {});
}

async function buildResource(targetUrl, context = {}) {
  if (!isDownloadableUrl(targetUrl) || !looksDownloadable(targetUrl, context.contentType)) {
    return null;
  }
  if (isNoiseResource(targetUrl) || isPlatformMediaRequest(targetUrl)) {
    return null;
  }

  const hint = headerHintsByUrl.get(targetUrl) || {};
  const fileName = hint.fileName || fileNameFromUrl(targetUrl);
  const parsedURL = safeURL(targetUrl);
  const type = resourceType(targetUrl, context.contentType || hint.contentType);
  const headers = {
    "User-Agent": navigator.userAgent
  };
  if (isHttpUrl(context.referer)) {
    headers.Referer = context.referer;
    headers.Origin = new URL(context.referer).origin;
  }
  if (type === "M3U8" || type === "MPD") {
    headers[ENGINE_HEADER] = "ffmpeg";
  }
  if (type === "TORRENT" || isMagnetUrl(targetUrl)) {
    headers[ENGINE_HEADER] = "BitTorrent";
  }
  if (type === "ED2K" || isED2KUrl(targetUrl)) {
    headers[ENGINE_HEADER] = "eD2K";
  }
  const platform = platformNameForUrl(targetUrl);
  if (platform) {
    headers[ENGINE_HEADER] = "yt-dlp";
    headers[SITE_PRESET_HEADER] = platform;
    headers[YTDLP_FORMAT_HEADER] = platformFormat(platform);
  }

  return {
    url: targetUrl,
    host: parsedURL?.hostname || protocolLabel(targetUrl),
    type,
    title: fileName || `${type} resource`,
    quality: context.source || "detected",
    size: "--",
    confidence: context.source === "network" ? 0.95 : 0.82,
    fileName,
    headers,
    cookie: isHttpUrl(targetUrl) ? await cookieHeaderFor(targetUrl) : "",
    tabId: context.tabId
  };
}

async function platformPageResource(tab) {
  if (!tab?.url || !isHttpUrl(tab.url)) {
    return null;
  }

  const platform = platformNameForUrl(tab.url);
  if (!platform) {
    return null;
  }

  const headers = {
    "User-Agent": navigator.userAgent,
    Referer: tab.url,
    Origin: new URL(tab.url).origin
  };
  headers[ENGINE_HEADER] = "yt-dlp";
  headers[SITE_PRESET_HEADER] = platform;
  headers[YTDLP_FORMAT_HEADER] = platformFormat(platform);

  return {
    url: canonicalPlatformUrl(tab.url),
    host: new URL(tab.url).hostname,
    type: platform.toUpperCase(),
    title: sanitizeFileName(tab.title || `${platform} video`),
    quality: "yt-dlp",
    size: "--",
    confidence: 0.99,
    fileName: sanitizeFileName(tab.title || `${platform} video`),
    headers,
    cookie: await cookieHeaderFor(tab.url),
    tabId: tab.id
  };
}

async function sendResources(resources) {
  const validResources = resources.filter(Boolean);
  if (validResources.length === 0) {
    return;
  }

  const freshResources = validResources.filter((resource) => !sentResourceUrls.has(resource.url));

  if (freshResources.length > 0) {
    freshResources.forEach((resource) => sentResourceUrls.add(resource.url));
    if (sentResourceUrls.size > 500) {
      sentResourceUrls.clear();
    }

    try {
      const response = await fetch(RESOURCES_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-FNDM-Source": "chrome-extension"
        },
        body: JSON.stringify(freshResources)
      });
      if (!response.ok) {
        throw new Error(`Local bridge returned HTTP ${response.status}`);
      }
    } catch (error) {
      console.error("Fast Native Download Manager resource bridge error:", error);
    }
  }

  publishResourcesToTabs(validResources);
}

async function tabFromMessage(message) {
  if (typeof message.tabId === "number") {
    return getTab(message.tabId);
  }
  const tabs = await queryTabs({ active: true, currentWindow: true });
  if (tabs[0]) {
    return tabs[0];
  }
  throw new Error("No active tab found.");
}

async function scanTabForResources(tab) {
  if (!tab?.id) {
    return [];
  }

  await requestAppExtractors(tab.url, tab.title);

  const platformResource = await platformPageResource(tab);
  if (platformResource) {
    await sendResources([platformResource]);
    return resourcesByTabId.get(tab.id) || [stripInternalResourceFields(platformResource)];
  }

  const results = await executeTabScript(tab.id, scanPageForDownloadableResources);
  const urls = Array.isArray(results?.[0]) ? results[0] : [];
  const resources = await Promise.all(urls.filter(isDownloadableUrl).map((url) => buildResource(url, {
    referer: tab.url,
    source: "page-scan",
    tabId: tab.id
  })));
  await sendResources(resources.filter(Boolean));
  return resourcesByTabId.get(tab.id) || [];
}

async function requestAppExtractors(pageUrl, title = "") {
  if (!isHttpUrl(pageUrl)) {
    return false;
  }
  try {
    const response = await fetch(EXTRACT_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-FNDM-Source": "chrome-extension"
      },
      body: JSON.stringify({ url: pageUrl, title })
    });
    if (!response.ok) {
      throw new Error(`Local bridge returned HTTP ${response.status}`);
    }
    return true;
  } catch (error) {
    console.warn("Fast Native Download Manager extractor bridge error:", error);
    return false;
  }
}

function publishResourcesToTabs(resources) {
  const grouped = new Map();
  for (const resource of resources) {
    const tabId = resource.tabId;
    if (typeof tabId !== "number" || tabId < 0) {
      continue;
    }
    grouped.set(tabId, [...(grouped.get(tabId) || []), stripInternalResourceFields(resource)]);
  }

  for (const [tabId, tabResources] of grouped.entries()) {
    const existing = resourcesByTabId.get(tabId) || [];
    const merged = new Map(existing.map((resource) => [resource.url, resource]));
    for (const resource of tabResources) {
      merged.set(resource.url, resource);
    }
    const list = Array.from(merged.values()).slice(-50);
    resourcesByTabId.set(tabId, list);
    updateBrowserActionBadge(tabId, list.length);
    sendTabMessage(tabId, { type: "fndm-resources-detected", resources: list }).catch(() => {});
  }
}

function updateBrowserActionBadge(tabId, count = 0) {
  Promise.resolve(setActionBadgeText({
    tabId,
    text: count > 0 ? String(Math.min(count, 99)) : ""
  })).catch(() => {});
  Promise.resolve(setActionBadgeBackgroundColor({
    tabId,
    color: "#007aff"
  })).catch(() => {});
}

function stripInternalResourceFields(resource) {
  const { tabId, ...publicResource } = resource;
  return publicResource;
}

function resourceToDownloadRequest(resource) {
  return {
    url: resource.url,
    fileName: resource.fileName || resource.title || fileNameFromUrl(resource.url),
    headers: resource.headers || { "User-Agent": navigator.userAgent },
    cookie: resource.cookie || "",
    source: "chrome-popup"
  };
}

async function buildRequest(targetUrl, context = {}) {
  const hint = headerHintsByUrl.get(targetUrl) || {};
  const headers = {
    "User-Agent": navigator.userAgent
  };

  const referer = context.referer || "";
  if (isHttpUrl(referer)) {
    headers.Referer = referer;
  }
  if (isMagnetUrl(targetUrl) || fileExtension(targetUrl) === "torrent") {
    headers[ENGINE_HEADER] = "BitTorrent";
  }
  if (isED2KUrl(targetUrl)) {
    headers[ENGINE_HEADER] = "eD2K";
  }

  return {
    url: targetUrl,
    fileName: context.fileName || hint.fileName || fileNameFromUrl(targetUrl),
    headers,
    cookie: isHttpUrl(targetUrl) ? await cookieHeaderFor(targetUrl) : "",
    source: "chrome"
  };
}

async function sendToLocalApp(request) {
  try {
    const response = await fetch(BRIDGE_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-FNDM-Source": "chrome-extension"
      },
      body: JSON.stringify(request)
    });
    if (!response.ok) {
      throw new Error(`Local bridge returned HTTP ${response.status}`);
    }
    notify("Sent to Fast Native Download Manager", request.fileName || request.url);
    return true;
  } catch (error) {
    console.error("Fast Native Download Manager local bridge error:", error);
    notify(
      "Fast Native Download Manager is not reachable",
      "Open the app first, then reload this Chrome extension and try again."
    );
    throw error;
  }
}

async function cookieHeaderFor(targetUrl) {
  try {
    const cookies = await getCookies({ url: targetUrl });
    return cookies.map((cookie) => `${cookie.name}=${cookie.value}`).join("; ");
  } catch (error) {
    console.warn("Unable to read cookies for download URL:", error);
    return "";
  }
}

function notify(title, message) {
  createNotification({
    type: "basic",
    iconUrl: api.runtime.getURL("icon-128.png"),
    title,
    message: String(message || "").slice(0, 240)
  }).catch(() => {});
}

function findDownloadUrl(info) {
  const candidates = [
    info.srcUrl,
    info.linkUrl,
    urlFromSelection(info.selectionText),
    info.pageUrl
  ];

  return candidates.find(isDownloadableUrl);
}

function fileNameFromContext(info) {
  return fileNameFromUrl(info.srcUrl || info.linkUrl || "");
}

function fileNameFromDownload(downloadItem) {
  const hinted = headerHintsByUrl.get(downloadItem.url)?.fileName;
  if (hinted) {
    return hinted;
  }

  const pathName = downloadItem.filename || "";
  const parts = pathName.split(/[\\/]/).filter(Boolean);
  return parts.at(-1) || fileNameFromUrl(downloadItem.url);
}

function rememberHeaderHint(url, hint) {
  headerHintsByUrl.set(url, hint);
  if (headerHintsByUrl.size > 300) {
    headerHintsByUrl.delete(headerHintsByUrl.keys().next().value);
  }
}

function urlFromSelection(text) {
  if (!text) {
    return undefined;
  }

  const trimmed = text.trim();
  return isDownloadableUrl(trimmed) ? trimmed : undefined;
}

function isDownloadableUrl(value) {
  return isHttpUrl(value) || isMagnetUrl(value) || isED2KUrl(value);
}

function isHttpUrl(value) {
  if (!value) {
    return false;
  }

  try {
    const url = new URL(value);
    return url.protocol === "http:" || url.protocol === "https:";
  } catch {
    return false;
  }
}

function isMagnetUrl(value) {
  if (!value) {
    return false;
  }
  try {
    const url = new URL(value);
    return url.protocol === "magnet:";
  } catch {
    return /^magnet:\?/i.test(String(value));
  }
}

function isED2KUrl(value) {
  if (!value) {
    return false;
  }
  try {
    const url = new URL(value);
    return url.protocol === "ed2k:";
  } catch {
    return /^ed2k:\/\//i.test(String(value));
  }
}

function safeURL(value) {
  try {
    return new URL(value);
  } catch {
    return null;
  }
}

function protocolLabel(value) {
  if (isMagnetUrl(value)) {
    return "magnet";
  }
  if (isED2KUrl(value)) {
    return "ed2k";
  }
  return "";
}

function looksDownloadable(url, contentType = "") {
  if (isNoiseResource(url)) {
    return false;
  }

  const extension = fileExtension(url);
  if ([
    "mp4", "m4v", "mov", "mkv", "webm", "m3u8", "mpd", "m4s", "avi", "flv",
    "mp3", "flac", "aac", "m4a", "wav", "ogg", "opus",
    "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "zst",
    "dmg", "pkg", "xip", "exe", "msi", "app",
    "pdf", "doc", "docx", "txt", "rtf", "pages", "xls", "xlsx", "ppt", "pptx", "epub",
    "torrent", "ed2k"
  ].includes(extension)) {
    return true;
  }

  if (/application\/octet-stream|application\/x-|application\/zip|application\/dash\+xml|mpegurl|audio\/|video\//i.test(contentType || "")) {
    return true;
  }

  try {
    const parsed = new URL(url);
    return platformNameForUrl(url) === "imdb"
      || /(^|\.)googlevideo\.com$/i.test(parsed.hostname)
      || /(^|\.)bilivideo\.com$/i.test(parsed.hostname)
      || /(^|\.)tiktokcdn\.com$/i.test(parsed.hostname)
      || /(^|\.)tiktokv\.com$/i.test(parsed.hostname)
      || /(^|\.)fbcdn\.net$/i.test(parsed.hostname)
      || /(^|\.)cdninstagram\.com$/i.test(parsed.hostname)
      || /(^|\.)vimeocdn\.com$/i.test(parsed.hostname)
      || /\/videoplayback|\/video\/tos|\/dash|\/hls/i.test(parsed.pathname);
  } catch {
    return false;
  }
}

function isNoiseResource(value) {
  try {
    const url = new URL(value);
    const path = url.pathname.toLowerCase();
    const name = fileNameFromUrl(value).toLowerCase();
    return path.includes("/generate_204")
      || path.endsWith("/ptracking")
      || path.includes("/pagead/")
      || path.includes("/ads?")
      || ["success.mp3", "open.mp3", "no_input.mp3", "failure.mp3"].includes(name)
      || /\/api\/stats|\/log_event|\/player_204|\/stats\/watchtime|\/youtubei\/v1\/log_event/i.test(path);
  } catch {
    return false;
  }
}

function isPlatformMediaRequest(value) {
  try {
    const url = new URL(value);
    return /(^|\.)googlevideo\.com$/i.test(url.hostname)
      || /(^|\.)bilivideo\.com$/i.test(url.hostname)
      || /(^|\.)vimeocdn\.com$/i.test(url.hostname)
      || /(^|\.)tiktokcdn\.com$/i.test(url.hostname)
      || /(^|\.)tiktokv\.com$/i.test(url.hostname)
      || /(^|\.)fbcdn\.net$/i.test(url.hostname)
      || /(^|\.)cdninstagram\.com$/i.test(url.hostname);
  } catch {
    return false;
  }
}

function platformNameForUrl(value) {
  try {
    const url = new URL(value);
    const host = url.hostname.toLowerCase();
    if (host === "youtu.be" || host.endsWith(".youtube.com")) {
      return "youtube";
    }
    if (host.endsWith(".bilibili.com")) {
      return "bilibili";
    }
    if (host.endsWith(".vimeo.com")) {
      return "vimeo";
    }
    if ((host === "imdb.com" || host.endsWith(".imdb.com")) && isImdbVideoUrl(url.href)) {
      return "imdb";
    }
    if (host === "x.com" || host.endsWith(".twitter.com")) {
      return "x";
    }
    if (host.endsWith(".instagram.com")) {
      return "instagram";
    }
    if (host.endsWith(".tiktok.com") || host.endsWith(".tiktokv.com") || host.endsWith(".tiktokcdn.com")) {
      return "tiktok";
    }
    if (host.endsWith(".facebook.com") || host === "fb.watch") {
      return "facebook";
    }
    if (host.endsWith(".twitch.tv")) {
      return "twitch";
    }
    if (host.endsWith(".dailymotion.com") || host === "dai.ly") {
      return "dailymotion";
    }
    if (host.endsWith(".reddit.com") || host.endsWith(".redd.it")) {
      return "reddit";
    }
    if (host.endsWith(".soundcloud.com")) {
      return "soundcloud";
    }
    if (host.endsWith(".pinterest.com")) {
      return "pinterest";
    }
    if (host.endsWith(".linkedin.com")) {
      return "linkedin";
    }
    return "";
  } catch {
    return "";
  }
}

function isImdbVideoUrl(value) {
  try {
    const url = new URL(value);
    const host = url.hostname.toLowerCase();
    return (host === "imdb.com" || host.endsWith(".imdb.com"))
      && /^\/(?:video|videoplayer)\//i.test(url.pathname);
  } catch {
    return false;
  }
}

function canonicalPlatformUrl(value) {
  try {
    const url = new URL(value);
    if (url.hostname === "youtu.be" || url.hostname.endsWith(".youtube.com")) {
      const id = url.searchParams.get("v");
      return id ? `https://www.youtube.com/watch?v=${id}` : url.href;
    }
    url.hash = "";
    return url.href;
  } catch {
    return value;
  }
}

function platformFormat(platform) {
  switch (String(platform || "").toLowerCase()) {
    case "youtube":
      return "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/bv*+ba/b";
    case "bilibili":
    case "instagram":
    case "tiktok":
    case "vimeo":
    case "x":
      return "bv*+ba/b";
    case "soundcloud":
      return "ba/bestaudio";
    default:
      return "bv*+ba/b";
  }
}

function resourceType(url, contentType = "") {
  const extension = fileExtension(url).toUpperCase();
  if (isMagnetUrl(url)) {
    return "TORRENT";
  }
  if (isED2KUrl(url)) {
    return "ED2K";
  }
  if (extension) {
    return extension;
  }
  if (/mpegurl|m3u8/i.test(contentType)) {
    return "M3U8";
  }
  if (/dash|mpd/i.test(contentType)) {
    return "MPD";
  }
  if (/video\//i.test(contentType)) {
    return "MP4";
  }
  if (/zip/i.test(contentType)) {
    return "ZIP";
  }
  return "FILE";
}

function fileNameFromUrl(value) {
  if (!isHttpUrl(value)) {
    if (isMagnetUrl(value)) {
      try {
        const url = new URL(value);
        const name = url.searchParams.get("dn");
        if (name) {
          return sanitizeFileName(name.endsWith(".torrent") ? name : `${name}.torrent`);
        }
      } catch {
      }
      return "magnet-download.torrent";
    }
    if (isED2KUrl(value)) {
      return fileNameFromED2K(value) || "ed2k-download";
    }
    return "";
  }

  const url = new URL(value);
  const disposition = url.searchParams.get("response-content-disposition") || url.searchParams.get("rscd");
  const fromDisposition = fileNameFromContentDisposition(disposition);
  if (fromDisposition) {
    return fromDisposition;
  }

  const decoded = decodeURIComponent(url.pathname.split("/").filter(Boolean).at(-1) || "");
  return sanitizeFileName(decoded || url.hostname || "download");
}

function fileExtension(value) {
  if (!isHttpUrl(value) && !isMagnetUrl(value) && !isED2KUrl(value)) {
    return "";
  }

  const name = fileNameFromUrl(value).toLowerCase();
  const index = name.lastIndexOf(".");
  return index >= 0 ? name.slice(index + 1) : "";
}

function fileNameFromContentDisposition(value) {
  if (!value) {
    return "";
  }

  const utf8Match = value.match(/filename\*=UTF-8''([^;]+)/i);
  if (utf8Match) {
    return sanitizeFileName(decodeURIComponent(utf8Match[1].trim()));
  }

  const quotedMatch = value.match(/filename="?([^";]+)"?/i);
  return quotedMatch ? sanitizeFileName(quotedMatch[1].trim()) : "";
}

function sanitizeFileName(value) {
  return String(value || "download").replace(/[/:?%*|"<>\\]/g, "-").trim() || "download";
}

function fileNameFromED2K(value) {
  const parts = String(value || "").split("|");
  if (parts.length >= 4 && parts[1].toLowerCase() === "file") {
    try {
      return sanitizeFileName(decodeURIComponent(parts[2]));
    } catch {
      return sanitizeFileName(parts[2]);
    }
  }
  return "";
}

function scanPageForDownloadableResources() {
  const pattern = /\.(mp4|m3u8|mpd|m4s|zip|dmg|torrent)(?:[?#][^\s"'<>]*)?$/i;
  const platformPattern = /googlevideo\.com\/videoplayback|bilivideo\.com|vimeocdn\.com|tiktokcdn\.com|tiktokv\.com|fbcdn\.net|cdninstagram\.com|imdb\.com\/(?:video|videoplayer)\/|\/video\/tos|\/dash\/|\/hls\//i;
  const urls = new Set();
  const add = (value) => {
    if (!value || typeof value !== "string") {
      return;
    }
    try {
      const url = new URL(value, document.baseURI).href;
      if (/^(https?:\/\/|magnet:\?|ed2k:\/\/)/i.test(url) && (pattern.test(new URL(url).pathname + new URL(url).search) || platformPattern.test(url) || /^(magnet:\?|ed2k:\/\/)/i.test(url))) {
        urls.add(url);
      }
    } catch {
    }
  };

  document.querySelectorAll("a[href], source[src], video[src], audio[src], img[src]").forEach((element) => {
    add(element.href || element.src);
    add(element.currentSrc);
  });

  performance.getEntriesByType("resource").forEach((entry) => add(entry.name));

  for (const script of document.scripts) {
    const text = script.textContent || "";
    for (const match of text.matchAll(/(?:https?:\/\/[^\s"'<>]+?(?:\.(?:mp4|m3u8|mpd|m4s|zip|dmg|torrent)|googlevideo\.com\/videoplayback|bilivideo\.com|vimeocdn\.com|tiktokcdn\.com|tiktokv\.com|fbcdn\.net|cdninstagram\.com|imdb\.com\/(?:video|videoplayer)\/|\/video\/tos|\/dash\/|\/hls\/)[^\s"'<>]*|magnet:\?[^\s"'<>]+|ed2k:\/\/[^\s"'<>]+)/gi)) {
      add(match[0]);
    }
  }

  return Array.from(urls).slice(0, 200);
}
