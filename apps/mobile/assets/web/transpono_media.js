/* Transpono's page-local controls. No media is captured, fetched or exported. */
(function () {
  'use strict';

  const allowedPage = () => window.top === window &&
    /(^|\.)(youtube|soundcloud)\.com$/i.test(window.location.hostname) &&
    window.location.protocol === 'https:';
  if (!allowedPage()) return;
  // SoundCloud plays through an Audio element that is never put in the page,
  // so it cannot be found with querySelector: remember the one that last
  // started playing. (In Gecko this runs in the relay's content-script
  // sandbox, where the page's own prototype is reached through
  // wrappedJSObject and the hook is handed back with exportFunction.)
  const soundCloud = () => /(^|\.)soundcloud\.com$/i.test(window.location.hostname);
  // The YouTube mobile site itself (not YouTube Music).
  const plainYouTube = () => /(^|\.)youtube\.com$/i.test(window.location.hostname) &&
    !/^music\./i.test(window.location.hostname);

  // The YouTube site dressed like the YouTube app for Android:
  // - bottom bar: icons only (home, Shorts, a free slot, "you"); the free slot
  //   is where the official app has "+", and where this app draws its round
  //   "adjustments" button; subscriptions move to the top tabs;
  // - top: the filter chips become text tabs with a red line under the
  //   selected one, with a "subscriptions" tab after the first;
  // - scrolling down hides both bars, scrolling up brings them back.
  if (plainYouTube() && !window.__transponoBars) {
    window.__transponoBars = true;
    const bars = document.createElement('style');
    bars.id = 'transpono-bars-style';
    bars.textContent = `
      /* The site keeps room under the bar for the system's buttons; the app
         already sits above them, so the bar goes right to the bottom. */
      ytm-pivot-bar-renderer {
        bottom: 0 !important; padding-bottom: 0 !important;
        margin-bottom: 0 !important; height: 48px !important;
        min-height: 0 !important; box-sizing: border-box !important;
        justify-content: flex-start !important;
        transition: transform .22s ease;
      }
      ytm-pivot-bar-renderer ytm-pivot-bar-item-renderer {
        flex: 0 0 25% !important; width: 25% !important; max-width: 25% !important;
        margin: 0 !important;
      }
      ytm-pivot-bar-renderer ytm-pivot-bar-item-renderer:has(.pivot-subs) {
        display: none !important;
      }
      ytm-pivot-bar-renderer ytm-pivot-bar-item-renderer:has(.pivot-shorts) {
        margin-right: 25% !important;
      }
      ytm-pivot-bar-renderer .pivot-bar-item-tab { height: 48px !important; }
      ytm-pivot-bar-renderer .pivot-bar-item-title { display: none !important; }
      ytm-pivot-bar-renderer c3-icon {
        width: 28px !important; height: 28px !important;
      }
      /* Text tabs instead of chips. */
      ytm-feed-filter-chip-bar-renderer { transition: transform .22s ease; }
      ytm-mobile-topbar-renderer { transition: transform .22s ease; }
      ytm-feed-filter-chip-bar-renderer ytm-chip-cloud-chip-renderer.more-drawer,
      ytm-feed-filter-chip-bar-renderer ytm-chip-divider-renderer {
        display: none !important;
      }
      ytm-feed-filter-chip-bar-renderer ytm-chip-cloud-chip-renderer,
      ytm-feed-filter-chip-bar-renderer .transpono-tab {
        margin: 0 10px !important; padding: 0 !important;
      }
      ytm-feed-filter-chip-bar-renderer .chip-container.chip-container.chip-container.chip-container,
      ytm-feed-filter-chip-bar-renderer .transpono-tab {
        background: transparent !important; border: 0 !important;
        border-radius: 0 !important; padding: 0 2px !important;
        height: 40px !important; min-width: 0 !important;
        display: flex !important; align-items: center !important;
        color: var(--yt-spec-text-primary, #f1f1f1) !important;
        font-size: 17px !important; font-weight: 500 !important;
        white-space: nowrap; box-sizing: border-box !important;
        border-bottom: 3px solid transparent !important;
      }
      /* The row is a line of inline blocks: the extra tab stays in it. */
      ytm-feed-filter-chip-bar-renderer .transpono-tab {
        display: inline-flex !important; vertical-align: top !important;
      }
      ytm-feed-filter-chip-bar-renderer .chip-container.chip-container.chip-container.chip-container * {
        color: inherit !important; font-size: inherit !important;
        font-weight: inherit !important; background: transparent !important;
      }
      ytm-feed-filter-chip-bar-renderer ytm-chip-cloud-chip-renderer[aria-selected="true"] .chip-container.chip-container.chip-container.chip-container {
        border-bottom-color: #ff0033 !important;
      }
      /* Scrolled down: both bars slide away. */
      html.transpono-bars-away ytm-mobile-topbar-renderer,
      html.transpono-bars-away ytm-feed-filter-chip-bar-renderer {
        transform: translateY(-110px) !important;
      }
      html.transpono-bars-away ytm-pivot-bar-renderer {
        transform: translateY(60px) !important;
      }
      /* The app's own row of tabs (see ensureTopTabs): it stands where the
         site's filter chips are on the home page, and is also there on the
         subscriptions page, which has no chips. */
      .tp-tabs {
        position: fixed; left: 0; right: 0; top: 48px; height: 48px;
        z-index: 3; display: flex; align-items: stretch;
        overflow-x: auto; overflow-y: hidden; white-space: nowrap;
        padding: 0 6px; box-sizing: border-box;
        background: var(--yt-spec-base-background, #0f0f0f);
        transition: transform .22s ease;
        scrollbar-width: none;
      }
      .tp-tabs::-webkit-scrollbar { display: none; }
      .tp-tabs .tp-tab {
        flex: 0 0 auto; display: flex; align-items: center;
        height: 40px; margin: 0 10px; padding: 0 2px;
        border: 0; border-bottom: 3px solid transparent; background: none;
        color: var(--yt-spec-text-primary, #f1f1f1);
        font: 500 17px/1 Roboto, Arial, sans-serif; box-sizing: border-box;
      }
      .tp-tabs .tp-tab[aria-selected="true"] { border-bottom-color: #ff0033; }
      html.tp-tabs-on ytm-feed-filter-chip-bar-renderer { visibility: hidden !important; }
      html.tp-tabs-on.tp-tabs-pad .page-container { padding-top: 48px !important; }
      html.transpono-bars-away .tp-tabs { transform: translateY(-110px) !important; }
      html.tp-native-bar.tp-native-bar.tp-native-bar ytm-pivot-bar-renderer {
        opacity: 0 !important; pointer-events: none !important;
      }
      html.tp-shorts.tp-shorts ytm-mobile-topbar-renderer#header-bar,
      html.tp-shorts.tp-shorts ytm-mobile-topbar-renderer#header-bar header {
        background: transparent !important; box-shadow: none !important;
        border: 0 !important;
      }
      html.tp-shorts ytm-mobile-topbar-renderer#header-bar header,
      html.tp-shorts ytm-mobile-topbar-renderer#header-bar header * {
        color: #fff !important;
      }
      html.tp-shorts ytm-mobile-topbar-renderer#header-bar svg {
        filter: drop-shadow(0 0 2px rgba(0, 0, 0, .7));
      }
      /* Subscriptions page: the row of channels like the YouTube app's,
         larger pictures with the channel's name under each, and the word
         "all" instead of an arrow. */
      ytm-channel-list-sub-menu-renderer.YtmChannelListSubMenuRendererHost {
        height: auto !important; min-height: 0 !important;
        align-items: flex-start !important; padding: 10px 0 6px !important;
      }
      ytm-channel-list-sub-menu-renderer .YtmChannelListSubMenuRendererAvatars {
        height: auto !important; white-space: nowrap !important;
      }
      ytm-channel-list-sub-menu-avatar-renderer.YtmChannelListSubMenuAvatarRendererHost {
        width: 72px !important; height: auto !important;
        margin: 0 3px !important; padding: 0 !important;
        vertical-align: top !important; text-align: center !important;
        position: relative !important;
      }
      ytm-channel-list-sub-menu-avatar-renderer > a {
        display: block !important; width: 72px !important; height: auto !important;
        text-decoration: none !important;
      }
      ytm-channel-list-sub-menu-avatar-renderer ytm-profile-icon,
      ytm-channel-list-sub-menu-avatar-renderer img.ytProfileIconImage {
        width: 56px !important; height: 56px !important; border-radius: 50% !important;
      }
      ytm-channel-list-sub-menu-avatar-renderer > a::after {
        content: attr(aria-label); display: block; margin: 6px auto 0;
        max-width: 68px; overflow: hidden; text-overflow: ellipsis;
        white-space: nowrap; font-size: 12px; line-height: 16px;
        color: var(--yt-spec-text-primary, #f1f1f1);
      }
      ytm-channel-list-sub-menu-renderer a.channel-list-sub-menu-show-all {
        width: auto !important; height: 56px !important;
        display: flex !important; align-items: center !important;
        padding: 0 12px 0 8px !important; text-decoration: none !important;
      }
      ytm-channel-list-sub-menu-renderer a.channel-list-sub-menu-show-all .icon-button {
        display: none !important;
      }
      ytm-channel-list-sub-menu-renderer a.channel-list-sub-menu-show-all::after {
        content: 'Todos'; font-size: 14px; font-weight: 500; color: #3ea6ff;
      }
      /* Search: one rounded field and the round microphone, on the page's
         own background, like the YouTube app's search screen. */
      ytm-mobile-topbar-renderer header[data-mode="searching"] {
        background: var(--yt-spec-base-background, #0f0f0f) !important;
      }
      header[data-mode="searching"] .ytSearchboxComponentInputBox {
        border-radius: 20px !important; height: 40px !important;
        margin-top: -4px !important;
        background: var(--yt-spec-raised-background, #272727) !important;
        display: flex !important; align-items: center !important;
        flex: 1 1 auto !important;
      }
      header[data-mode="searching"] .ytSearchboxComponentSearchButton {
        display: none !important;
      }
      header[data-mode="searching"] .ytSearchboxComponentVoiceSearchWrapper {
        width: 40px !important; height: 40px !important; margin-top: -4px !important;
        margin-left: 8px !important; border-radius: 50% !important;
        display: flex !important; align-items: center !important;
        justify-content: center !important;
        background: var(--yt-spec-raised-background, #272727) !important;
      }
      header[data-mode="searching"] .ytSearchboxComponentInput { font-size: 16px !important; }
      /* Search suggestions like the YouTube app's list: one colour (the
         page's own), white text, an icon on the left (a clock for past
         searches, a magnifier for the others) and taller rows. */
      .ytSearchboxComponentSuggestionsContainer.ytSearchboxComponentSuggestionsContainer {
        background: var(--yt-spec-base-background, #0f0f0f) !important;
        border: 0 !important; box-shadow: none !important;
      }
      .ytSearchboxComponentSuggestionsContainer .ytSuggestionComponentSuggestion {
        display: flex !important; align-items: center !important;
        min-height: 48px !important; height: auto !important;
        padding: 0 4px 0 16px !important; border: 0 !important;
        background: transparent !important;
        color: var(--yt-spec-text-primary, #f1f1f1) !important;
      }
      .ytSearchboxComponentSuggestionsContainer .ytSuggestionComponentText {
        flex: 1 1 auto !important; min-width: 0 !important;
        font-size: 16px !important; line-height: 22px !important;
        color: inherit !important; background: transparent !important;
      }
      .ytSearchboxComponentSuggestionsContainer .ytSuggestionComponentText * {
        color: inherit !important;
      }
      .ytSearchboxComponentSuggestionsContainer .ytSuggestionComponentLeftContainer {
        display: flex !important; flex-direction: row !important;
        flex-wrap: nowrap !important; align-items: center !important;
        justify-content: flex-start !important; text-align: left !important;
        min-width: 0 !important;
      }
      .ytSearchboxComponentSuggestionsContainer .ytSuggestionComponentLeftContainer > span {
        flex: 1 1 auto !important; min-width: 0 !important;
        overflow: hidden !important; text-overflow: ellipsis !important;
        white-space: nowrap !important;
      }
      .ytSearchboxComponentSuggestionsContainer .ytSuggestionComponentLeftContainer::before {
        content: ''; flex: 0 0 24px; width: 24px; height: 24px; margin-right: 20px;
        background: currentColor;
        -webkit-mask: url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'><path d='M15.5 14h-.79l-.28-.27A6.471 6.471 0 0 0 16 9.5 6.5 6.5 0 1 0 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z'/></svg>") center / contain no-repeat;
        mask: url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'><path d='M15.5 14h-.79l-.28-.27A6.471 6.471 0 0 0 16 9.5 6.5 6.5 0 1 0 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z'/></svg>") center / contain no-repeat;
      }
      .ytSearchboxComponentSuggestionsContainer .ytSuggestionComponentPersonalizedSuggestion .ytSuggestionComponentLeftContainer::before {
        -webkit-mask-image: url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'><path d='M13 3a9 9 0 0 0-9 9H1l3.89 3.89.07.14L9 12H6c0-3.87 3.13-7 7-7s7 3.13 7 7-3.13 7-7 7c-1.93 0-3.68-.79-4.94-2.06l-1.42 1.42A8.954 8.954 0 0 0 13 21a9 9 0 0 0 0-18zm-1 5v5l4.28 2.54.72-1.21-3.5-2.08V8H12z'/></svg>");
        mask-image: url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'><path d='M13 3a9 9 0 0 0-9 9H1l3.89 3.89.07.14L9 12H6c0-3.87 3.13-7 7-7s7 3.13 7 7-3.13 7-7 7c-1.93 0-3.68-.79-4.94-2.06l-1.42 1.42A8.954 8.954 0 0 0 13 21a9 9 0 0 0 0-18zm-1 5v5l4.28 2.54.72-1.21-3.5-2.08V8H12z'/></svg>");
      }
      .ytSearchboxComponentSuggestionsContainer .ytSuggestionComponentBold {
        font-weight: 400 !important;
      }
      .ytSearchboxComponentSuggestionsContainer .ytSuggestionComponentRightContainer,
      .ytSearchboxComponentSuggestionsContainer .ytSuggestionComponentRightContainer * {
        background: transparent !important;
      }
      .ytSearchboxComponentSuggestionsContainer .ytSuggestionComponentRightContainer {
        color: var(--yt-spec-text-primary, #f1f1f1) !important;
      }
      .ytSearchboxComponentSuggestionsContainer .ytSuggestionComponentRemoveLink {
        color: var(--yt-spec-text-secondary, #aaa) !important;
        font-size: 13px !important; padding: 0 12px !important;
      }
      /* iPhone, like the YouTube app there: the bottom bar is a floating
         pill, the tab being shown stands on a lighter patch, and the "you"
         page is plain dark with outlined buttons. */
      html.tp-ios.tp-ios ytm-pivot-bar-renderer {
        left: 24px !important; right: 24px !important; width: auto !important;
        bottom: 10px !important; height: 52px !important;
        padding: 0 4px !important; border-radius: 26px !important;
        /* Glass: the page shows through, blurred, with a light rim. */
        border: 1px solid rgba(255, 255, 255, .18) !important;
        background: transparent !important;
        box-shadow: inset 0 1px 0 rgba(255, 255, 255, .16),
          0 8px 24px rgba(0, 0, 0, .35) !important;
        overflow: hidden !important;
      }
      /* Two layers of glass: the middle blurs what is behind it; the rim
         keeps it almost sharp, brighter and more vivid, so the edges read
         as a lens bending the page (page CSS cannot truly refract). */
      html.tp-ios ytm-pivot-bar-renderer::after,
      html.tp-ios ytm-pivot-bar-renderer::before {
        content: ''; position: absolute; z-index: -1; pointer-events: none;
      }
      html.tp-ios ytm-pivot-bar-renderer::after {
        inset: 5px; border-radius: 21px;
        background: rgba(30, 30, 30, .45);
        -webkit-backdrop-filter: blur(22px) saturate(180%);
        backdrop-filter: blur(22px) saturate(180%);
      }
      html.tp-ios ytm-pivot-bar-renderer::before {
        inset: 0; border-radius: 26px; padding: 5px;
        background: linear-gradient(180deg, rgba(255, 255, 255, .22),
          rgba(255, 255, 255, .04) 45%, rgba(255, 255, 255, .14));
        -webkit-backdrop-filter: blur(3px) brightness(1.35) saturate(220%) contrast(1.15);
        backdrop-filter: blur(3px) brightness(1.35) saturate(220%) contrast(1.15);
        -webkit-mask: linear-gradient(#000 0 0) content-box, linear-gradient(#000 0 0);
        -webkit-mask-composite: xor;
        mask: linear-gradient(#000 0 0) content-box exclude, linear-gradient(#000 0 0);
      }
      html.tp-ios[data-transpono-theme="light"] ytm-pivot-bar-renderer::after {
        background: rgba(250, 250, 250, .5);
      }
      html.tp-ios.tp-ios[data-transpono-theme="light"] ytm-pivot-bar-renderer {
        border-color: rgba(0, 0, 0, .1) !important;
      }
      html.tp-ios ytm-pivot-bar-renderer .pivot-bar-item-tab {
        height: 42px !important; margin: 4px 2px !important;
        border-radius: 21px !important;
      }
      html.tp-ios ytm-pivot-bar-renderer .pivot-bar-item-tab[aria-selected="true"] {
        background: rgba(255, 255, 255, .16) !important;
      }
      html.tp-ios[data-transpono-theme="light"] ytm-pivot-bar-renderer .pivot-bar-item-tab[aria-selected="true"] {
        background: rgba(0, 0, 0, .1) !important;
      }
      html.tp-ios.transpono-bars-away ytm-pivot-bar-renderer {
        transform: translateY(90px) !important;
      }
      html.tp-ios.tp-library.tp-library .page-container,
      html.tp-ios.tp-library.tp-library ytm-mobile-topbar-renderer#header-bar,
      html.tp-ios.tp-library.tp-library ytm-mobile-topbar-renderer#header-bar header {
        background: var(--yt-spec-base-background, #0f0f0f) !important;
      }
      html.tp-ios.tp-library.tp-library .ytContentMetadataViewModelMetadataRow > span:first-child {
        color: var(--yt-spec-text-secondary, #aaa) !important;
      }
      html.tp-ios.tp-library ytm-home-logo button::after {
        background: transparent; border: 1px solid rgba(128, 128, 128, .6);
      }
      html.tp-ios.tp-library .tp-channel a { background: #f1f1f1; }
      html.tp-ios.tp-library .ytFlexibleActionsViewModelAction button-view-model a {
        background: transparent !important;
        border: 1px solid rgba(128, 128, 128, .6) !important;
      }
      /* The "you" page dressed like the YouTube app's: a teal wash at the
         top, an accounts pill instead of the logo, the name large, a light
         "channel" button, plain section titles with an arrow, and the
         playlists as a list. Dark theme only for the colours. */
      html.tp-library:not([data-transpono-theme="light"]) ytm-mobile-topbar-renderer#header-bar,
      html.tp-library:not([data-transpono-theme="light"]) ytm-mobile-topbar-renderer#header-bar header {
        /* The bar has no colour of its own: it takes the colour the page's
           background has where the bar is (see libraryBarColour). */
        background: var(--tp-bar-bg, #0d3a42) !important;
      }
      html.tp-library:not([data-transpono-theme="light"]) .page-container {
        background: linear-gradient(180deg, #0d3a42 0px, #0f0f0f 430px) !important;
      }
      html.tp-library ytm-browse,
      html.tp-library yt-page-header-renderer,
      html.tp-library yt-page-header-view-model,
      html.tp-library ytm-single-column-browse-results-renderer,
      html.tp-library ytm-section-list-renderer,
      html.tp-library ytm-item-section-renderer {
        background: transparent !important;
      }
      html.tp-library ytm-home-logo c3-icon { display: none !important; }
      html.tp-library ytm-home-logo button::after {
        content: attr(data-tp-accounts) '  \\25BE';
        display: inline-flex; align-items: center; height: 36px;
        margin-left: 12px; padding: 0 16px; border-radius: 18px;
        background: rgba(255, 255, 255, .1);
        color: var(--yt-spec-text-primary, #f1f1f1);
        font-size: 15px; font-weight: 500; white-space: nowrap;
      }
      html.tp-library .dynamicTextViewModelH1 {
        font-size: 28px !important; line-height: 34px !important;
        font-weight: 700 !important;
      }
      html.tp-library:not([data-transpono-theme="light"]) .ytContentMetadataViewModelMetadataRow > span:first-child {
        color: #7fd6e8 !important;
      }
      html.tp-library .ytContentMetadataViewModelDelimiter,
      html.tp-library .ytContentMetadataViewModelMetadataTextLastPart {
        display: none !important;
      }
      html.tp-library .ytFlexibleActionsViewModelActionRow { gap: 8px; }
      html.tp-library .ytFlexibleActionsViewModelAction { flex: 1 1 0 !important; padding: 0 !important; }
      html.tp-library .ytFlexibleActionsViewModelAction:has(button):not(.tp-channel) {
        display: none !important;
      }
      html.tp-library .ytFlexibleActionsViewModelAction button-view-model,
      html.tp-library .ytFlexibleActionsViewModelAction button-view-model a {
        width: 100% !important; height: 36px !important; border-radius: 18px !important;
      }
      html.tp-library .tp-channel a {
        display: flex; align-items: center; justify-content: center;
        height: 36px; border-radius: 18px; text-decoration: none;
        background: #c9f3fb; color: #0f0f0f;
        font-size: 14px; font-weight: 500;
      }
      html.tp-library .horizontal-card-list-top-container {
        justify-content: flex-start !important; align-items: center !important;
      }
      html.tp-library .ytm-rich-list-header-title {
        font-size: 20px !important; line-height: 26px !important;
        font-weight: 700 !important; overflow: visible !important;
      }
      html.tp-library .horizontal-card-list-button a {
        border: 0 !important; background: none !important;
        min-width: 0 !important; padding: 0 6px !important;
      }
      html.tp-library .horizontal-card-list-button yt-light-shape { display: none !important; }
      html.tp-library .horizontal-card-list-button .ytSpecButtonShapeNextButtonTextContent {
        font-size: 0 !important;
      }
      html.tp-library .horizontal-card-list-button .ytSpecButtonShapeNextButtonTextContent::after {
        content: '\\203A'; font-size: 28px; line-height: 36px;
        color: var(--yt-spec-text-primary, #f1f1f1);
      }
      html.tp-library .horizontal-card-list-cards:has(ytm-playlist-card-renderer) {
        overflow-x: hidden !important; white-space: normal !important;
      }
      html.tp-library ytm-playlist-card-renderer.horizontal-card-list-card {
        display: flex !important; align-items: center !important;
        width: auto !important; margin: 0 12px 14px !important;
      }
      html.tp-library ytm-playlist-card-renderer .playlist-card-image {
        flex: 0 0 160px !important; width: 160px !important;
      }
      html.tp-library ytm-playlist-card-renderer .playlist-card-metadata {
        flex: 1 1 auto !important; min-width: 0 !important;
        padding-left: 16px !important;
      }
      html.tp-library ytm-playlist-card-renderer .playlist-card-title {
        font-size: 16px !important; line-height: 21px !important;
        max-height: 42px !important; white-space: normal !important;
      }
      html.tp-library ytm-playlist-card-renderer .playlist-card-title-container {
        height: auto !important;
      }`;
    (document.head || document.documentElement).appendChild(bars);
  }
  // The row of tabs under the top bar, like the YouTube app's: home,
  // subscriptions, music, live and "more". The site has filter chips on the
  // home page only; this row stands in their place there and stays on the
  // subscriptions page too. Each tab works the site's own controls: the
  // bottom-bar tabs (home, subscriptions), the home page's "music" and
  // "live" chips, and the "explore" drawer for "more".
  function ensureTopTabs() {
    if (!plainYouTube()) return;
    try {
      const root = document.documentElement;
      const path = window.location.pathname;
      const wanted = (path === '/' || path === '/feed/subscriptions') &&
        !!document.querySelector('ytm-pivot-bar-renderer');
      let row = document.querySelector('.tp-tabs');
      if (!wanted) {
        if (row) row.remove();
        root.classList.remove('tp-tabs-on', 'tp-tabs-pad');
        return;
      }
      const chipRow = document.querySelector(
        'ytm-feed-filter-chip-bar-renderer .chip-bar-contents');
      const chips = chipRow
        ? [...chipRow.querySelectorAll('ytm-chip-cloud-chip-renderer')] : [];
      const words = chip => (chip.textContent || '').trim();
      const chipOf = kind => {
        if (kind === 'home') return chips.find(c => c.classList.contains('all-chip-renderer'));
        if (kind === 'music') return chips.find(c => /^(m[uú]sica|music)$/i.test(words(c)));
        if (kind === 'live') return chips.find(c => /^(ao vivo|em direto|live)$/i.test(words(c)));
        if (kind === 'more') return chips.find(c => c.classList.contains('more-drawer'));
        return null;
      };
      const tap = element => {
        if (!element) return false;
        (element.querySelector('.chip-container') || element).click();
        return true;
      };
      // A tab whose control only exists on the home page: go there first,
      // then use it as soon as it shows up.
      const pending = window.__transponoPendingTab;
      if (pending && path === '/' && chipOf(pending)) {
        window.__transponoPendingTab = null;
        tap(chipOf(pending));
      }
      const pivotLabel = name => {
        const title = document.querySelector(
          `ytm-pivot-bar-renderer .${name} .pivot-bar-item-title`);
        return title ? (title.textContent || '').trim() : '';
      };
      const remembered = window.__transponoTabLabels || (window.__transponoTabLabels = {});
      const label = (kind, found, fallback) => {
        if (found) remembered[kind] = found;
        return remembered[kind] || fallback;
      };
      const tabs = [
        ['home', label('home', pivotLabel('pivot-w2w'), 'Início')],
        ['subs', label('subs', pivotLabel('pivot-subs'), 'Inscrições')],
        ['music', label('music', chipOf('music') ? words(chipOf('music')) : '', 'Música')],
        ['live', label('live', chipOf('live') ? words(chipOf('live')) : '', 'Ao vivo')],
        ['more', 'Mais'],
      ];
      if (!row) {
        row = document.createElement('div');
        row.className = 'tp-tabs';
        row.setAttribute('role', 'tablist');
        row.addEventListener('click', event => {
          const tab = event.target && event.target.closest
            ? event.target.closest('.tp-tab') : null;
          if (!tab) return;
          event.preventDefault();
          event.stopPropagation();
          const kind = tab.getAttribute('data-kind');
          const here = window.location.pathname;
          const pivot = name => {
            const target = document.querySelector(`ytm-pivot-bar-renderer .${name}`);
            if (target) target.click();
          };
          if (kind === 'subs') {
            pivot('pivot-subs');
          } else if (here !== '/') {
            window.__transponoPendingTab = kind;
            pivot('pivot-w2w');
          } else {
            const live = document.querySelector(
              'ytm-feed-filter-chip-bar-renderer .chip-bar-contents');
            const all = live ? [...live.querySelectorAll('ytm-chip-cloud-chip-renderer')] : [];
            const text = chip => (chip.textContent || '').trim();
            const target =
              kind === 'home' ? all.find(c => c.classList.contains('all-chip-renderer')) :
              kind === 'music' ? all.find(c => /^(m[uú]sica|music)$/i.test(text(c))) :
              kind === 'live' ? all.find(c => /^(ao vivo|em direto|live)$/i.test(text(c))) :
              all.find(c => c.classList.contains('more-drawer'));
            if (target) (target.querySelector('.chip-container') || target).click();
          }
          if (typeof window.__transponoPostFocus === 'function') window.__transponoPostFocus();
        });
        document.body.appendChild(row);
      }
      // Which tab is the one being shown.
      const selectedChip = chips.find(c => c.getAttribute('aria-selected') === 'true');
      const drawerOpen = !!document.querySelector('.ytmDrawerLayoutContainerOpened');
      const current = path === '/feed/subscriptions' ? 'subs'
        : drawerOpen ? 'more'
        : selectedChip && selectedChip === chipOf('music') ? 'music'
        : selectedChip && selectedChip === chipOf('live') ? 'live'
        : 'home';
      const signature = tabs.map(t => t.join(':')).join('|');
      if (row.getAttribute('data-tabs') !== signature) {
        row.setAttribute('data-tabs', signature);
        while (row.firstChild) row.removeChild(row.firstChild);
        for (const [kind, text] of tabs) {
          const tab = document.createElement('button');
          tab.className = 'tp-tab';
          tab.setAttribute('type', 'button');
          tab.setAttribute('role', 'tab');
          tab.setAttribute('data-kind', kind);
          tab.textContent = text;
          row.appendChild(tab);
        }
      }
      for (const tab of row.children) {
        const on = tab.getAttribute('data-kind') === current;
        if (tab.getAttribute('aria-selected') !== String(on)) {
          tab.setAttribute('aria-selected', String(on));
        }
      }
      root.classList.add('tp-tabs-on');
      // The home page already keeps room for its chips; other pages do not.
      root.classList.toggle('tp-tabs-pad', !chipRow);
    } catch (_) {
      // The row is an extra: the page works without it.
    }
  }
  // The site's "open the app" button in the top bar has no use inside this
  // app: it goes, and the app's own start-screen icon takes its place. Found
  // by its words, since the site gives it no stable name.
  function hideOpenApp(header) {
    try {
      for (const button of header.querySelectorAll('a, button')) {
        if (button.__transponoChecked) continue;
        button.__transponoChecked = true;
        const words = ((button.getAttribute('aria-label') || '') + ' ' +
          (button.textContent || '')).trim();
        if (!/^(abrir|open|abre|usar)\b.*\b(app|aplicativo|aplicação)\b/i.test(words)) continue;
        const holder = button.closest('ytm-button-renderer') || button;
        holder.style.setProperty('display', 'none', 'important');
      }
    } catch (_) {}
  }
  // Shorts start in a low quality inside an app's page (360p on a phone
  // that shows 1080p): ask the site's player for HD, once per Short and
  // again if it fell back.
  function shortsQuality() {
    try {
      if (!/^\/shorts(\/|$)/.test(window.location.pathname)) return;
      const element = document.querySelector('#movie_player');
      const player = element && (element.wrappedJSObject || element);
      if (!player || typeof player.setPlaybackQualityRange !== 'function') return;
      const now = Date.now();
      const id = window.location.pathname;
      const low = typeof player.getPlaybackQuality === 'function' &&
        /^(tiny|small|medium|large)$/.test(player.getPlaybackQuality() || '');
      if (window.__transponoShortsQ === id &&
          (!low || now - (window.__transponoShortsQAt || 0) < 4000)) return;
      const levels = typeof player.getAvailableQualityLevels === 'function'
        ? Array.from(player.getAvailableQualityLevels() || []) : [];
      const best = ['hd1080', 'hd720'].find(level => levels.indexOf(level) >= 0);
      if (!best) return;
      window.__transponoShortsQ = id;
      window.__transponoShortsQAt = now;
      player.setPlaybackQualityRange(best, best);
    } catch (_) {
      // Quality stays as the site chose it.
    }
  }
  // Leaving the site's search. Its back arrow steps back in the page's
  // history; when the search is the only entry there (the page was loaded
  // again while searching) that does nothing and the search could not be
  // left at all. So: use the arrow, and if the search is still open a
  // moment later, load the page again without the search mark.
  const searchOpen = () => {
    const header = document.querySelector(
      'ytm-mobile-topbar-renderer header.mobile-topbar-header');
    return !!header && header.getAttribute('data-mode') === 'searching';
  };
  const leaveSearchFallback = () => {
    setTimeout(() => {
      try {
        if (!searchOpen()) return;
        window.location.replace(window.location.href.split('#')[0]);
      } catch (_) {}
    }, 600);
  };
  if (plainYouTube() && !window.__transponoLeaveSearch) {
    window.__transponoLeaveSearch = () => {
      try {
        if (!searchOpen()) return;
        const back = document.querySelector(
          'ytm-mobile-topbar-renderer .mobile-topbar-back-arrow');
        if (back) back.click();
        leaveSearchFallback();
      } catch (_) {}
    };
    if (typeof document.addEventListener === 'function') {
      // A finger on the arrow gets the same safety net.
      document.addEventListener('click', event => {
        if (!event.isTrusted || !event.target || !event.target.closest) return;
        if (event.target.closest('.mobile-topbar-back-arrow') && searchOpen()) {
          leaveSearchFallback();
        }
      }, true);
    }
  }
  // The app's start-screen icon is drawn by the page itself, inside the
  // site's top bar, so it moves with the bar exactly (sliding away and back,
  // scrolling with the video page): an icon drawn by the app over the page
  // always arrived a moment late. A tap is counted and the app acts on it.
  function placeHomeIcon(header, free, right) {
    try {
      if (!header || typeof document.createElementNS !== 'function') return false;
      let icon = header.querySelector('.tp-home-icon');
      if (!icon) {
        icon = document.createElement('button');
        icon.className = 'tp-home-icon';
        icon.setAttribute('type', 'button');
        icon.setAttribute('aria-label', 'Menu inicial do Transpono');
        icon.style.cssText = 'position:absolute;top:0;width:48px;height:48px;' +
          'margin:0;padding:12px;border:0;background:none;box-sizing:border-box;' +
          'color:var(--yt-spec-text-primary,#f1f1f1);z-index:3;';
        const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
        svg.setAttribute('viewBox', '0 0 24 24');
        svg.setAttribute('width', '24');
        svg.setAttribute('height', '24');
        const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
        path.setAttribute('fill', 'currentColor');
        path.setAttribute('d', 'M4 8h4V4H4v4zm6 12h4v-4h-4v4zm-6 0h4v-4H4v4zm0-6h4v-4H4v4z' +
          'm6 0h4v-4h-4v4zm6-10v4h4V4h-4zm-6 4h4V4h-4v4zm6 6h4v-4h-4v4zm0 6h4v-4h-4v4z');
        svg.appendChild(path);
        icon.appendChild(svg);
        icon.addEventListener('click', event => {
          event.preventDefault();
          event.stopPropagation();
          window.__transponoHomeSeq = (window.__transponoHomeSeq || 0) + 1;
          if (typeof window.__transponoPostFocus === 'function') window.__transponoPostFocus();
        });
        if (getComputedStyle(header).position === 'static') header.style.position = 'relative';
        header.appendChild(icon);
      }
      // Measured against the header's own box (it can be narrower than the
      // page when the phone is on its side).
      const box = header.getBoundingClientRect();
      const fromRight = Math.max(0, Math.round(right - (window.innerWidth - box.right)));
      icon.style.right = fromRight + 'px';
      icon.style.display = free ? 'block' : 'none';
      return free;
    } catch (_) {
      return false;
    }
  }
  // Bars away while reading down a list page; never on a video page or while
  // typing in the search field.
  function syncBarsAway() {
    if (!plainYouTube()) return;
    try {
      const field = document.activeElement;
      const typing = !!field && !!field.matches &&
        field.matches('input, textarea, [contenteditable="true"]');
      const away = window.__transponoScrollDir === 'down' && !typing &&
        window.location.pathname !== '/watch' &&
        !document.documentElement.classList.contains('transpono-mini');
      document.documentElement.classList.toggle('transpono-bars-away', away);
    } catch (_) {}
  }
  // The "you" page's top bar copies the background behind it: the page's
  // wash goes from teal (13, 58, 66) at the top to the page's dark
  // (15, 15, 15) 430 px down, and the bar shows the colour at its own place
  // as the page scrolls under it, so it reads as see-through to the
  // background only, never to the content.
  function libraryBarColour() {
    try {
      const root = document.documentElement;
      if (!root.classList.contains('tp-library')) return;
      const scroller = document.scrollingElement || root;
      const top = Math.max(0, window.scrollY || scroller.scrollTop || 0);
      const t = Math.min(1, top / 430);
      const mix = (a, b) => Math.round(a + (b - a) * t);
      root.style.setProperty(
        '--tp-bar-bg', `rgb(${mix(13, 15)}, ${mix(58, 15)}, ${mix(66, 15)})`);
    } catch (_) {}
  }
  // The "you" page: the accounts pill takes the logo's place (it opens the
  // site's own account switcher) and a light "channel" button stands where
  // the switcher's button was, opening the channel link the page shows.
  function dressLibraryPage() {
    if (!plainYouTube()) return;
    try {
      const root = document.documentElement;
      const library = window.location.pathname === '/feed/library';
      root.classList.toggle('tp-library', library);
      if (!library) return;
      const switcher = document.querySelector('.ytFlexibleActionsViewModelAction button');
      const logo = document.querySelector('ytm-home-logo button');
      if (logo && switcher && !logo.hasAttribute('data-tp-accounts')) {
        const words = (switcher.getAttribute('aria-label') || '').trim().split(/\s+/);
        // "Mudar de conta" → "Contas": the last word, in the plural.
        const last = words.length ? words[words.length - 1] : '';
        logo.setAttribute('data-tp-accounts',
          last ? last.charAt(0).toUpperCase() + last.slice(1) + 's' : 'Contas');
      }
      if (!window.__transponoBarColour && typeof document.addEventListener === 'function') {
        window.__transponoBarColour = true;
        document.addEventListener('scroll', libraryBarColour, {passive: true, capture: true});
      }
      libraryBarColour();
      if (!window.__transponoAccountsTap && typeof document.addEventListener === 'function') {
        window.__transponoAccountsTap = true;
        document.addEventListener('click', event => {
          if (!document.documentElement.classList.contains('tp-library')) return;
          if (!event.target || !event.target.closest ||
              !event.target.closest('ytm-home-logo')) return;
          const target = document.querySelector('.ytFlexibleActionsViewModelAction button');
          if (!target) return;
          event.preventDefault();
          event.stopPropagation();
          target.click();
        }, true);
      }
      const row = document.querySelector('.ytFlexibleActionsViewModelActionRow');
      const channel = document.querySelector(
        '.ytContentMetadataViewModelMetadataTextLastPart a[href^="/channel/"], ' +
        '.ytContentMetadataViewModelMetadataTextLastPart a[href^="/@"]');
      if (row && channel && !row.querySelector('.tp-channel')) {
        const holder = document.createElement('div');
        holder.className =
          'ytFlexibleActionsViewModelAction ytFlexibleActionsViewModelActionRowAction tp-channel';
        const link = document.createElement('a');
        link.setAttribute('href', channel.getAttribute('href'));
        link.textContent = (channel.textContent || '').trim() || 'Ver canal';
        holder.appendChild(link);
        row.insertBefore(holder, row.firstChild);
      }
    } catch (_) {
      // Dressing only: the page works without it.
    }
  }
  // YouTube Music, dressed in the same way as YouTube: no "open the app"
  // button or prompt, the app's start-screen icon in the site's top bar, the
  // top bar sliding away while scrolling down, and (drawn by the app, since
  // the site has none on a phone) a bottom bar with home, explore, the
  // adjustments and the library.
  const musicYouTube = () => /^music\.youtube\.com$/i.test(window.location.hostname);
  if (musicYouTube() && !window.__transponoMusicBars) {
    window.__transponoMusicBars = true;
    const music = document.createElement('style');
    music.id = 'transpono-music-style';
    music.textContent = `
      ytmusic-nav-bar .app-install-link { display: none !important; }
      ytmusic-nav-bar, #nav-bar-background { transition: transform .22s ease; }
      html.transpono-bars-away ytmusic-nav-bar,
      html.transpono-bars-away #nav-bar-background {
        transform: translateY(-80px) !important;
      }`;
    (document.head || document.documentElement).appendChild(music);
  }
  function musicBars() {
    if (!musicYouTube()) return null;
    try {
      // The site's "open in the YouTube Music app" prompt: answer "not now".
      const prompt = document.querySelector('ytmusic-popup-container tp-yt-paper-dialog');
      if (prompt && prompt.offsetHeight > 0 && !prompt.__transponoDismissed &&
          /app YouTube Music/i.test(prompt.textContent || '')) {
        const decline = [...prompt.querySelectorAll('button')].find(
          button => !/^(abrir|open|abre)\b/i.test((button.textContent || '').trim()));
        if (decline) {
          prompt.__transponoDismissed = true;
          decline.click();
        }
      }
      const field = document.activeElement;
      const typing = !!field && !!field.matches &&
        field.matches('input, textarea, [contenteditable="true"]');
      const away = window.__transponoScrollDir === 'down' && !typing;
      document.documentElement.classList.toggle('transpono-bars-away', away);
      const nav = document.querySelector('ytmusic-nav-bar');
      const search = nav ? nav.querySelector('ytmusic-search-box') : null;
      const searchLeft = search ? search.getBoundingClientRect().left : 0;
      // Room for the icon: left of the search button, where "open the app"
      // was; not while the search field is opened over the bar.
      const topFree = !!nav && nav.offsetHeight > 20 && !typing &&
        searchLeft > window.innerWidth / 2;
      const topRight = Math.round(window.innerWidth - searchLeft);
      const homeInPage = placeHomeIcon(nav, topFree, topRight);
      if (nav) {
        const icon = nav.querySelector('.tp-home-icon');
        if (icon) icon.style.top = '8px';
      }
      const picture = nav ? nav.querySelector('ytmusic-settings-button img') : null;
      const path = window.location.pathname;
      return {
        pivot: null,
        pivotX: null,
        topFree,
        topRight,
        hidden: away,
        searching: false,
        shorts: false,
        music: true,
        avatar: picture && /^https:\/\//.test(picture.src || '') ? picture.src : '',
        tab: path === '/' ? 'home'
          : /^\/explore/.test(path) ? 'explore'
          : /^\/library/.test(path) ? 'library' : '',
        topAway: !topFree,
        homeInPage,
        dark: true,
      };
    } catch (_) {
      return null;
    }
  }
  // Where the page's own bars are, for the app's buttons that sit in them.
  // Measured from the layout (offset*), so a bar that is sliding in or out
  // reports its resting place.
  function pageBars() {
    if (!plainYouTube()) return null;
    try {
      // iPhone: the app says so (its engine there does not show it in the
      // page); any iOS browser's own name counts too.
      const agent = navigator.userAgent || '';
      document.documentElement.classList.toggle('tp-ios',
        window.__transponoIOS === true || /iPhone|iPad|iPod/.test(agent));
      // The app draws the bottom bar itself (iPhone's own glass): the
      // site's bar stays in the page, working but unseen.
      document.documentElement.classList.toggle('tp-native-bar',
        window.__transponoNativeBar === true);
      // The Shorts page: the site's top bar floats over the video, with no
      // band of its own, like in the YouTube app.
      document.documentElement.classList.toggle('tp-shorts',
        /^\/shorts(\/|$)/.test(window.location.pathname));
      ensureTopTabs();
      dressLibraryPage();
      shortsQuality();
      syncBarsAway();
      const bar = document.querySelector('ytm-pivot-bar-renderer');
      const shorts = bar
        ? bar.querySelector('ytm-pivot-bar-item-renderer:has(.pivot-shorts)') : null;
      // The account picture of the bar's last tab, kept for the bar the app
      // draws itself under the Shorts page (the site has none there).
      try {
        const picture = bar && bar.querySelector('.pivot-you img, avatar-view-model img');
        if (picture && picture.src && /^https:\/\//.test(picture.src)) {
          window.__transponoAvatar = picture.src;
          window.localStorage.setItem('transpono-avatar', picture.src);
        } else if (!window.__transponoAvatar) {
          window.__transponoAvatar = window.localStorage.getItem('transpono-avatar') || '';
        }
      } catch (_) {}
      const shown = !!bar && !!shorts && bar.offsetHeight > 20 &&
        getComputedStyle(bar).visibility !== 'hidden';
      // The site's top bar, on any of its pages (lists, a video, a playlist,
      // a channel…). The app's start-screen icon lives only there, just left
      // of the bar's own icons on the right (search; on some pages also
      // settings or a menu). Where the bar has no room for it (a search
      // field fills it), is scrolled out of sight or does not exist, the
      // icon is hidden: it never floats over the page.
      const header = document.querySelector(
        'ytm-mobile-topbar-renderer header.mobile-topbar-header');
      const barThere = !!header && header.offsetHeight > 20;
      const searching = !!header && header.getAttribute('data-mode') === 'searching';
      if (barThere) hideOpenApp(header);
      const away = document.documentElement.classList.contains('transpono-bars-away');
      let topFree = barThere &&
        (away || header.getBoundingClientRect().top > -8);
      let topRight = 48;
      if (topFree) {
        let left = window.innerWidth;
        for (const icon of header.querySelectorAll('button, a')) {
          if (icon.classList.contains('tp-home-icon')) continue;
          const at = icon.getBoundingClientRect();
          if (at.width > 20 && at.width < 80 && at.left > window.innerWidth / 2) {
            left = Math.min(left, at.left);
          }
        }
        topRight = Math.round(window.innerWidth - left);
        // The icon's own 48 px slot must be free of the search field.
        const slotLeft = left - 48;
        for (const field of header.querySelectorAll('input:not([type="file"])')) {
          const at = field.getBoundingClientRect();
          if (at.width > 20 && at.height > 8 && at.right > slotLeft + 4) {
            topFree = false;
          }
        }
        if (slotLeft < window.innerWidth / 3) topFree = false;
      }
      const topAway = !topFree;
      const homeInPage = placeHomeIcon(header, topFree, topRight);
      return {
        // Centre of the free slot: up from the bottom, and from the left.
        pivot: shown
          ? Math.round((parseFloat(getComputedStyle(bar).bottom) || 0) + bar.offsetHeight / 2)
          : null,
        pivotX: shown
          ? Math.round((shorts.offsetParent === bar ? bar.offsetLeft : 0) +
              shorts.offsetLeft + shorts.offsetWidth * 1.5)
          : null,
        topFree,
        topRight,
        // Also while the site's side drawer ("more") covers the page.
        hidden: away || searching ||
          !!document.querySelector('.ytmDrawerLayoutContainerOpened'),
        // The search field is open (with its list of suggestions): the
        // system's back button closes it.
        searching,
        // The Shorts page: the site shows no bottom bar there, the app draws
        // one under the page.
        shorts: !bar && /^\/shorts(\/|$)/.test(window.location.pathname),
        avatar: typeof window.__transponoAvatar === 'string' ? window.__transponoAvatar : '',
        // Which of the bar's tabs is the page being shown.
        tab: (path => path === '/' ? 'home'
          : /^\/shorts(\/|$)/.test(path) ? 'shorts'
          : path === '/feed/library' ? 'you' : '')(window.location.pathname),
        topAway,
        homeInPage,
        dark: document.documentElement.getAttribute('data-transpono-theme') !== 'light',
      };
    } catch (_) {
      return null;
    }
  }
  if (soundCloud() && !window.__transponoPlayHook) {
    window.__transponoPlayHook = true;
    try {
      const pageWindow = window.wrappedJSObject || window;
      const proto = pageWindow.HTMLMediaElement.prototype;
      const originalPlay = proto.play;
      const remember = function () {
        window.__transponoPlaying = this;
        return originalPlay.apply(this, arguments);
      };
      proto.play = typeof exportFunction === 'function'
        ? exportFunction(remember, pageWindow)
        : remember;
    } catch (_) {
      // Without the hook the bridge simply finds no SoundCloud player.
    }
  }
  // Which way the user last scrolled the page (any scroller: the document or
  // an inner list): down shrinks the app's floating "Abrir ajustes" to an
  // arrow, up shows it in full, like YouTube's own top bar.
  if (!window.__transponoScrollWatch && typeof document.addEventListener === 'function') {
    window.__transponoScrollWatch = true;
    window.__transponoScrollDir = 'up';
    const lastTop = new WeakMap();
    document.addEventListener('scroll', event => {
      const target = event.target === document || !event.target ? document.documentElement : event.target;
      const top = target === document.documentElement
        ? (window.scrollY || document.documentElement.scrollTop || 0)
        : (target.scrollTop || 0);
      // A scroller seen for the first time starts from its top, so the
      // very first scroll already counts.
      const before = lastTop.has(target) ? lastTop.get(target) : 0;
      if (Math.abs(top - before) < 12) return;
      lastTop.set(target, top);
      const direction = top > before && top > 40 ? 'down' : 'up';
      if (direction === window.__transponoScrollDir) return;
      window.__transponoScrollDir = direction;
      // The bars slide at once and the app hears of it at once, so its own
      // buttons leave and return together with the bars (not at the next
      // periodic report).
      try {
        if (typeof syncBarsAway === 'function') syncBarsAway();
        if (typeof window.__transponoPostFocus === 'function') window.__transponoPostFocus();
      } catch (_) {}
    }, {passive: true, capture: true});
  }
  // Two-page mode, browse page: a tap on a video (a /watch link) is handed to
  // the app, which plays it in its player page; this page stays where it is
  // (the search results stay behind the mini player).
  if (!window.__transponoOpenWatch && typeof document.addEventListener === 'function') {
    window.__transponoOpenWatch = true;
    document.addEventListener('click', event => {
      if (!window.__transponoBrowseOnly || !event.target || !event.target.closest) return;
      // Shorts are not handed over: they open here, in the site's own
      // vertical player, like in the YouTube app.
      const link = event.target.closest('a[href*="/watch?"]');
      if (!link) return;
      let url;
      try { url = new URL(link.getAttribute('href'), window.location.href); } catch (_) { return; }
      if (url.pathname !== '/watch' || !url.searchParams.get('v')) return;
      event.preventDefault();
      event.stopPropagation();
      window.__transponoOpenRequest = url.href;
      window.__transponoOpenSeq = (window.__transponoOpenSeq || 0) + 1;
    }, true);
  }
  // Mini player, as in the YouTube app: drag the watch-page video DOWN and it
  // shrinks to a small video in a corner, the space it used is released so
  // the video list moves up; tapping the small video restores the full
  // player, dragging it moves it and it settles in the nearest corner. On
  // m.youtube.com the player is a fixed "sticky-player" under the top bar; it
  // keeps its size and is only scaled, so YouTube's own layout and the audio
  // graph are untouched.
  if (!soundCloud() && !window.__transponoMini) {
    window.__transponoMini = true;
    const style = document.createElement('style');
    style.id = 'transpono-mini-style';
    style.textContent = `
      html.transpono-mini #player-container-id.sticky-player {
        top: auto !important; bottom: 140px !important;
        left: auto !important; right: 10px !important;
        width: 100vw !important;
        transform: translate(var(--transpono-mini-x, 0px), var(--transpono-mini-y, 0px)) scale(.46);
        transform-origin: right bottom;
        /* Rounded corners that also clip the video layer: ~13 pt once scaled. */
        border-radius: 28px; overflow: hidden; clip-path: inset(0 round 28px);
        box-shadow: 0 12px 40px rgba(0, 0, 0, .6);
        z-index: 9999 !important;
        transition: transform .18s ease;
        /* The small video is moved with the finger: the page must not scroll
           under it. Done here, not with preventDefault, so that the touchmove
           listener can be passive and never delays the page's scrolling. */
        touch-action: none;
      }
      html.transpono-mini.transpono-mini-left #player-container-id.sticky-player {
        right: auto !important; left: 10px !important; transform-origin: left bottom;
      }
      html.transpono-mini.transpono-mini-top #player-container-id.sticky-player {
        bottom: auto !important; top: 64px !important;
      }
      html.transpono-mini.transpono-mini-top.transpono-mini-left #player-container-id.sticky-player {
        transform-origin: left top;
      }
      html.transpono-mini.transpono-mini-top:not(.transpono-mini-left) #player-container-id.sticky-player {
        transform-origin: right top;
      }
      html.transpono-mini.transpono-mini-dragging #player-container-id.sticky-player {
        transition: none;
      }
      /* The related-videos filter chips stay in the page flow while mini
         (sticky, they hung mid-screen under where the full player was). */
      html.transpono-mini ytm-related-chip-cloud-renderer,
      html.transpono-mini ytm-chip-cloud-renderer,
      html.transpono-mini *:has(> ytm-related-chip-cloud-renderer),
      html.transpono-mini *:has(> ytm-chip-cloud-renderer) {
        position: static !important; top: auto !important;
        transform: none !important;
      }
      html.transpono-mini .player-placeholder-wrapper,
      html.transpono-mini .player-placeholder {
        height: 0 !important; min-height: 0 !important;
        padding: 0 !important; overflow: hidden !important;
      }`;
    (document.head || document.documentElement).appendChild(style);
    // Flutter gives the player WebView the mini-player's actual bounds. Do
    // not scale a full-screen platform view into a small Flutter rectangle:
    // native hit testing can otherwise disagree with the visible player.
    style.textContent += `
      html.transpono-app-mini-surface,
      html.transpono-app-mini-surface body {
        width: 100% !important; height: 100% !important;
        margin: 0 !important; overflow: hidden !important;
        background: #000 !important;
      }
      html.transpono-app-mini-surface body :not(#player-container-id):not(#player-container-id *) {
        visibility: hidden !important;
      }
      html.transpono-app-mini-surface #player-container-id,
      html.transpono-app-mini-surface #player-container-id * {
        visibility: visible !important;
      }
      /* In the small window only the picture shows: YouTube's own controls
         (play, time, settings…) are hidden; the app draws pause and close. */
      html.transpono-app-mini-surface #player-container-id *:not(video):not(:has(video)) {
        visibility: hidden !important;
      }
      html.transpono-app-mini-surface #player-container-id,
      html.transpono-app-mini-surface #player-container-id.sticky-player {
        position: fixed !important;
        top: 0 !important; left: 0 !important; right: auto !important;
        bottom: auto !important;
        width: var(--transpono-app-mini-content-width) !important;
        height: var(--transpono-app-mini-content-height) !important;
        max-width: none !important;
        transform: none !important;
        transform-origin: top left !important;
        min-width: 0 !important; min-height: 0 !important;
        border-radius: 0 !important; clip-path: none !important;
        overflow: hidden !important; z-index: 2147483000 !important;
      }
      html.transpono-app-mini-surface #movie_player,
      html.transpono-app-mini-surface .html5-video-container,
      html.transpono-app-mini-surface #player-container-id video {
        width: 100% !important; height: 100% !important;
        min-width: 0 !important; min-height: 0 !important;
      }
      html.transpono-app-mini-surface #player-container-id video {
        display: block !important;
        object-fit: contain !important;
      }`;
    // Keep the YouTube player at its regular CSS size while Flutter clips and
    // scales the full-size WebView into the app's mini-player window. Resizing
    // the player itself makes YouTube enter tiny mode and pause playback.
    // The video fills the page's width; the app then scales the whole page
    // down to the small window. Measured again when the page changes size
    // (the phone was turned), or the video would keep its old width.
    const sizeAppMini = () => {
      const contentWidth = Math.max(window.innerWidth, 220);
      root.style.setProperty(
        '--transpono-app-mini-content-width', `${contentWidth}px`);
      root.style.setProperty(
        '--transpono-app-mini-content-height', `${contentWidth * 9 / 16}px`);
    };
    window.__transponoSetAppMiniSurface = visible => {
      if (visible) sizeAppMini();
      root.classList.toggle('transpono-app-mini-surface', visible);
    };
    if (typeof window.addEventListener === 'function') {
      window.addEventListener('resize', () => {
        if (root.classList.contains('transpono-app-mini-surface')) sizeAppMini();
      });
    }
    const root = document.documentElement;
    const playerOf = () => document.querySelector('#player-container-id.sticky-player');
    // m.youtube.com keeps some bars (the filter chips) sticky/fixed just under
    // the full-size player; once it shrinks they hung mid-screen over the
    // list. While mini they go back into the page flow (scrolling away with
    // it); restored after. Also re-checked while mini: YouTube adds them late.
    const lifted = [];
    const liftStickyBars = () => {
      if (typeof window.getComputedStyle !== 'function' || !document.body) return;
      const player = playerOf();
      const walker = document.createTreeWalker(document.body, 1);
      let node = walker.nextNode();
      let seen = 0;
      while (node && seen++ < 6000) {
        if (!(player && player.contains(node))) {
          const css = window.getComputedStyle(node);
          if ((css.position === 'sticky' || css.position === 'fixed') &&
              parseFloat(css.top) > 80 && !node.__transponoLifted) {
            node.__transponoLifted = true;
            lifted.push([node, node.getAttribute('style')]);
            node.style.setProperty('position', 'static', 'important');
            node.style.setProperty('top', 'auto', 'important');
          }
        }
        node = walker.nextNode();
      }
    };
    const restoreStickyBars = () => {
      while (lifted.length) {
        const [node, styleText] = lifted.pop();
        node.__transponoLifted = false;
        if (styleText === null) node.removeAttribute('style');
        else node.setAttribute('style', styleText);
      }
    };
    const setOffset = (x, y) => {
      root.style.setProperty('--transpono-mini-x', `${x}px`);
      root.style.setProperty('--transpono-mini-y', `${y}px`);
    };
    const setMini = mini => {
      if (root.classList.contains('transpono-mini') === mini) return;
      root.classList.toggle('transpono-mini', mini);
      if (mini) {
        liftStickyBars();
      } else {
        restoreStickyBars();
        setOffset(0, 0);
        root.classList.remove('transpono-mini-left', 'transpono-mini-top', 'transpono-mini-dragging');
      }
      window.scrollTo({top: 0, left: 0, behavior: 'instant'});
    };
    let dragStartY = null;
    // Moving the small video: where the finger started, and whether it moved
    // enough to be a drag rather than a tap.
    let move = null;
    let moved = false;
    document.addEventListener('touchstart', event => {
      const player = playerOf();
      const touch = event.touches[0];
      if (root.classList.contains('transpono-mini')) {
        move = player && player.contains(event.target)
          ? {x: touch.clientX, y: touch.clientY} : null;
        moved = false;
        dragStartY = null;
        return;
      }
      // Also while the studio's adjustments are open: the video shrinks the
      // same way, and the app closes the adjustments as it does.
      dragStartY = player &&
        window.location.pathname === '/watch' && player.contains(event.target)
        ? touch.clientY : null;
    }, {passive: true, capture: true});
    document.addEventListener('touchmove', event => {
      const touch = event.touches[0];
      if (move) {
        const dx = touch.clientX - move.x;
        const dy = touch.clientY - move.y;
        if (!moved && Math.hypot(dx, dy) < 10) return;
        moved = true;
        root.classList.add('transpono-mini-dragging');
        setOffset(dx, dy);
        // The page does not scroll under the finger: touch-action (style).
        return;
      }
      if (dragStartY === null) return;
      if (touch.clientY - dragStartY > 60) {
        dragStartY = null;
        if (window.__transponoAppMini) {
          window.__transponoMinimizeSeq = (window.__transponoMinimizeSeq || 0) + 1;
        }
        else setMini(true);
      }
    // Passive: a non-passive touchmove on the document makes every scroll of
    // the page wait for this script, which made scrolling feel slow.
    }, {passive: true, capture: true});
    document.addEventListener('touchend', event => {
      dragStartY = null;
      if (!move) return;
      if (moved) {
        // Settle in the corner nearest to where the finger let go.
        const touch = event.changedTouches[0];
        root.classList.toggle('transpono-mini-left', touch.clientX < window.innerWidth / 2);
        root.classList.toggle('transpono-mini-top', touch.clientY < window.innerHeight / 2);
        setOffset(0, 0);
        root.classList.remove('transpono-mini-dragging');
      }
      move = null;
    }, {passive: true, capture: true});
    // A real touch cancellation must clear the drag state. Do not treat
    // pointercancel as touchcancel: Android WebView can dispatch pointercancel
    // while the same physical gesture continues as touchmove/touchend. If we
    // clear dragStartY there, the app's minimize gesture never completes.
    const cancelTouchGesture = () => {
      dragStartY = null;
      move = null;
      moved = false;
      root.classList.remove('transpono-mini-dragging');
      setOffset(0, 0);
    };
    document.addEventListener('touchcancel', cancelTouchGesture, {
      passive: true, capture: true,
    });
    // Tapping the small video brings the full player back instead of
    // pausing it; the click that ends a drag does nothing.
    document.addEventListener('click', event => {
      if (!root.classList.contains('transpono-mini')) return;
      const player = playerOf();
      if (!player || !player.contains(event.target)) return;
      event.preventDefault();
      event.stopPropagation();
      if (moved) {
        moved = false;
        return;
      }
      setMini(false);
    }, true);
    // Leaving the watch page (search, home) drops the mini state.
    setInterval(() => {
      if (!root.classList.contains('transpono-mini')) return;
      if (!playerOf() || window.location.pathname !== '/watch') {
        setMini(false);
      } else if (!lifted.length) {
        // Only until the bar is found: walking the page is not free.
        liftStickyBars();
      }
    }, 500);
  }
  // Gecko on iOS opens the keyboard only when a text field GAINS focus. If
  // the user taps outside the page (an app button) the keyboard closes but the
  // search field keeps its focus, so tapping it again changes nothing: no
  // keyboard, and YouTube's search overlay stays over the results. Tapping a
  // field that already has focus therefore drops and retakes the focus, which
  // makes Gecko ask for the keyboard again.
  if (!window.__transponoRefocus) {
    window.__transponoRefocus = true;
    document.addEventListener('touchend', event => {
      const target = event.target;
      const field = target && target.closest &&
        target.closest('input, textarea, [contenteditable="true"]');
      if (!field || field !== document.activeElement) return;
      field.blur();
      setTimeout(() => field.focus(), 0);
    }, true);
  }
  // A video that starts without a tap (chosen in the other page, next in a
  // playlist, autoplay) is started muted by YouTube, with its "Toque para
  // ativar o som" button. On the player page the app gives it its sound at
  // once, the same way the 'unmute' command does, so the button never stays.
  // Only where the app asks for it: on iPhone the native audio copy mutes the
  // page's video on purpose.
  if (!window.__transponoAutoSoundInstalled) {
    window.__transponoAutoSoundInstalled = true;
    let lastTry = 0;
    const giveSound = () => {
      if (window.__transponoAutoSound !== true) return;
      if (window.location.pathname !== '/watch') return;
      const video = document.querySelector('video.html5-main-video');
      if (!video || video.paused || !(video.muted || video.volume === 0)) return;
      const t = Date.now();
      if (t - lastTry < 300) return;
      lastTry = t;
      const element = document.getElementById('movie_player');
      const player = element && (element.wrappedJSObject || element);
      try {
        if (player && typeof player.unMute === 'function') {
          player.unMute();
          if (typeof player.getVolume === 'function' && player.getVolume() === 0 &&
              typeof player.setVolume === 'function') player.setVolume(100);
        }
      } catch (_) {}
      video.muted = false;
      if (video.volume === 0) video.volume = 1;
      const control = document.querySelector('.ytp-unmute');
      if (control && typeof control.click === 'function') control.click();
    };
    for (const name of ['playing', 'volumechange', 'loadeddata']) {
      document.addEventListener(name, giveSound, true);
    }
    setInterval(giveSound, 500);
  }
  // WebView can reinject after an SPA navigation. Reuse MediaElementAudioSource
  // ownership: creating a second source for the same element is not supported.
  if (window.TransponoMedia && window.TransponoMedia._activate) {
    window.TransponoMedia._activate();
    return;
  }

  const graphs = new WeakMap();
  const preparing = new WeakMap();
  const allGraphs = new Set();
  // Enabled only by the isolated generated-tone integration fixture.
  const probeEnabled = window.__transponoAudioProbe === true;
  const minLoopSeconds = 0.25;
  let audioContext = null;
  let video = null;
  let videoId = null;
  let pitch = 0;
  let speed = 1;
  let bass = 0;
  let mid = 0;
  let treble = 0;
  let gain = 0;
  let chorus = 0;
  let feedback = 0;
  let delay = 0;
  let reverb = 0;
  let reverbImpulse = null;
  let effectsEpoch = 0;
  let restoringEffectsEpoch = -1;
  const effectIntents = new Map();
  const keyDetector = window.TransponoKeyDetector
    ? new window.TransponoKeyDetector.KeyDetector() : null;
  let keyCapture = null;
  let keyPreparing = false;
  let keyLastAttempt = -Infinity;
  let keyLastSample = -Infinity;
  let keyRoot = null;
  let keyMode = '';
  let keyStatus = 'waiting';
  let pitchStatus = 'idle';
  let pitchMessage = '';
  let loopA = null;
  let loopB = null;
  let loopWanted = false;
  // Completion is an observation, not a seek command acknowledgement. Keep the
  // counter monotonic and change epoch whenever its playback context changes.
  let loopCount = 0;
  let loopEpoch = 0;
  let cycleArmed = false;
  let pendingLoopReturn = null;
  let loopEventElement = null;
  let loopEventHandlers = null;
  let observedSource = '';
  let isAd = false;
  // The current element's source was judged unusable for pitch (see refresh).
  let sourceBlocked = false;
  let revision = 0;
  let timer = null;
  let disposed = false;
  let lastPosted = '';
  let snapshotRevision = 0;
  let timelineSeekEpoch = 0;
  let timelineRateEpoch = 0;
  let timelineSourceEpoch = 0;
  let transportRevision = 0;
  let playbackIntent = null;
  let pitchCommandIntent = null;
  let activeDispatchId = null;
  const commandResults = new Map();
  const maxCommandResults = 64;

  const finite = (value, fallback = 0) => Number.isFinite(value) ? value : fallback;
  const decibelGain = value => Math.pow(10, value / 20);
  function setEffectParam(parameter, value, smooth = false) {
    const time = audioContext.currentTime;
    parameter.cancelScheduledValues(time);
    if (smooth) parameter.setTargetAtTime(value, time, 0.015);
    else parameter.setValueAtTime(value, time);
  }
  const now = () => performance.now();
  const durationOf = (element) => Math.max(0, finite(element && element.duration));
  const positionOf = (element) => Math.max(0, finite(element && element.currentTime));
  const sourceOf = (element) => element ? element.currentSrc || element.src || '' : '';
  // A YouTube video element that left the page is gone; SoundCloud's player
  // element is never in the page, so it is gone only once replaced.
  const gone = (element) => soundCloud()
    ? element !== window.__transponoPlaying
    : element.isConnected === false;
  const playbackReady = () => !!video && !disposed && !isAd && !video.ended &&
    video.readyState >= 3 && !video.seeking;
  const nearLoopStart = () => loopA !== null && loopB !== null &&
    Math.abs(positionOf(video) - loopA) <= Math.min(0.1, (loopB - loopA) / 4);
  const selectedId = () => {
    if (soundCloud()) {
      // The player keeps going across pages: identify the track itself.
      const playing = window.__transponoPlaying;
      const meta = navigator.mediaSession && navigator.mediaSession.metadata;
      if (!playing || !meta || !meta.title) return null;
      const name = `${meta.title}|${meta.artist || ''}`;
      let hash = 0;
      for (let i = 0; i < name.length; i++) hash = (hash * 31 + name.charCodeAt(i)) | 0;
      return `soundcloud-${(hash >>> 0).toString(36)}`;
    }
    const url = new URL(window.location.href);
    if (url.pathname === '/watch') return url.searchParams.get('v');
    const match = url.pathname.match(/^\/(?:shorts|live|embed)\/([^/?]+)/);
    return match ? match[1] : null;
  };
  const title = () => {
    // YouTube Music sets Media Session metadata ("Song" + "Artist"); the
    // chord search wants both, like a YouTube "Song - Artist" title.
    const session = navigator.mediaSession && navigator.mediaSession.metadata;
    const sessionTitle = session && session.title
      ? (session.artist ? `${session.title} - ${session.artist}` : session.title)
      : '';
    // YouTube Music's player bar: song title plus the first part of the
    // byline ("Artist • Album • Year"). Read before Media Session, which
    // carries the advert's name while one plays.
    const musicBar = (() => {
      if (!/(^|\.)music\.youtube\.com$/i.test(window.location.hostname)) return '';
      const song = document.querySelector('ytmusic-player-bar .title')?.textContent?.trim() || '';
      const artist = (document.querySelector('ytmusic-player-bar .byline')?.textContent || '')
        .split('•')[0].trim();
      return song ? (artist ? `${song} - ${artist}` : song) : '';
    })();
    const candidates = [
      musicBar,
      /(^|\.)(music\.youtube|soundcloud)\.com$/i.test(window.location.hostname) && !isAd
        ? sessionTitle : '',
      // m.youtube.com now shows the title in an h2 "ytVideoMetadataViewModelTitle";
      // after a page change document.title stays "YouTube" and og:title is gone.
      document.querySelector('.ytVideoMetadataViewModelTitle, h1.ytd-watch-metadata, .slim-video-information-title, .slim-video-metadata-title, h1.title')?.textContent,
      document.querySelector('meta[property="og:title"]')?.getAttribute('content'),
      document.querySelector('meta[name="title"]')?.getAttribute('content'),
      document.title,
    ];
    for (const candidate of candidates) {
      const value = (candidate || '').replace(/\s*[-–|]\s*YouTube(?: Music)?\s*$/i, '').trim();
      if (value && !/^(?:youtube(?: music)?|vídeo do youtube)$/i.test(value)) return value;
    }
    return '';
  };

  function timeout(promise, milliseconds, message) {
    let timeoutId;
    return Promise.race([
      Promise.resolve(promise),
      new Promise((_, reject) => {
        timeoutId = setTimeout(() => reject(new Error(message)), milliseconds);
      }),
    ]).finally(() => clearTimeout(timeoutId));
  }

  function setGain(node, value) {
    node.gain.cancelScheduledValues(audioContext.currentTime);
    node.gain.setValueAtTime(value, audioContext.currentTime);
  }

  function dry(graph, stopProcessing = false) {
    if (!graph) return;
    // These switches share the audio-context timestamp: never sum two copies.
    setGain(graph.wet, 0);
    setGain(graph.dry, 1);
    graph.audible = false;
    if (stopProcessing) {
      graph.acknowledged = false;
      if (graph.dspConnected && graph.stretch) {
        graph.input.disconnect(graph.stretch);
        graph.stretch.disconnect();
        graph.output.disconnect();
        graph.dspConnected = false;
      }
      try {
        if (graph.stretch) Promise.resolve(graph.stretch.schedule({active: false})).catch(() => {});
      } catch (_) {
        // A dead processor must never prevent the dry route from being restored.
      }
    }
  }

  function wet(graph) {
    setGain(graph.dry, 0);
    setGain(graph.wet, 1);
    graph.audible = true;
  }

  function impulseResponse() {
    if (reverbImpulse) return reverbImpulse;
    const length = Math.floor(audioContext.sampleRate * 1.15);
    const buffer = audioContext.createBuffer(2, length, audioContext.sampleRate);
    // A short, decaying stereo impulse keeps the reverb local to the page.
    let seed = 2179;
    for (let channel = 0; channel < 2; channel++) {
      const data = buffer.getChannelData(channel);
      for (let i = 0; i < length; i++) {
        seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
        const envelope = Math.pow(1 - i / length, 3);
        data[i] = (seed / 2147483648 - 1) * envelope;
      }
    }
    reverbImpulse = buffer;
    return buffer;
  }

  function connectEffects(graph) {
    graph.low.connect(graph.mid).connect(graph.high).connect(graph.master);
    if (graph.probeFinal) graph.master.connect(graph.probeFinal).connect(audioContext.destination);
    else graph.master.connect(audioContext.destination);
    graph.high.connect(graph.echoDelay);
    graph.echoDelay.connect(graph.echoGain).connect(graph.master);
    graph.echoDelay.connect(graph.feedbackGain).connect(graph.echoDelay);
    graph.high.connect(graph.chorusDelay).connect(graph.chorusGain).connect(graph.master);
    graph.chorusLfo.connect(graph.chorusDepth).connect(graph.chorusDelay.delayTime);
    graph.high.connect(graph.convolver).connect(graph.reverbGain).connect(graph.master);
  }

  function retire(graph) {
    if (!graph || graph.retired) return;
    dry(graph, true);
    graph.source.disconnect();
    graph.input.disconnect();
    graph.keyAnalyser.disconnect();
    graph.dry.disconnect();
    graph.wet.disconnect();
    graph.low.disconnect();
    graph.mid.disconnect();
    graph.high.disconnect();
    graph.master.disconnect();
    if (graph.probeFinal) graph.probeFinal.disconnect();
    graph.echoDelay.disconnect();
    graph.echoGain.disconnect();
    graph.feedbackGain.disconnect();
    graph.chorusDelay.disconnect();
    graph.chorusGain.disconnect();
    graph.chorusLfo.disconnect();
    if (graph.lfoStarted) graph.chorusLfo.stop();
    graph.lfoStarted = false;
    graph.chorusDepth.disconnect();
    graph.convolver.disconnect();
    graph.reverbGain.disconnect();
    graph.retired = true;
    allGraphs.delete(graph);
  }

  function revive(graph) {
    if (!graph || !graph.retired) return;
    graph.chorusLfo = audioContext.createOscillator();
    graph.chorusLfo.frequency.value = 0.8;
    graph.input.connect(graph.keyAnalyser).connect(graph.dry).connect(graph.low);
    graph.wet.connect(graph.low);
    connectEffects(graph);
    graph.source.connect(graph.input);
    graph.chorusLfo.start();
    graph.lfoStarted = true;
    graph.retired = false;
    allGraphs.add(graph);
  }

  function preservesPitch(element) {
    if ('preservesPitch' in element) element.preservesPitch = true;
    else if ('webkitPreservesPitch' in element) element.webkitPreservesPitch = true;
    else if ('mozPreservesPitch' in element) element.mozPreservesPitch = true;
    else return false;
    return true;
  }

  function safeSource(element) {
    if (element.mediaKeys) return false;
    try {
      const source = new URL(element.currentSrc || element.src, window.location.href);
      return source.protocol === 'blob:' && source.origin === window.location.origin;
    } catch (_) {
      return false;
    }
  }

  function stopKeyCapture() {
    if (!keyCapture) return;
    keyCapture.source.disconnect();
    keyCapture.analyser.disconnect();
    keyCapture.silent.disconnect();
    keyCapture.stream.getTracks().forEach(track => track.stop());
    keyCapture = null;
  }

  function resetKeyDetection() {
    stopKeyCapture();
    if (keyDetector) keyDetector.reset();
    keyRoot = null;
    keyMode = '';
    keyStatus = 'waiting';
    keyLastAttempt = -Infinity;
    keyLastSample = -Infinity;
  }

  async function startKeyCapture(element) {
    const capture = element.captureStream || element.mozCaptureStream;
    if (!capture) throw new Error('Captura de áudio indisponível.');
    const stream = capture.call(element);
    const track = stream.getAudioTracks()[0];
    if (!track) {
      stream.getTracks().forEach(item => item.stop());
      throw new Error('O vídeo ainda não tem uma faixa de áudio acessível.');
    }
    try {
      const Context = window.AudioContext || window.webkitAudioContext;
      if (!Context) throw new Error('Análise de áudio indisponível.');
      if (!audioContext) audioContext = new Context({latencyHint: 'interactive'});
      await timeout(audioContext.resume(), 4000, 'Áudio ainda não iniciado.');
      if (element !== video || disposed || isAd) throw new Error('O vídeo mudou.');
      const source = audioContext.createMediaStreamSource(stream);
      const analyser = audioContext.createAnalyser();
      analyser.fftSize = 16384;
      analyser.smoothingTimeConstant = 0.7;
      const silent = audioContext.createGain();
      silent.gain.value = 0;
      source.connect(analyser).connect(silent).connect(audioContext.destination);
      keyCapture = {
        element, source, analyser, silent, stream, track,
        spectrum: new Float32Array(analyser.frequencyBinCount), startedAt: now(),
      };
      keyStatus = 'analyzing';
    } catch (error) {
      stream.getTracks().forEach(item => item.stop());
      throw error;
    }
  }

  function updateKeyDetection() {
    if (!keyDetector || !video || isAd || disposed) return;
    if (video.paused || video.ended || video.readyState < 3) return;
    if (keyCapture && (keyCapture.element !== video || keyCapture.track.readyState !== 'live')) {
      stopKeyCapture();
      keyLastAttempt = -Infinity;
    }
    if (!keyCapture && !keyPreparing && now() - keyLastAttempt > 3000) {
      const element = video;
      keyPreparing = true;
      keyLastAttempt = now();
      void startKeyCapture(element).catch(() => {
        if (element === video && !isAd) keyStatus = 'unavailable';
      }).finally(() => { keyPreparing = false; });
      return;
    }
    const graph = graphs.get(video);
    const analyser = keyCapture ? keyCapture.analyser : graph && graph.keyAnalyser;
    const spectrum = keyCapture ? keyCapture.spectrum : graph && graph.keySpectrum;
    if (!analyser || !spectrum || !audioContext || audioContext.state !== 'running') return;
    if (keyCapture && keyCapture.track.muted) {
      if (now() - keyCapture.startedAt > 4000) keyStatus = 'unavailable';
      return;
    }
    if (now() - keyLastSample < 330) return;
    keyLastSample = now();
    analyser.getFloatFrequencyData(spectrum);
    const result = keyDetector.observeSpectrum(spectrum, audioContext.sampleRate, analyser.fftSize);
    if (result) {
      keyRoot = result.root;
      keyMode = result.mode;
      keyStatus = 'ready';
    } else if (keyDetector.frames > 75) {
      keyStatus = 'indeterminate';
    } else {
      keyStatus = 'analyzing';
    }
  }

  function requireSound(element) {
    if (element.muted || element.volume === 0) {
      const error = new Error('Ative o som do vídeo e tente alterar o tom novamente.');
      error.code = 'sound-muted';
      throw error;
    }
  }

  function unavailable(message, element = video) {
    dry(element && graphs.get(element), true);
    pitch = 0;
    pitchStatus = 'unavailable';
    pitchMessage = message;
  }

  function invalidateLoopObservation() {
    loopEpoch += 1;
    discardLoopReturn();
  }

  function discardLoopReturn() {
    cycleArmed = false;
    pendingLoopReturn = null;
  }

  function invalidatePlaybackIntent() {
    transportRevision += 1;
    playbackIntent = null;
  }

  function currentPlaybackIntent(intent) {
    return intent && playbackIntent === intent && intent.revision === transportRevision &&
      !disposed && allowedPage() && video === intent.element && videoId === intent.videoId &&
      sourceOf(video) === intent.source && isAd === intent.isAd;
  }

  async function playCurrentVideo() {
    const intent = {
      revision: ++transportRevision, element: video, videoId,
      source: sourceOf(video), isAd, commandId: activeDispatchId,
    };
    playbackIntent = intent;
    if (audioContext) {
      await timeout(audioContext.resume(), 4000, 'Toque no vídeo para ativar o áudio.');
    }
    // The page can replace its source while AudioContext.resume is pending,
    // including when background timers are throttled. Re-read it before play.
    refresh();
    if (!currentPlaybackIntent(intent)) return;
    await intent.element.play();
    refresh();
    if (!currentPlaybackIntent(intent)) {
      // A cancelled old Play cannot resurrect playback, but it must not stop a
      // newer explicit Play for this same element/context when its promise ends.
      if (!(currentPlaybackIntent(playbackIntent) &&
          playbackIntent.element === intent.element)) intent.element.pause();
    }
  }

  function armCycleAtStart() {
    if (loopWanted && !pendingLoopReturn && playbackReady() &&
        !video.paused && nearLoopStart()) cycleArmed = true;
  }

  function validLoopReturn(pending) {
    return pending && pending.element === video && pending.epoch === loopEpoch &&
      pending.videoId === videoId && pending.source === sourceOf(video) &&
      loopWanted && !disposed && !isAd && pending.a === loopA && pending.b === loopB;
  }

  function bindLoopEvents(element) {
    if (loopEventElement === element) return;
    if (loopEventHandlers) {
      for (const [name, handler] of Object.entries(loopEventHandlers)) {
        loopEventElement.removeEventListener(name, handler);
      }
    }
    loopEventElement = null;
    loopEventHandlers = null;
    if (!element || typeof element.addEventListener !== 'function' ||
        typeof element.removeEventListener !== 'function') return;
    loopEventElement = element;
    loopEventHandlers = {
      seeking() {
        if (element !== video || disposed) return;
        timelineSeekEpoch += 1;
        refresh();
        const pending = pendingLoopReturn;
        // currentTime is changed synchronously, but seeking/seeked are queued.
        // Only the first seek to our exact A target belongs to this return.
        if (validLoopReturn(pending) && !pending.sawSeeking && nearLoopStart()) {
          pending.sawSeeking = true;
        } else {
          invalidateLoopObservation();
          if (loopWanted && (positionOf(video) < loopA || positionOf(video) >= loopB)) {
            loopWanted = false;
          }
        }
        post();
      },
      seeked() {
        if (element !== video || disposed) return;
        refresh();
        const pending = pendingLoopReturn;
        const confirmed = validLoopReturn(pending) && pending.sawSeeking &&
          playbackReady() && !video.paused && nearLoopStart();
        pendingLoopReturn = null;
        if (confirmed && pending.eligible) loopCount += 1;
        // An external seek to A can start a new full pass, but cannot finish one.
        cycleArmed = loopWanted && playbackReady() && !video.paused && nearLoopStart();
        post();
      },
      play() {
        if (element !== video || disposed) return;
        refresh();
        // A paused seek to A must arm before the first 200 ms poll, which can
        // already be beyond the start tolerance even at 0.6x speed.
        armCycleAtStart();
        post();
      },
      playing() {
        if (element !== video || disposed) return;
        refresh();
        // play can precede HAVE_FUTURE_DATA. The readiness event also covers
        // buffering recovery at A, without arming a partial pass in the middle.
        armCycleAtStart();
        post();
      },
      pause() {
        if (element !== video || disposed) return;
        // Native YouTube controls can pause without going through our command
        // bridge. Ignore an already-stale queued pause event after a newer Play.
        if (element.paused) invalidatePlaybackIntent();
        // A normal pause halfway through a pass preserves progress. Pausing a
        // return before confirmation must never add a completed repetition.
        if (pendingLoopReturn) discardLoopReturn();
        post();
      },
      emptied() {
        if (element !== video || disposed) return;
        invalidateLoopObservation();
        post();
      },
      ratechange() {
        if (element !== video || disposed) return;
        timelineRateEpoch += 1;
        post();
      },
    };
    for (const [name, handler] of Object.entries(loopEventHandlers)) {
      element.addEventListener(name, handler);
    }
  }

  function returnLoopToStart() {
    const pending = {
      element: video, videoId, source: sourceOf(video), epoch: loopEpoch,
      a: loopA, b: loopB, eligible: cycleArmed, sawSeeking: false, startedAt: now(),
    };
    cycleArmed = false;
    pendingLoopReturn = pending;
    try {
      video.currentTime = loopA;
    } catch (_) {
      invalidateLoopObservation();
    }
  }

  function resetPractice(previous) {
    effectsEpoch += 1;
    revision += 1;
    invalidatePlaybackIntent();
    invalidateLoopObservation();
    dry(previous && graphs.get(previous), true);
    if (previous) previous.playbackRate = 1;
    pitch = 0;
    speed = 1;
    bass = 0;
    mid = 0;
    treble = 0;
    gain = 0;
    chorus = 0;
    feedback = 0;
    delay = 0;
    reverb = 0;
    resetKeyDetection();
    const graph = previous && graphs.get(previous);
    if (graph) {
      setEffectParam(graph.low.gain, 0);
      setEffectParam(graph.mid.gain, 0);
      setEffectParam(graph.high.gain, 0);
      setEffectParam(graph.master.gain, 1);
      setEffectParam(graph.echoGain.gain, 0);
      setEffectParam(graph.feedbackGain.gain, 0);
      setEffectParam(graph.chorusGain.gain, 0);
      setEffectParam(graph.reverbGain.gain, 0);
    }
    pitchStatus = 'idle';
    pitchMessage = '';
    sourceBlocked = false;
    loopA = null;
    loopB = null;
    loopWanted = false;
  }

  function refresh() {
    if (disposed || !allowedPage()) return;
    const id = selectedId();
    const next = !id
      ? null
      : soundCloud()
      ? window.__transponoPlaying || null
      : document.querySelector('video.html5-main-video') || document.querySelector('video');
    if (id !== videoId) {
      timelineSourceEpoch += 1;
      resetPractice(video);
      videoId = id;
    }
    if (next !== video) {
      timelineSourceEpoch += 1;
      effectsEpoch += 1;
      resetKeyDetection();
      invalidatePlaybackIntent();
      dry(video && graphs.get(video), true);
      if (video && gone(video)) retire(graphs.get(video));
      video = next;
      invalidateLoopObservation();
      bindLoopEvents(video);
      revive(video && graphs.get(video));
      revision += 1;
      if (pitch !== 0) {
        pitchStatus = 'idle';
        pitchMessage = 'O vídeo mudou. Aplique o tom novamente.';
      }
    }
    const nextSource = sourceOf(video);
    if (nextSource !== observedSource) {
      timelineSourceEpoch += 1;
      effectsEpoch += 1;
      observedSource = nextSource;
      invalidatePlaybackIntent();
      invalidateLoopObservation();
    }
    for (const graph of allGraphs) {
      if (graph.element !== video && gone(graph.element)) retire(graph);
    }
    const nextAd = !!document.querySelector('.ad-showing, .ad-interrupting');
    if (nextAd !== isAd) {
      effectsEpoch += 1;
      isAd = nextAd;
      invalidatePlaybackIntent();
      invalidateLoopObservation();
      revision += 1;
      dry(video && graphs.get(video), true);
      const currentGraph = video && graphs.get(video);
      if (currentGraph) {
        setEffectParam(currentGraph.low.gain, isAd ? 0 : bass);
        setEffectParam(currentGraph.mid.gain, isAd ? 0 : mid);
        setEffectParam(currentGraph.high.gain, isAd ? 0 : treble);
        setEffectParam(currentGraph.master.gain, isAd ? 1 : decibelGain(gain));
        setEffectParam(currentGraph.echoGain.gain, isAd ? 0 : delay);
        setEffectParam(currentGraph.feedbackGain.gain, isAd ? 0 : feedback);
        setEffectParam(currentGraph.chorusGain.gain, isAd ? 0 : chorus);
        setEffectParam(currentGraph.reverbGain.gain, isAd ? 0 : reverb);
      }
      if (isAd) {
        if (video) video.playbackRate = 1;
        pitchStatus = 'idle';
        pitchMessage = 'Os controles de prática retomam depois do anúncio.';
      } else if (video) {
        if (preservesPitch(video)) video.playbackRate = speed;
        pitchMessage = '';
        if (pitch !== 0) void applyPitch();
      }
    }
    const graph = video && graphs.get(video);
    // While YouTube swaps the next video into the same element its source is
    // briefly empty or not yet the page's own media stream. Treating that
    // moment as "this video cannot be pitched" left pitchStatus stuck at
    // 'unavailable' for every later video once pitch had been used ("Tom
    // indisponível nesta fonte" until the app was reopened). Judge only a
    // settled source, and clear the block when a usable source returns.
    if (graph && sourceOf(video) && video.readyState >= 1 && !safeSource(video)) {
      if (!sourceBlocked) {
        sourceBlocked = true;
        unavailable('Este vídeo não permite alterar o tom. Reabra o vídeo se o áudio não voltar.');
      }
    } else if (sourceBlocked && video && safeSource(video)) {
      sourceBlocked = false;
      if (pitchStatus === 'unavailable') {
        pitchStatus = 'idle';
        pitchMessage = '';
        revision += 1;
      }
    }
    restoreEffects();
    const duration = durationOf(video);
    if (!isAd && loopB !== null && (duration === 0 || loopB > duration)) {
      loopB = null;
      loopWanted = false;
      invalidateLoopObservation();
    }
  }

  function desiredEffects() {
    return {bass, mid, treble, gain, chorus, feedback, delay, reverb};
  }

  function effectNodes(graph) {
    return {bass: graph.low.gain, mid: graph.mid.gain, treble: graph.high.gain,
      gain: graph.master.gain, chorus: graph.chorusGain.gain,
      feedback: graph.feedbackGain.gain, delay: graph.echoGain.gain,
      reverb: graph.reverbGain.gain};
  }

  function validEffectsContext(epoch, element, id, source) {
    return !disposed && !isAd && effectsEpoch === epoch && video === element &&
      videoId === id && sourceOf(element) === source && safeSource(element);
  }

  function restoreEffects() {
    if (!video || disposed || isAd || !safeSource(video)) return;
    const graph = graphs.get(video);
    if (graph?.effectsFailed || graph?.effectsEpoch === effectsEpoch) return;
    if (!graph && !Object.values(desiredEffects()).some(value => value !== 0)) return;
    if (graph && !graph.retired) {
      const nodes = effectNodes(graph);
      for (const [action, value] of Object.entries(desiredEffects())) {
        setEffectParam(nodes[action], action === 'gain' ? decibelGain(value) : value);
      }
      graph.effectsEpoch = effectsEpoch;
      return;
    }
    if (video.muted || video.volume === 0 || restoringEffectsEpoch === effectsEpoch) return;
    const epoch = effectsEpoch, element = video, id = videoId, source = sourceOf(video);
    restoringEffectsEpoch = epoch;
    void prepareGraph(element, false).then(restored => {
      if (!validEffectsContext(epoch, element, id, source) || restored.effectsFailed) return;
      // Values may have changed while preparation awaited AudioContext.resume.
      restored.effectsEpoch = -1;
      restoreEffects();
      post();
    }).catch(() => {
      // Keep the native route; a new context or explicit adjustment can retry.
      // Snapshots report zero until there is an applicable processing graph.
    });
  }

  function appliedEffects(graph) {
    const values = {bass: 0, mid: 0, treble: 0, gain: 0,
      chorus: 0, feedback: 0, delay: 0, reverb: 0};
    if (!graph || graph.effectsFailed || graph.retired || disposed || isAd ||
        graph.effectsEpoch !== effectsEpoch || !safeSource(video)) return values;
    const nodes = effectNodes(graph);
    for (const action of Object.keys(values)) {
      const value = nodes[action].value;
      values[action] = action === 'gain' ? 20 * Math.log10(value) : value;
    }
    return values;
  }

  function snapshot() {
    refresh();
    const graph = video && graphs.get(video);
    const sampleTimeMs = now();
    const mediaPosition = positionOf(video);
    return {
      snapshotRevision: ++snapshotRevision,
      sampleTimeMs,
      timelineSeekEpoch,
      timelineRateEpoch,
      timelineSourceEpoch,
      videoId,
      title: video ? title() : '',
      // A text field (the search bar) has the focus: the app hides its
      // floating start-screen button meanwhile.
      inputFocused: (() => {
        const field = document.activeElement;
        return !!field && !!field.matches &&
          field.matches('input, textarea, [contenteditable="true"]');
      })(),
      pageScroll: window.__transponoScrollDir === 'down' ? 'down' : 'up',
      bars: pageBars() || musicBars(),
      // The site's vertical Shorts player is on screen.
      shortsPage: /^\/shorts(\/|$)/.test(window.location.pathname),
      // Counters, not one-shot flags: any snapshot (there are several
      // callers) may read them; the app acts on each new number once.
      minimizeSeq: window.__transponoMinimizeSeq || 0,
      homeSeq: window.__transponoHomeSeq || 0,
      openSeq: window.__transponoOpenSeq || 0,
      openRequest: typeof window.__transponoOpenRequest === 'string'
        ? window.__transponoOpenRequest : '',
      hasVideo: !!video && !disposed,
      playing: !!video && !video.paused && !video.ended && !disposed,
      seeking: !!video && video.seeking,
      muted: !!video && (video.muted || video.volume === 0),
      position: mediaPosition,
      duration: durationOf(video),
      speed: video && !isAd ? finite(video.playbackRate, speed) : speed,
      // During a live pitch change, keep showing the tone still audible on
      // the processed route instead of briefly reporting the original tone.
      pitch: graph && graph.audible ? graph.appliedPitch : 0,
      pendingPitch: pitchStatus === 'loading' ? pitch : null,
      pitchStatus,
      pitchMessage,
      audioEffects: appliedEffects(graph),
      keyRoot,
      keyMode,
      keyStatus: keyDetector ? keyStatus : 'unavailable',
      loopA,
      loopB,
      loopEnabled: loopWanted && !isAd && !disposed,
      loopCount,
      loopEpoch,
      loopEventsSupported: !!video && loopEventElement === video &&
        durationOf(video) > 0 && !disposed &&
        // At EOF the page can pause/navigate before the 200 ms loop poll. Do
        // not offer automatic progression where completion is not reliable.
        (loopB === null || loopB < durationOf(video)),
      playbackReady: playbackReady(),
      isAd,
      ...(probeEnabled ? {probe: probeSnapshot()} : {}),
    };
  }

  // Report focus changes at once (the start-screen button hides while the
  // search bar has the focus). The page script can be injected again, so
  // the listeners always call the latest post().
  window.__transponoPostFocus = () => post();
  if (!window.__transponoFocusListen) {
    window.__transponoFocusListen = true;
    const report = () => setTimeout(() => {
      if (typeof window.__transponoPostFocus === 'function') window.__transponoPostFocus();
    }, 0);
    document.addEventListener('focusin', report, true);
    document.addEventListener('focusout', report, true);
  }

  function post() {
    const json = JSON.stringify(snapshot());
    if (json === lastPosted) return;
    lastPosted = json;
    if (window.TransponoBridge && typeof window.TransponoBridge.postMessage === 'function') {
      window.TransponoBridge.postMessage(json);
    }
  }

  async function prepareGraph(element, needsPitch = true) {
    if (graphs.has(element)) {
      const graph = graphs.get(element);
      revive(graph);
      if (needsPitch && !graph.stretch) await attachStretch(graph);
      return graph;
    }
    if (preparing.has(element)) {
      const graph = await preparing.get(element);
      if (needsPitch && !graph.stretch) await attachStretch(graph);
      return graph;
    }
    const id = videoId;
    const pending = (async () => {
      if (!safeSource(element)) throw new Error('Este vídeo não disponibiliza áudio para alterar o tom neste dispositivo.');
      const Context = window.AudioContext || window.webkitAudioContext;
      if (!Context) throw new Error('O equalizador não está disponível neste navegador.');
      if (!audioContext) audioContext = new Context({latencyHint: 'interactive'});
      await timeout(audioContext.resume(), 4000, 'Toque no vídeo para ativar o áudio e tente novamente.');
      let stretch;
      let connected = false;
      try {
        if (needsPitch) {
          // Worklet/WASM/CSP failure must precede MediaElementAudioSource ownership.
          stretch = await createStretchNode();
          await timeout(stretch.schedule({active: true, semitones: pitch}), 4000,
            'O processador de tom não respondeu.');
        }
        if (disposed || video !== element || videoId !== id || isAd || (needsPitch && pitch === 0))
          throw new Error('A seleção de vídeo mudou. Tente novamente.');
        if (!safeSource(element)) throw new Error('Esta fonte de áudio não permite alterar o tom.');
        requireSound(element);
        const input = audioContext.createAnalyser();
        const output = audioContext.createAnalyser();
        const keyAnalyser = audioContext.createAnalyser();
        keyAnalyser.fftSize = 16384;
        keyAnalyser.smoothingTimeConstant = 0.7;
        input.fftSize = output.fftSize = probeEnabled ? 8192 : 512;
        if (probeEnabled) input.smoothingTimeConstant = output.smoothingTimeConstant = 0;
        const dryGain = audioContext.createGain();
        const wetGain = audioContext.createGain();
        const low = audioContext.createBiquadFilter();
        low.type = 'lowshelf';
        low.frequency.value = 200;
        low.gain.value = bass;
        const high = audioContext.createBiquadFilter();
        high.type = 'highshelf';
        high.frequency.value = 3000;
        high.gain.value = treble;
        const midFilter = audioContext.createBiquadFilter();
        midFilter.type = 'peaking';
        midFilter.frequency.value = 1000;
        midFilter.Q.value = 0.8;
        midFilter.gain.value = mid;
        const echoDelay = audioContext.createDelay(0.6);
        echoDelay.delayTime.value = 0.28;
        const echoGain = audioContext.createGain();
        echoGain.gain.value = delay;
        const feedbackGain = audioContext.createGain();
        feedbackGain.gain.value = feedback;
        const chorusDelay = audioContext.createDelay(0.05);
        chorusDelay.delayTime.value = 0.018;
        const chorusGain = audioContext.createGain();
        chorusGain.gain.value = chorus;
        const chorusLfo = audioContext.createOscillator();
        chorusLfo.frequency.value = 0.8;
        const chorusDepth = audioContext.createGain();
        chorusDepth.gain.value = 0.004;
        const convolver = audioContext.createConvolver();
        convolver.buffer = impulseResponse();
        const reverbGain = audioContext.createGain();
        reverbGain.gain.value = reverb;
        const master = audioContext.createGain();
        master.gain.value = decibelGain(gain);
        // Test-only observation of the actual mixed output, including bypass/EQ.
        const probeFinal = probeEnabled ? audioContext.createAnalyser() : null;
        if (probeFinal) {
          probeFinal.fftSize = 8192;
          probeFinal.smoothingTimeConstant = 0;
        }
        dryGain.gain.value = 1;
        wetGain.gain.value = 0;
        input.connect(keyAnalyser).connect(dryGain).connect(low);
        // EQ/effects may create this graph before pitch is first requested.
        // Keep its wet output wired even when the processor is attached later.
        wetGain.connect(low);
        if (stretch) input.connect(stretch).connect(output).connect(wetGain);
        // Last irreversible operation, after the entire output graph is ready.
        const source = audioContext.createMediaElementSource(element);
        const graph = {
          element, source, input, output, keyAnalyser, probeFinal,
          keySpectrum: new Float32Array(keyAnalyser.frequencyBinCount),
          stretch, dry: dryGain, wet: wetGain,
          low, mid: midFilter, high, master, echoDelay, echoGain, feedbackGain,
          chorusDelay, chorusGain, chorusLfo, chorusDepth, convolver, reverbGain,
          retired: false, lfoStarted: false,
          samples: new Float32Array(512), audible: false, failed: false, dspConnected: !!stretch,
          appliedPitch: pitch, acknowledged: false, silentSince: null,
          effectsEpoch, effectsFailed: false,
          ...(probeEnabled ? {
            probeSpectrum: new Float32Array(4096), probeWave: new Float32Array(8192),
          } : {}),
        };
        graphs.set(element, graph);
        allGraphs.add(graph);
        try {
          connectEffects(graph);
          source.connect(input);
          chorusLfo.start();
          graph.lfoStarted = true;
        } catch (error) {
          source.disconnect();
          source.connect(audioContext.destination);
          graph.failed = true;
          graph.effectsFailed = true;
          throw error;
        }
        connected = true;
        if (stretch) listenForProcessorError(graph);
        return graph;
      } finally {
        if (!connected && stretch) stretch.disconnect();
      }
    })();
    preparing.set(element, pending);
    try {
      return await pending;
    } finally {
      preparing.delete(element);
    }
  }

  async function createStretchNode() {
    const createStretch = window.TransponoCreateStretch || globalThis.SignalsmithStretch || window.SignalsmithStretch;
    if (typeof createStretch !== 'function')
      throw new Error('A alteração de tom não está disponível neste navegador.');
    const creation = Promise.resolve(createStretch(audioContext, {
      numberOfInputs: 1, numberOfOutputs: 1, outputChannelCount: [2],
    }));
    let expired = false;
    creation.then(node => { if (expired) node.disconnect(); }, () => {});
    try {
      return await timeout(creation, 8000, 'O processamento de tom não pôde ser iniciado.');
    } catch (error) {
      expired = true;
      throw error;
    }
  }

  function listenForProcessorError(graph) {
    graph.stretch.addEventListener('processorerror', () => {
      graph.failed = true;
      dry(graph, true);
      if (graph.element === video)
        unavailable('O processamento parou. O áudio original foi mantido. Reabra o vídeo para tentar novamente.');
      post();
    });
  }

  async function attachStretch(graph) {
    const stretch = await createStretchNode();
    if (disposed || graph.element !== video || isAd || pitch === 0) {
      stretch.disconnect();
      throw new Error('A seleção de vídeo mudou. Aplique o tom novamente.');
    }
    graph.stretch = stretch;
    graph.input.connect(stretch).connect(graph.output).connect(graph.wet);
    graph.dspConnected = true;
    listenForProcessorError(graph);
  }

  async function applyPitch() {
    const element = video;
    const token = ++revision;
    pitchCommandIntent = {commandId: activeDispatchId, token, element};
    const requested = pitch;
    if (!element || isAd || disposed) return;
    if (requested === 0) {
      dry(graphs.get(element), true);
      pitchStatus = 'idle';
      pitchMessage = '';
      return;
    }
    pitchStatus = 'loading';
    pitchMessage = 'A preparar a alteração de tom…';
    const previous = graphs.get(element);
    const keepProcessed = !!previous && previous.audible &&
      previous.acknowledged && previous.dspConnected && !previous.failed;
    if (previous && !keepProcessed) {
      previous.acknowledged = false;
      dry(previous);
    }
    try {
      requireSound(element);
      if (!safeSource(element)) throw new Error('Este vídeo não disponibiliza áudio para alterar o tom neste dispositivo.');
      const graph = await prepareGraph(element);
      if (token !== revision || disposed || element !== video || isAd) return;
      if (graph.failed) throw new Error('O processamento parou. Reabra o vídeo para tentar novamente.');
      await timeout(audioContext.resume(), 4000, 'Toque no vídeo para ativar o áudio e tente novamente.');
      if (!graph.dspConnected) {
        graph.input.connect(graph.stretch);
        graph.stretch.connect(graph.output).connect(graph.wet);
        graph.dspConnected = true;
      }
      const scheduledAt = now();
      await timeout(graph.stretch.schedule({active: true, semitones: requested}), 4000,
        'O processador de tom não respondeu.');
      if (token !== revision || disposed || element !== video || isAd) return;
      graph.appliedPitch = requested;
      graph.acknowledged = true;
      graph.silentSince = null;
      graph.noSignalPlayingMs = 0;
      graph.lastConfirmationTick = null;
      graph.checkAfter = scheduledAt + 250;
      if (keepProcessed && graph === previous && graph.audible) {
        // This processor was already producing audio. Updating its pitch does
        // not require switching back to the unprocessed route or re-priming it.
        pitchStatus = 'active';
        // Applied: nothing to tell (no banner over the player).
        pitchMessage = '';
      } else {
        // First activation still needs real output before leaving the dry route.
        dry(graph);
        pitchMessage = 'Tom preparado; a aguardar sinal de áudio.';
      }
    } catch (error) {
      if (token === revision && !disposed && element === video && !isAd) {
        unavailable(error.message || 'Não foi possível alterar o tom.');
        if (error.code === 'sound-muted') pitchStatus = 'idle';
      }
    }
    post();
  }

  function hasSignal(analyser, samples) {
    analyser.getFloatTimeDomainData(samples);
    return samples.some(sample => Number.isFinite(sample) && Math.abs(sample) > 0.00001);
  }

  function probeMeasurement(analyser, graph) {
    analyser.getFloatFrequencyData(graph.probeSpectrum);
    const bins = graph.probeSpectrum;
    let peak = 1;
    for (let i = 2; i < bins.length - 1; i += 1) {
      if (bins[i] > bins[peak]) peak = i;
    }
    let hz = null;
    if (Number.isFinite(bins[peak]) && bins[peak] > -90) {
      const left = bins[peak - 1];
      const center = bins[peak];
      const right = bins[peak + 1];
      const curvature = left - 2 * center + right;
      const offset = Number.isFinite(curvature) && curvature < 0
        ? Math.max(-0.5, Math.min(0.5, 0.5 * (left - right) / curvature)) : 0;
      hz = (peak + offset) * audioContext.sampleRate / analyser.fftSize;
    }
    analyser.getFloatTimeDomainData(graph.probeWave);
    const energy = graph.probeWave.reduce((total, sample) => total + sample * sample, 0);
    return {hz, rms: Math.sqrt(energy / graph.probeWave.length)};
  }

  function probeSnapshot() {
    const graph = video && graphs.get(video);
    const input = graph ? probeMeasurement(graph.input, graph) : {hz: null, rms: null};
    const output = graph ? probeMeasurement(graph.output, graph) : {hz: null, rms: null};
    const finalOutput = graph && graph.probeFinal
      ? probeMeasurement(graph.probeFinal, graph) : {hz: null, rms: null};
    return {
      inputHz: input.hz, outputHz: output.hz, inputRms: input.rms, outputRms: output.rms,
      finalHz: finalOutput.hz, finalRms: finalOutput.rms,
      sampleRate: audioContext ? audioContext.sampleRate : null,
      contextState: audioContext ? audioContext.state : 'absent',
      dryGain: graph ? graph.dry.gain.value : null,
      wetGain: graph ? graph.wet.gain.value : null,
      dspConnected: graph ? graph.dspConnected : false,
      effects: graph ? {
        gain: graph.master.gain.value,
        chorus: graph.chorusGain.gain.value,
        feedback: graph.feedbackGain.gain.value,
        delay: graph.echoGain.gain.value,
        reverb: graph.reverbGain.gain.value,
      } : null,
      sourceCount: allGraphs.size,
    };
  }

  function tick() {
    refresh();
    if (disposed || !allowedPage()) return;
    updateKeyDetection();
    if (video && !isAd) {
      const graph = graphs.get(video);
      if (pitchStatus === 'loading' && (video.muted || video.volume === 0)) {
        unavailable('Ative o som do vídeo e tente alterar o tom novamente.');
        pitchStatus = 'idle';
      }
      if (graph && (video.paused || audioContext.state !== 'running')) {
        graph.lastConfirmationTick = null;
      }
      if (graph && graph.acknowledged && !graph.failed && pitch !== 0 && graph.appliedPitch === pitch &&
          safeSource(video) && !video.paused && audioContext.state === 'running' &&
          now() >= graph.checkAfter && pitchStatus !== 'unavailable') {
        if (hasSignal(graph.output, graph.samples)) {
          if (!graph.audible) wet(graph);
          graph.silentSince = null;
          graph.noSignalPlayingMs = 0;
          graph.lastConfirmationTick = null;
          pitchStatus = 'active';
          // Applied: nothing to tell (no banner over the player).
          pitchMessage = '';
        } else if (hasSignal(graph.input, graph.samples)) {
          if (graph.silentSince === null) graph.silentSince = now();
          if (now() - graph.silentSince >= 2500) {
            unavailable('O processador não produziu áudio. O áudio original foi mantido.');
          }
        } else {
          graph.silentSince = null; // Genuine quiet passages are not DSP failures.
          if (pitchStatus === 'loading') {
            if (graph.lastConfirmationTick !== null) {
              // Bound elapsed playable time, excluding pauses/background throttling.
              graph.noSignalPlayingMs += Math.min(500, now() - graph.lastConfirmationTick);
            }
            graph.lastConfirmationTick = now();
            if (graph.noSignalPlayingMs >= 10000) {
              unavailable('Não foi possível confirmar áudio processável neste vídeo. Tente novamente durante a reprodução.');
            }
          }
        }
      }
      if (pendingLoopReturn && !validLoopReturn(pendingLoopReturn)) invalidateLoopObservation();
      if (pendingLoopReturn && (video.paused ||
          now() - pendingLoopReturn.startedAt >= 5000)) {
        // A long buffer/paused return lacks timely confirmation, but is not a
        // new source or external seek. Lose this repetition, not the epoch.
        discardLoopReturn();
      }
      if (loopWanted && loopA !== null && loopB !== null && !video.paused &&
          playbackReady() && !pendingLoopReturn) {
        if (positionOf(video) >= loopB) returnLoopToStart();
        else if (nearLoopStart()) cycleArmed = true;
      }
    }
    post();
  }

  function requireVideo() {
    if (!video) throw new Error('Escolha e abra um vídeo primeiro.');
  }

  function requirePractice() {
    requireVideo();
    if (isAd) throw new Error('Aguarde o fim do anúncio para usar os controles de prática.');
  }

  function numberIn(value, min, max, name) {
    if (typeof value !== 'number' || !Number.isFinite(value) || value < min || value > max) {
      throw new RangeError(name + ' fora do intervalo permitido.');
    }
    return value;
  }

  function requireTimeline() {
    requirePractice();
    if (!durationOf(video)) throw new Error('Aguarde a duração do vídeo. Este controle não está disponível em transmissões ao vivo.');
  }

  async function execute(request) {
    if (disposed || !allowedPage()) throw new Error('O navegador de prática está fechado.');
    refresh();
    if (!request || typeof request.action !== 'string') throw new TypeError('Comando inválido.');
    const effectIntent = {epoch: effectsEpoch, element: video, id: videoId,
      source: sourceOf(video), commandId: activeDispatchId};
    if (Object.hasOwn(desiredEffects(), request.action)) effectIntents.set(request.action, effectIntent);
    function checkEffect(graph) {
      refresh();
      if (effectIntents.get(request.action) !== effectIntent || graph.effectsFailed ||
          !validEffectsContext(effectIntent.epoch, effectIntent.element, effectIntent.id, effectIntent.source)) {
        throw new Error('O ajuste de áudio foi substituído ou o vídeo mudou.');
      }
    }
    switch (request.action) {
      case 'pause':
        invalidatePlaybackIntent();
        if (pendingLoopReturn) discardLoopReturn();
        if (video) video.pause();
        break;
      case 'play':
        requireVideo();
        // Flutter sends an explicit intent, never a toggle based on a possibly
        // stale snapshot. Repeated Play preserves playback and the mute state.
        if (video.paused || video.ended) await playCurrentVideo();
        break;
      case 'playPause':
        requireVideo();
        if (video.paused || video.ended) {
          await playCurrentVideo();
        } else {
          invalidatePlaybackIntent();
          video.pause();
        }
        break;
      case 'unmute':
        requireVideo();
        video.muted = false;
        if (video.volume === 0) video.volume = 1;
        // YouTube's muted autoplay keeps its own mute state ("Toque para
        // ativar o som"): press its unmute control too, as a person would.
        // YouTube's own player API first: it clears its muted state and the
        // "Toque para ativar o som" overlay.
        // (On iPhone the script runs in Gecko's extension sandbox: the page's
        // own methods are reached through wrappedJSObject.)
        const ytElement = typeof document.getElementById === 'function'
          ? document.getElementById('movie_player') : null;
        const ytPlayer = ytElement && (ytElement.wrappedJSObject || ytElement);
        if (ytPlayer && typeof ytPlayer.unMute === 'function') {
          try {
            ytPlayer.unMute();
            if (typeof ytPlayer.getVolume === 'function' && ytPlayer.getVolume() === 0 &&
                typeof ytPlayer.setVolume === 'function') ytPlayer.setVolume(100);
          } catch (_) {}
        }
        const controls = typeof document.querySelectorAll === 'function'
          ? document.querySelectorAll(
            '.ytp-unmute, [class*="unmute" i], [aria-label*="ativar o som" i], [aria-label*="unmute" i]')
          : [];
        for (const control of controls) {
          if (typeof control.click === 'function') { control.click(); break; }
        }
        await playCurrentVideo();
        pitchMessage = '';
        break;
      case 'pitch':
        requirePractice();
        pitch = numberIn(request.value, -12, 12, 'Tom');
        await applyPitch();
        break;
      case 'bass':
      case 'mid':
      case 'treble': {
        requirePractice();
        const value = numberIn(request.value, -12, 12, 'Equalizador');
        if (!safeSource(video))
          throw new Error('Este vídeo não disponibiliza áudio para o equalizador neste dispositivo.');
        requireSound(video);
        const graph = await prepareGraph(video, false);
        checkEffect(graph);
        if (request.action === 'bass') {
          graph.low.gain.setValueAtTime(value, audioContext.currentTime);
          bass = value;
        } else if (request.action === 'mid') {
          graph.mid.gain.setValueAtTime(value, audioContext.currentTime);
          mid = value;
        } else {
          graph.high.gain.setValueAtTime(value, audioContext.currentTime);
          treble = value;
        }
        break;
      }
      case 'gain':
      case 'chorus':
      case 'feedback':
      case 'delay':
      case 'reverb': {
        requirePractice();
        const limits = {
          gain: [-12, 6], chorus: [0, 0.5], feedback: [0, 0.55],
          delay: [0, 0.35], reverb: [0, 0.4],
        };
        const [minimum, maximum] = limits[request.action];
        const value = numberIn(request.value, minimum, maximum, request.action);
        if (!safeSource(video))
          throw new Error('Este vídeo não disponibiliza áudio para efeitos neste dispositivo.');
        requireSound(video);
        const graph = await prepareGraph(video, false);
        checkEffect(graph);
        switch (request.action) {
          case 'gain':
            setEffectParam(graph.master.gain, decibelGain(value), true);
            gain = value;
            break;
          case 'chorus':
            setEffectParam(graph.chorusGain.gain, value, true);
            chorus = value;
            break;
          case 'feedback':
            setEffectParam(graph.feedbackGain.gain, value, true);
            feedback = value;
            break;
          case 'delay':
            setEffectParam(graph.echoGain.gain, value, true);
            delay = value;
            break;
          case 'reverb':
            setEffectParam(graph.reverbGain.gain, value, true);
            reverb = value;
            break;
        }
        break;
      }
      case 'speed': {
        requirePractice();
        const value = numberIn(request.value, 0.25, 2, 'Velocidade');
        if (value !== 1 && !preservesPitch(video)) throw new Error('Este navegador não consegue preservar o tom ao mudar a velocidade.');
        preservesPitch(video);
        video.playbackRate = value;
        speed = video.playbackRate;
        break;
      }
      case 'seekBy': {
        requireTimeline();
        const delta = numberIn(request.value, -86400, 86400, 'Avanço');
        const target = Math.max(0, Math.min(durationOf(video), positionOf(video) + delta));
        invalidateLoopObservation();
        if (loopWanted && (target < loopA || target >= loopB)) loopWanted = false;
        video.currentTime = target;
        break;
      }
      case 'seekTo': {
        requireTimeline();
        const seconds = numberIn(request.value, -Number.MAX_VALUE, Number.MAX_VALUE, 'Posição');
        const target = Math.max(0, Math.min(durationOf(video), seconds));
        invalidateLoopObservation();
        if (loopWanted && (target < loopA || target >= loopB)) loopWanted = false;
        video.currentTime = target;
        break;
      }
      case 'markA':
        requireTimeline();
        invalidateLoopObservation();
        loopA = Math.min(positionOf(video), durationOf(video));
        if (loopB !== null && loopB - loopA < minLoopSeconds) {
          loopB = null;
          loopWanted = false;
        }
        break;
      case 'markB': {
        requireTimeline();
        const candidate = Math.min(positionOf(video), durationOf(video));
        if (loopA === null || candidate - loopA < minLoopSeconds) {
          throw new Error('Marque A primeiro e coloque B pelo menos 0,25 s depois de A.');
        }
        invalidateLoopObservation();
        loopB = candidate;
        loopWanted = true;
        break;
      }
      case 'toggleLoop':
        requireTimeline();
        if (loopA === null || loopB === null || loopB - loopA < minLoopSeconds) {
          throw new Error('Marque A e B antes de ativar o loop.');
        }
        invalidateLoopObservation();
        loopWanted = !loopWanted;
        if (loopWanted && (positionOf(video) < loopA || positionOf(video) >= loopB)) video.currentTime = loopA;
        break;
      case 'clearLoop':
        invalidateLoopObservation();
        loopWanted = false;
        loopA = loopB = null;
        break;
      default:
        throw new Error('Comando não reconhecido.');
    }
    post();
    return snapshot();
  }

  async function command(request) {
    try {
      return await execute(request);
    } catch (error) {
      pitchMessage = error.message || 'Não foi possível aplicar este controle.';
      post();
      throw error;
    }
  }

  // WebView evaluateJavascript does not await returned JS promises. Dart polls
  // this bounded, page-local acknowledgement instead of treating dispatch as
  // completion. IDs are idempotent while retained; forgetting never resurrects
  // an entry when an old asynchronous command eventually finishes.
  function dispatch(id, request) {
    if (typeof id !== 'string' || id.length === 0 || id.length > 100) {
      throw new TypeError('Identificador de comando inválido.');
    }
    if (commandResults.has(id)) return true;
    if (commandResults.size >= maxCommandResults) {
      for (const [key, result] of commandResults) {
        if (result.status !== 'pending') {
          commandResults.delete(key);
          break;
        }
      }
    }
    if (commandResults.size >= maxCommandResults) {
      throw new Error('Demasiados comandos pendentes.');
    }
    const pending = {status: 'pending'};
    commandResults.set(id, pending);
    // Propagate ownership only through synchronous submission. Keeping this
    // global set during await would misattribute independent user commands.
    const previousDispatchId = activeDispatchId;
    let operation;
    try {
      activeDispatchId = id;
      operation = command(request);
    } finally {
      activeDispatchId = previousDispatchId;
    }
    void operation.then(() => {
      if (commandResults.get(id) === pending) commandResults.set(id, {status: 'done'});
    }, error => {
      if (commandResults.get(id) === pending) {
        commandResults.set(id, {
          status: 'error', error: String(error && error.message || 'Comando falhou.').slice(0, 500),
        });
      }
    });
    return true;
  }

  function commandResult(id) {
    const result = commandResults.get(id);
    return result ? {...result, snapshot: disposed ? null : snapshot()} : null;
  }

  function forgetCommand(id) {
    return commandResults.delete(id);
  }

  function cancelCommand(id) {
    if (commandResults.get(id)?.status !== 'pending') return false;
    commandResults.set(id, {status: 'error', error: 'Comando cancelado.'});
    for (const [action, intent] of effectIntents) {
      if (intent.commandId === id) effectIntents.delete(action);
    }
    if (playbackIntent && playbackIntent.commandId === id) {
      const element = playbackIntent.element;
      invalidatePlaybackIntent();
      element.pause();
    }
    if (pitchCommandIntent && pitchCommandIntent.commandId === id &&
        pitchCommandIntent.token === revision) {
      revision += 1;
      dry(graphs.get(pitchCommandIntent.element), true);
      pitch = 0;
      pitchStatus = 'idle';
      pitchMessage = 'Alteração de tom cancelada. O áudio original foi mantido.';
      pitchCommandIntent = null;
    }
    return true;
  }

  function dispose() {
    revision += 1;
    invalidatePlaybackIntent();
    disposed = true;
    clearInterval(timer);
    timer = null;
    if (video) video.pause();
    resetPractice(video);
    allGraphs.forEach(graph => dry(graph, true));
    // Closing the context would permanently silence already attached elements.
    // Keep their dry routes until this document is destroyed; no playback starts.
  }

  function activate() {
    disposed = false;
    if (timer === null) timer = setInterval(tick, 200);
    tick();
  }

  window.TransponoMedia = Object.freeze({
    command, dispatch, commandResult, cancelCommand, forgetCommand, snapshot, dispose, _activate: activate,
  });
  activate();
})();
