const RULE_ID = 7319;
const REFRESH_MINUTES = 15;
const DEFAULT_LOCALE = "en-US";

const COUNTRY_LOCALES = {
  US: "en-US", GB: "en-GB", CA: "en-CA", AU: "en-AU", NZ: "en-NZ",
  FR: "fr-FR", DE: "de-DE", AT: "de-AT", CH: "de-CH", ES: "es-ES",
  MX: "es-MX", AR: "es-AR", IT: "it-IT", PT: "pt-PT", BR: "pt-BR",
  NL: "nl-NL", BE: "nl-BE", RU: "ru-RU", UA: "uk-UA", TR: "tr-TR",
  IR: "fa-IR", SA: "ar-SA", AE: "ar-AE", EG: "ar-EG", JP: "ja-JP",
  KR: "ko-KR", CN: "zh-CN", TW: "zh-TW", IN: "en-IN", PK: "ur-PK",
  SE: "sv-SE", NO: "nb-NO", DK: "da-DK", FI: "fi-FI", PL: "pl-PL",
  CZ: "cs-CZ", GR: "el-GR", IL: "he-IL", ID: "id-ID", TH: "th-TH",
  VN: "vi-VN", MY: "ms-MY", SG: "en-SG", ZA: "en-ZA"
};

async function applyHeader(locale) {
  const language = locale || DEFAULT_LOCALE;
  await chrome.declarativeNetRequest.updateDynamicRules({
    removeRuleIds: [RULE_ID],
    addRules: [{
      id: RULE_ID,
      priority: 1,
      action: {
        type: "modifyHeaders",
        requestHeaders: [{
          header: "accept-language",
          operation: "set",
          value: language + "," + language.split("-")[0] + ";q=0.9"
        }]
      },
      condition: {
        urlFilter: "|http",
        resourceTypes: [
          "main_frame", "sub_frame", "stylesheet", "script", "image",
          "font", "object", "xmlhttprequest", "ping", "media", "other"
        ]
      }
    }]
  });
}

async function refreshLocation(force = false) {
  const cached = await chrome.storage.local.get(["bpbLocation", "bpbUpdatedAt"]);
  if (!force && cached.bpbLocation && Date.now() - (cached.bpbUpdatedAt || 0) < REFRESH_MINUTES * 60_000) {
    return cached.bpbLocation;
  }

  // This request follows the browser's active network route. With a full-tunnel VPN,
  // it sees the VPN exit; with split tunneling, it may see the browser's direct route.
  const response = await fetch("https://ipapi.co/json/", { cache: "no-store" });
  if (!response.ok) throw new Error("IP location lookup failed: HTTP " + response.status);
  const data = await response.json();
  if (!data || typeof data.timezone !== "string" || typeof data.country_code !== "string") {
    throw new Error("IP location response did not include a country and timezone");
  }

  const locale = COUNTRY_LOCALES[data.country_code.toUpperCase()] || DEFAULT_LOCALE;
  const location = {
    timezone: data.timezone,
    locale,
    country: data.country_code.toUpperCase(),
    updatedAt: Date.now()
  };
  await chrome.storage.local.set({ bpbLocation: location, bpbUpdatedAt: Date.now() });
  await applyHeader(locale);
  return location;
}

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type !== "BPB_GET_BROWSER_PROFILE") return false;
  refreshLocation().then(
    location => sendResponse({ ok: true, location }),
    error => sendResponse({ ok: false, error: String(error) })
  );
  return true;
});

chrome.runtime.onInstalled.addListener(() => {
  chrome.alarms.create("bpb-location-refresh", { periodInMinutes: REFRESH_MINUTES });
  refreshLocation(true).catch(() => {});
});

chrome.runtime.onStartup.addListener(() => {
  chrome.alarms.create("bpb-location-refresh", { periodInMinutes: REFRESH_MINUTES });
  refreshLocation(true).catch(() => {});
});

chrome.alarms.onAlarm.addListener(alarm => {
  if (alarm.name === "bpb-location-refresh") refreshLocation(true).catch(() => {});
});

refreshLocation().catch(() => {});