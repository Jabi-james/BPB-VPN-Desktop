# BPB Browser Privacy extension

This directory contains the reviewable source for the Chromium extension intended for Chrome and Microsoft Edge.

## What it does

- Looks up the public IP's country and timezone using ipapi.co from the browser extension service worker.
- Sets the HTTP `Accept-Language` request header using a country-to-locale default.
- Overrides selected page-visible APIs at document start: `navigator.language`, `navigator.languages`, `Intl.DateTimeFormat` default timezone, and `Date.prototype.getTimezoneOffset`.
- Refreshes the IP-derived profile periodically and on browser startup.

## Chrome / Edge local development install

1. Open `chrome://extensions` (or `edge://extensions`).
2. Enable Developer mode.
3. Select **Load unpacked**.
4. Select the `chromium` folder containing `manifest.json`.

## Important limitations

- A country does not uniquely determine a person's preferred language. The country-to-locale table is a default mapping, not a reliable language inference.
- The IP lookup follows the browser's actual network route. If the browser is excluded from the VPN or uses split tunneling, the result may be the ISP-facing IP rather than the VPN exit.
- Browser APIs are not all overridden. In particular, this does not change the operating system clock/timezone, browser chrome/UI language, every JavaScript date rendering path, or every fingerprinting surface. It reduces common mismatches; it is not an anonymity guarantee.
- The lookup provider receives the public IP observed by its service. Review its privacy policy before enabling this feature.
- The current source is a Chromium MV3 implementation. Firefox packaging and compatibility testing must be completed separately before publishing to AMO.

## Permissions

- `storage` and `alarms`: cache and periodically refresh the IP-derived profile.
- `declarativeNetRequestWithHostAccess`: set the outgoing Accept-Language header.
- `https://ipapi.co/*`: retrieve country and timezone.
- `<all_urls>`: run the page-side API overrides on websites.
