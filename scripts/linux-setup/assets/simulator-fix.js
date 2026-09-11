(() => {
  const qs = new URLSearchParams(location.search);
  if (window.parent === window || location.pathname !== "/panel" || qs.get("simulator") !== "1") return;

  const state = {
    theme: null,
    themeMode: "dark",
    layout: null,
    deviceId: null,
    deviceTouch: undefined,
    dpi: undefined,
    displayBound: false,
    selectedWidgetId: null,
    brightness: 100,
    screenOn: true
  };

  let sawRealInit = false;
  let syntheticInitSent = false;
  let initTimer = null;

  function visibleDisplay() {
    if (state.layout?.surface !== "y70") return;
    window.postMessage({
      type: "simulator/set-display",
      brightness: state.brightness,
      screenOn: state.screenOn,
      showPanel: true
    }, location.origin);
  }

  function maybeInit() {
    if (sawRealInit || syntheticInitSent || !state.theme || state.layout?.surface !== "y70" || initTimer) return;
    initTimer = setTimeout(() => {
      initTimer = null;
      if (sawRealInit || syntheticInitSent || !state.theme || state.layout?.surface !== "y70") return;
      syntheticInitSent = true;
      window.postMessage({
        type: "simulator/init",
        surface: state.layout.surface || "y70",
        deviceTouch: state.deviceTouch,
        dpi: state.dpi,
        displayBound: state.displayBound,
        layout: state.layout,
        theme: state.theme,
        themeMode: state.themeMode,
        selectedWidgetId: state.selectedWidgetId,
        brightness: state.brightness,
        screenOn: state.screenOn,
        showPanel: true,
        deviceId: state.deviceId
      }, location.origin);
    }, 250);
  }

  window.addEventListener("message", (event) => {
    if (event.origin !== location.origin || event.source !== window.parent || !event.data || typeof event.data !== "object") return;
    const msg = event.data;

    switch (msg.type) {
      case "simulator/init":
        sawRealInit = true;
        if (initTimer) clearTimeout(initTimer);
        initTimer = null;
        state.theme = msg.theme ?? state.theme;
        state.themeMode = msg.themeMode ?? state.themeMode;
        state.layout = msg.layout ?? state.layout;
        state.deviceId = msg.deviceId ?? state.deviceId;
        state.deviceTouch = msg.deviceTouch;
        state.dpi = msg.dpi;
        state.displayBound = msg.displayBound ?? state.displayBound;
        state.selectedWidgetId = msg.selectedWidgetId ?? state.selectedWidgetId;
        state.brightness = msg.brightness ?? state.brightness;
        state.screenOn = msg.screenOn ?? state.screenOn;
        setTimeout(visibleDisplay, 0);
        return;

      case "simulator/set-theme":
        state.theme = msg.theme ?? state.theme;
        state.themeMode = msg.themeMode ?? state.themeMode;
        state.deviceId = msg.deviceId ?? state.deviceId;
        break;
      case "simulator/set-layout":
        state.layout = msg.layout ?? state.layout;
        break;
      case "simulator/set-grid":
        state.dpi = msg.dpi;
        break;
      case "simulator/set-touch":
        state.deviceTouch = msg.deviceTouch;
        break;
      case "simulator/set-display-bound":
        state.displayBound = msg.displayBound;
        break;
      case "simulator/set-selection":
        state.selectedWidgetId = msg.widgetId ?? null;
        break;
      case "simulator/set-display":
        state.brightness = msg.brightness ?? state.brightness;
        state.screenOn = msg.screenOn ?? state.screenOn;
        if (msg.showPanel !== true) setTimeout(visibleDisplay, 0);
        break;
      default:
        break;
    }
    maybeInit();
  }, true);
})();
