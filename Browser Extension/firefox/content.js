(() => {
  const api = typeof browser !== "undefined" ? browser : chrome;
  const state = {
    resources: []
  };

  api.runtime.onMessage.addListener((message) => {
    if (message?.type === "fndm-resources-detected" && Array.isArray(message.resources)) {
      mergeResources(message.resources);
      return Promise.resolve({ ok: true, count: state.resources.length });
    }
    if (message?.type === "fndm-get-content-resources") {
      return Promise.resolve({ resources: state.resources });
    }
    return false;
  });

  sendRuntimeMessage({ type: "fndm-get-resources" }).then((response) => {
    if (Array.isArray(response?.resources)) {
      mergeResources(response.resources);
    }
  }).catch(() => {});

  function sendRuntimeMessage(message) {
    const result = api.runtime.sendMessage(message);
    if (result && typeof result.then === "function") {
      return result;
    }
    return new Promise((resolve) => api.runtime.sendMessage(message, resolve));
  }

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
})();
