# QoLify

A modular collection of quality-of-life addons for WoW retail (Interface 120007 /
Midnight). This one repo ships three CurseForge artifacts: the QoLify suite, plus
standalone [SoundScaper](https://www.curseforge.com/wow/addons/soundscaper) and
[Decor Spendwatch](https://www.curseforge.com/wow/addons/decor-spendwatch).

The core addon draws the settings panel and carries the small QoL tweaks. Bigger
features are **LoadOnDemand modules**: none of their code is loaded until you enable
them in the settings.

## Quality of life tweaks

The main settings page (`/qolify`, or right-click the minimap button) lists small
tweaks that live in the core. Each toggles individually and takes effect immediately
in both directions, no reload needed:

- *Quick delete*: auto-fills the "type DELETE to confirm" popup for rare+ items.
- *Auto-accept resurrection*: accepts resurrections automatically, except combat res.
- *Party Keys in Group Finder*: a dropdown on the listing-creation panel that lists the
  party's keystones (read from LibKeystone as shipped in BigWigs and DBM,
  Details/LibOpenRaid, overheard Angry Keystones broadcasts, or AstralKeys, whichever
  are present) and fills in dungeon, M+ activity and playstyle from the key you pick,
  with the suggested title offered for copy-paste.

## Modules

Each module has its own page in the settings tree (expand QoLify on the left). Tick
"Enable this module" on its page to load it. Its options appear on the same page.
Left-clicking the minimap button opens a dropdown of the enabled modules to pick one
to open (its window if it has one, its settings page otherwise), or opens the settings
directly while no module is enabled. The main QoLify page lists every installed module
with its status, including modules unticked in WoW's own AddOn list, which QoLify
respects and never force-loads.

- **SoundScaper**: per-context sound levels. Same code as the standalone addon and the
  same SavedVariables. If the standalone SoundScaper is installed and enabled, the
  module stands by and mirrors its settings. Remove the standalone and the module takes
  over with the same settings. `/ss` opens its window. The QoLify minimap button replaces the
  standalone's own.
- **Decor Spendwatch**: a gold budget for housing decor, with a red tooltip warning on
  decor over your per-item cap plus spend tracking with chat summaries. Same code and
  SavedVariables as the standalone addon, with the same standby behaviour: it stands by
  while the standalone addon is enabled and takes over with the same data once it is
  removed. `/dsw` opens its settings. The QoLify minimap button replaces the
  standalone's own.

## Slash commands

- `/qolify` opens the settings panel
- `/qolify version` prints the addon version
- `/ss` (or `/soundscaper`) opens SoundScaper once its module or standalone is active
- `/dsw` opens Decor Spendwatch once its module or standalone is active

## One repo, three addons

Modules that also ship standalone keep two .toc files in the same folder:

- `QoLify_<X>/QoLify_<X>.toc` is the module build: LoadOnDemand, `RequiredDeps: QoLify`,
  bootstrapped by `Host_Module.lua`.
- `QoLify_<X>/<X>.toc` is the standalone build: its own version and CurseForge project
  ID, the minimap button file, bootstrapped by `Host_Standalone.lua`.

WoW only reads the .toc whose name matches the folder, so the standalone .toc is inert
in a QoLify install. It exists purely so `make package-<x>` can stage a standalone zip
whose single folder is named `<X>` (that name keys the SavedVariables file in WTF and
must never change). Everything outside the two Host files is shared engine code,
identical in both builds.

## Adding a module

1. Create `QoLify_<Name>/` in the repo root with a `QoLify_<Name>.toc` containing:
   ```
   ## LoadOnDemand: 1
   ## RequiredDeps: QoLify
   ## X-QoLify-Module: 1
   ```
2. Make it visible to WoW with a junction:
   `New-Item -ItemType Junction -Path "<AddOns>\QoLify_<Name>" -Target "<repo>\QoLify_<Name>"`
3. Initialize with the `PLAYER_LOGIN` plus `ADDON_LOADED` dual hook used by the Host
   files. A module's own `ADDON_LOADED` does not fire reliably when loaded at login,
   and `PLAYER_LOGIN` alone misses mid-session enabling.

Small tweaks do not become modules. Add a file under `QoL/` that calls
`QOL.RegisterFeature` at file scope, list it in `QoLify.toc`, and it appears on the
main settings page.

## Development

Copy `.env.example` to `.env` and fill in your CurseForge token before releasing.

```
make lint                    run luacheck (core + QoL + modules)
make format                  format all Lua files with stylua
make check                   format validation without writing (CI)
make package                 build QoLify-x.y.z.zip (core + module folders)
make package-min             build minified suite zip (comments stripped)
make package-soundscaper     build the standalone SoundScaper zip
make package-decorspendwatch build the standalone DecorSpendwatch zip
make release                 upload the suite zip to CurseForge
make release-soundscaper     upload the standalone SoundScaper zip
make release-decorspendwatch upload the standalone DecorSpendwatch zip
make release-all             upload all three
make clean                   remove built zips
```

Each artifact's CurseForge project ID lives in its own .toc as
`## X-Curse-Project-ID:`. Standalones only need a release when their own files
changed and the version in their standalone .toc was bumped. A suite release does not
imply standalone releases.

## Continuous integration

On GitHub, three workflows wrap the make targets. Pushes to master and every pull
request run `make lint` and `make check`, and pull requests additionally build all
three zips as downloadable artifacts. Publishing a GitHub release uploads exactly one
artifact to CurseForge, chosen by the tag name:

| Tag                      | Releases                  |
| ------------------------ | ------------------------- |
| `v1.2.3`                 | the QoLify suite          |
| `soundscaper-v1.2.3`     | standalone SoundScaper    |
| `decorspendwatch-v1.2.3` | standalone DecorSpendwatch |

The workflow refuses to run when the tag's version does not match the artifact's .toc,
and attaches the zip to the GitHub release. It needs a `CURSEFORGE_TOKEN` repository
secret. To release two artifacts, publish two releases.

The CurseForge release type comes from the version: `v0.2.0-alpha.1` uploads as alpha,
`v0.2.0-beta.1` as beta (as does ticking GitHub's pre-release box on a plain tag), and
`v0.2.0` as release. Bump the .toc to the suffixed version before tagging, since the
two must match.

For the rare case where everything changed at once, the manually triggered
"Release all" workflow (Actions tab, Run workflow) uploads any or all artifacts with a
chosen release type, using the versions already in the .tocs. It creates no tags or
GitHub releases.
