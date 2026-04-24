// =============================================================================
// user.js — Ammar's Firefox configuration
// Sidebar settings + privacy hardening (Betterfox-inspired, curated for setup)
// Applied automatically on every Firefox launch.
// =============================================================================

// ── Telemetry — disable all Mozilla data collection ──────────────────────────
user_pref("toolkit.telemetry.unified",                    false);
user_pref("toolkit.telemetry.enabled",                    false);
user_pref("toolkit.telemetry.server",                     "data:,");
user_pref("toolkit.telemetry.archive.enabled",            false);
user_pref("toolkit.telemetry.newProfilePing.enabled",     false);
user_pref("toolkit.telemetry.shutdownPingSender.enabled", false);
user_pref("toolkit.telemetry.updatePing.enabled",         false);
user_pref("toolkit.telemetry.bhrPing.enabled",            false);
user_pref("toolkit.telemetry.firstShutdownPing.enabled",  false);
user_pref("datareporting.healthreport.uploadEnabled",     false);
user_pref("datareporting.policy.dataSubmissionEnabled",   false);
user_pref("browser.ping-centre.telemetry",                false);

// ── Tracking protection ───────────────────────────────────────────────────────
user_pref("privacy.trackingprotection.enabled",                   true);
user_pref("privacy.trackingprotection.socialtracking.enabled",    true);
user_pref("privacy.trackingprotection.cryptomining.enabled",      true);
user_pref("privacy.trackingprotection.fingerprinting.enabled",    true);
user_pref("browser.contentblocking.category",                     "strict");

// ── WebRTC — prevent IP leak through Mullvad ─────────────────────────────────
// Critical: without this, WebRTC can expose your real IP even with VPN active
user_pref("media.peerconnection.ice.no_host",             true);
user_pref("media.peerconnection.ice.proxy_only_if_behind_proxy", true);

// ── Pocket, sponsored content, clutter ───────────────────────────────────────
user_pref("extensions.pocket.enabled",                    false);
user_pref("browser.newtabpage.activity-stream.feeds.section.topstories", false);
user_pref("browser.newtabpage.activity-stream.showSponsored",    false);
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
user_pref("browser.urlbar.suggest.quicksuggest.sponsored", false);

// ── Performance (Wayland + NVIDIA) ────────────────────────────────────────────
user_pref("gfx.webrender.all",          true);
user_pref("media.ffmpeg.vaapi.enabled", true);

// ── Sidebar: vertical tabs, expand on hover (your Windows setup) ─────────────
user_pref("sidebar.verticalTabs",   true);
user_pref("sidebar.expandOnHover",  true);
user_pref("sidebar.visibility",     "expand-on-hover");
user_pref("sidebar.revamp",         true);
user_pref("sidebar.position_start", true);
user_pref("sidebar.animation.enabled",                           true);
user_pref("sidebar.animation.duration-ms",                       200);
user_pref("sidebar.animation.expand-on-hover.delay-duration-ms", 200);
user_pref("sidebar.animation.expand-on-hover.duration-ms",       400);
user_pref("sidebar.backupState", "{\"command\":\"\",\"panelOpen\":false,\"panelWidth\":626,\"launcherWidth\":51,\"expandedLauncherWidth\":166,\"launcherExpanded\":false,\"launcherVisible\":true}");

// ── Toolbar ───────────────────────────────────────────────────────────────────
user_pref("browser.toolbars.bookmarks.visibility", "never");
user_pref("browser.theme.toolbar-theme",           2);
user_pref("reader.toolbar.vertical",               true);
