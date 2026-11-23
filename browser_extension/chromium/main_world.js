(() => {
  "use strict";
  const eventName = "bpb-browser-profile-ready";

  function install(profile) {
    if (!profile || typeof profile.timezone !== "string" || typeof profile.locale !== "string") return;
    const timezone = profile.timezone;
    const locale = profile.locale;
    const NativeDateTimeFormat = Intl.DateTimeFormat;

    try {
      const WrappedDateTimeFormat = new Proxy(NativeDateTimeFormat, {
        construct(target, args, newTarget) {
          const options = args[1] && typeof args[1] === "object" ? { ...args[1] } : {};
          if (!Object.prototype.hasOwnProperty.call(options, "timeZone")) options.timeZone = timezone;
          const locales = args[0] == null ? locale : args[0];
          return Reflect.construct(target, [locales, options], newTarget === WrappedDateTimeFormat ? target : newTarget);
        },
        apply(target, thisArg, args) {
          const options = args[1] && typeof args[1] === "object" ? { ...args[1] } : {};
          if (!Object.prototype.hasOwnProperty.call(options, "timeZone")) options.timeZone = timezone;
          return Reflect.apply(target, thisArg, [args[0] == null ? locale : args[0], options]);
        }
      });
      Object.setPrototypeOf(WrappedDateTimeFormat, NativeDateTimeFormat);
      WrappedDateTimeFormat.prototype = NativeDateTimeFormat.prototype;
      Object.defineProperty(Intl, "DateTimeFormat", {
        configurable: true, writable: true, value: WrappedDateTimeFormat
      });
    } catch (_) {}

    try {
      Object.defineProperty(navigator, "language", { configurable: true, get: () => locale });
      Object.defineProperty(navigator, "languages", {
        configurable: true, get: () => [locale, locale.split("-")[0]]
      });
    } catch (_) {}

    try {
      const nativeOffset = Date.prototype.getTimezoneOffset;
      Date.prototype.getTimezoneOffset = function () {
        const date = Number.isNaN(this.getTime()) ? new Date() : this;
        const parts = new NativeDateTimeFormat("en-US", {
          timeZone: timezone,
          year: "numeric", month: "2-digit", day: "2-digit",
          hour: "2-digit", minute: "2-digit", second: "2-digit",
          hourCycle: "h23"
        }).formatToParts(date);
        const values = Object.fromEntries(parts.map(part => [part.type, part.value]));
        const utc = Date.UTC(
          Number(values.year), Number(values.month) - 1, Number(values.day),
          Number(values.hour), Number(values.minute), Number(values.second)
        );
        return -Math.round((utc - date.getTime()) / 60000);
      };
      Object.defineProperty(Date.prototype.getTimezoneOffset, "name", {
        value: nativeOffset.name, configurable: true
      });
    } catch (_) {}
  }

  window.addEventListener(eventName, event => install(event.detail), { once: true });
})();