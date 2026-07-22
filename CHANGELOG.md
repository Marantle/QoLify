# Changelog

## 1.0.0
- First stable release. Same feature set as 0.1.0.

## 0.1.0
- Initial release: modular QoL collection core.
- Small quality-of-life tweaks live on the main settings page with per-feature
  toggles that work immediately in both directions: Quick delete (auto-fills the
  DELETE confirmation for rare+ items), Auto-accept resurrection (except combat
  res), and Party Keys in Group Finder (a dropdown on the listing-creation panel
  that lists the party's keystones, gathered from LibKeystone as shipped in
  BigWigs and DBM, Details/LibOpenRaid, overheard Angry Keystones broadcasts and
  AstralKeys, whichever are present, and fills the listing's dungeon, M+ activity
  and playstyle from the selected key, with the suggested title offered for
  copy-paste).
- Bigger features are LoadOnDemand modules. No module code loads until enabled in
  settings.
- Minimap button: left-click opens a dropdown of the enabled modules to pick one
  to open (falls back to the settings while no module is enabled). Right-click
  opens the settings.
- Settings panel (`/qolify`, or the minimap button) with per-module enable
  checkboxes. The main page lists every module with live status, and modules
  unticked in WoW's own AddOn list are respected (shown as such, never
  force-loaded).
- SoundScaper module: the standalone SoundScaper (v1.3.0) as a module, same code
  and SavedVariables. Stands by while the standalone addon is active, and takes
  over with the same settings once it is removed. `/ss` opens the window.
- Decor Spendwatch module: the standalone DecorSpendwatch (v1.1.0) as a module,
  same code and SavedVariables. Stands by while the standalone addon is active,
  and takes over with the same data once it is removed. `/dsw` opens the
  settings.
