// Isolated-world bridge: page scripts cannot access chrome.runtime directly.
(async () => {
  try {
    const result = await chrome.runtime.sendMessage({ type: "BPB_GET_BROWSER_PROFILE" });
    if (!result?.ok || !result.location) return;
    window.dispatchEvent(new CustomEvent("bpb-browser-profile-ready", {
      detail: result.location
    }));
  } catch (_) {
    // Keep the page's native locale/timezone if the lookup or extension is unavailable.
  }
})();