const api = typeof browser !== "undefined" ? browser : chrome;

const statusEl = document.getElementById("status");
const scanButton = document.getElementById("scan");
const emptyEl = document.getElementById("empty");
const listEl = document.getElementById("list");

let activeTabId = null;
let resources = [];

scanButton.addEventListener("click", () => scanActiveTab());

init();

async function init() {
  const [tab] = await api.tabs.query({ active: true, currentWindow: true });
  activeTabId = tab?.id ?? null;
  await loadResources();
  await scanActiveTab();
}

async function loadResources() {
  if (activeTabId == null) {
    setStatus("No active tab.");
    render();
    return;
  }

  const response = await sendRuntimeMessage({ type: "fndm-get-resources", tabId: activeTabId });
  resources = Array.isArray(response?.resources) ? response.resources : [];
  render();
}

async function scanActiveTab() {
  if (activeTabId == null) {
    return;
  }

  scanButton.disabled = true;
  setStatus("Sniffing this page...");
  try {
    const response = await sendRuntimeMessage({ type: "fndm-scan-tab", tabId: activeTabId });
    resources = Array.isArray(response?.resources) ? response.resources : [];
    setStatus(response?.ok === false ? response.error : statusForCount(resources.length));
  } catch (error) {
    setStatus(error?.message || "Unable to scan this page.");
  } finally {
    scanButton.disabled = false;
    render();
  }
}

function render() {
  listEl.textContent = "";
  emptyEl.hidden = resources.length > 0;

  for (const resource of resources.slice().reverse()) {
    const row = document.createElement("button");
    row.type = "button";
    row.className = "resource";
    row.title = resource.url;
    row.addEventListener("click", () => download(resource, row));

    const badge = document.createElement("span");
    badge.className = "badge";
    badge.textContent = String(resource.type || "FILE").slice(0, 8);

    const text = document.createElement("span");
    text.className = "resource-text";

    const title = document.createElement("span");
    title.className = "title";
    title.textContent = resource.title || resource.fileName || resource.url;

    const url = document.createElement("span");
    url.className = "url";
    url.textContent = resource.host || resource.url;

    const icon = document.createElement("span");
    icon.className = "send-icon";
    icon.textContent = "↓";

    text.append(title, url);
    row.append(badge, text, icon);
    listEl.append(row);
  }

  if (!statusEl.textContent || statusEl.textContent.startsWith("Looking")) {
    setStatus(statusForCount(resources.length));
  }
}

async function download(resource, row) {
  row.disabled = true;
  const oldTitle = statusEl.textContent;
  setStatus("Sending to app...");
  try {
    const response = await sendRuntimeMessage({ type: "fndm-download-resource", resource });
    setStatus(response?.ok ? "Sent to Fast Native Download Manager." : (response?.error || "Send failed."));
  } catch (error) {
    setStatus(error?.message || "Send failed.");
  } finally {
    setTimeout(() => {
      row.disabled = false;
      if (statusEl.textContent === "Sent to Fast Native Download Manager.") {
        setStatus(statusForCount(resources.length));
      } else if (oldTitle) {
        setStatus(oldTitle);
      }
    }, 1000);
  }
}

function statusForCount(count) {
  return count === 0 ? "No resources detected." : `${count} resource${count === 1 ? "" : "s"} detected.`;
}

function setStatus(text) {
  statusEl.textContent = text;
}

function sendRuntimeMessage(message) {
  const result = api.runtime.sendMessage(message);
  if (result && typeof result.then === "function") {
    return result;
  }
  return new Promise((resolve) => api.runtime.sendMessage(message, resolve));
}
