(() => {
  const rootId = "fndm-grabber-root";
  const state = {
    resources: [],
    open: false
  };

  chrome.runtime.onMessage.addListener((message) => {
    if (message?.type === "fndm-resources-detected" && Array.isArray(message.resources)) {
      mergeResources(message.resources);
      render();
    }
  });

  chrome.runtime.sendMessage({ type: "fndm-get-resources" }, (response) => {
    if (Array.isArray(response?.resources)) {
      mergeResources(response.resources);
      render();
    }
  });

  function mergeResources(resources) {
    const merged = new Map(state.resources.map((resource) => [resource.url, resource]));
    for (const resource of resources) {
      if (resource?.url && shouldDisplayResource(resource)) {
        merged.set(resource.url, resource);
      }
    }
    state.resources = Array.from(merged.values())
      .sort((left, right) => (right.confidence || 0) - (left.confidence || 0))
      .slice(0, 20);
  }

  function shouldDisplayResource(resource) {
    const type = String(resource.type || "").toUpperCase();
    if ([
      "YOUTUBE", "BILIBILI", "VIMEO", "X", "INSTAGRAM", "TIKTOK",
      "FACEBOOK", "TWITCH", "DAILYMOTION", "REDDIT", "SOUNDCLOUD",
      "PINTEREST", "LINKEDIN", "IMDB", "MP4", "M3U8", "MPD", "ZIP", "DMG", "TORRENT", "ED2K"
    ].includes(type)) {
      return true;
    }
    return /(^magnet:\?|^ed2k:\/\/|(?:\.)(mp4|m3u8|mpd|zip|dmg|torrent)(?:[?#]|$))/i.test(resource.url || "");
  }

  function render() {
    if (state.resources.length === 0) {
      document.getElementById(rootId)?.remove();
      return;
    }

    const root = ensureRoot();
    root.innerHTML = "";

    const button = document.createElement("button");
    button.type = "button";
    button.className = "fndm-button";
    button.textContent = `Download ${state.resources.length}`;
    button.title = "Fast Native Download Manager detected downloadable resources";
    button.addEventListener("click", () => {
      state.open = !state.open;
      render();
    });
    root.append(button);

    if (!state.open) {
      return;
    }

    const panel = document.createElement("div");
    panel.className = "fndm-panel";

    const title = document.createElement("div");
    title.className = "fndm-title";
    title.textContent = "Detected resources";
    panel.append(title);

    for (const resource of state.resources.slice().reverse()) {
      const row = document.createElement("button");
      row.type = "button";
      row.className = "fndm-row";
      row.title = resource.url;
      row.addEventListener("click", () => download(resource));

      const badge = document.createElement("span");
      badge.className = "fndm-badge";
      badge.textContent = resource.type || "FILE";

      const text = document.createElement("span");
      text.className = "fndm-text";
      text.textContent = resource.title || resource.fileName || resource.url;

      row.append(badge, text);
      panel.append(row);
    }

    root.append(panel);
  }

  function download(resource) {
    const button = document.querySelector(`#${rootId} .fndm-button`);
    if (button) {
      button.textContent = "Sending...";
    }
    chrome.runtime.sendMessage({ type: "fndm-download-resource", resource }, (response) => {
      response = chrome.runtime.lastError ? { ok: false, error: chrome.runtime.lastError.message } : response;
      if (button) {
        button.textContent = response?.ok ? "Sent" : "Error";
        button.title = response?.ok ? "Sent to Fast Native Download Manager" : (response?.error || "Unable to send to Fast Native Download Manager");
        setTimeout(render, 900);
      }
    });
  }

  function ensureRoot() {
    let root = document.getElementById(rootId);
    if (root) {
      return root;
    }

    root = document.createElement("div");
    root.id = rootId;
    const style = document.createElement("style");
    style.textContent = `
      #${rootId} {
        position: fixed;
        top: 72px;
        right: 18px;
        z-index: 2147483647;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", sans-serif;
        color: #111827;
      }
      #${rootId} .fndm-button {
        border: 0;
        border-radius: 999px;
        background: #007aff;
        color: white;
        min-width: 112px;
        height: 36px;
        padding: 0 14px;
        box-shadow: 0 10px 28px rgba(0, 0, 0, 0.22);
        font-size: 13px;
        font-weight: 700;
        cursor: pointer;
      }
      #${rootId} .fndm-panel {
        width: 340px;
        max-height: 360px;
        overflow: auto;
        margin-top: 8px;
        border: 1px solid rgba(0, 0, 0, 0.12);
        border-radius: 14px;
        background: rgba(255, 255, 255, 0.96);
        box-shadow: 0 18px 48px rgba(0, 0, 0, 0.24);
        backdrop-filter: blur(18px);
      }
      #${rootId} .fndm-title {
        height: 34px;
        display: flex;
        align-items: center;
        padding: 0 12px;
        border-bottom: 1px solid rgba(0, 0, 0, 0.08);
        font-size: 13px;
        font-weight: 700;
      }
      #${rootId} .fndm-row {
        width: 100%;
        height: 40px;
        border: 0;
        border-bottom: 1px solid rgba(0, 0, 0, 0.06);
        background: transparent;
        display: flex;
        align-items: center;
        gap: 8px;
        padding: 0 10px;
        text-align: left;
        cursor: pointer;
      }
      #${rootId} .fndm-row:hover {
        background: rgba(0, 122, 255, 0.1);
      }
      #${rootId} .fndm-badge {
        min-width: 44px;
        color: #007aff;
        font-size: 11px;
        font-weight: 800;
      }
      #${rootId} .fndm-text {
        flex: 1;
        overflow: hidden;
        white-space: nowrap;
        text-overflow: ellipsis;
        font-size: 13px;
      }
    `;
    document.documentElement.append(style, root);
    return root;
  }
})();
