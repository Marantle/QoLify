-include .env
export

ADDON          := QoLify
VERSION        := $(shell grep "^\#\# Version:" $(ADDON).toc | awk '{print $$3}')
TOC_VERSION    := $(shell grep "^\#\# Interface:" $(ADDON).toc | awk '{print $$3}')
TOC_DISPLAY    := $(shell echo $(TOC_VERSION) | awk '{printf "%d.%d.%d", substr($$0,1,2), substr($$0,3,2), substr($$0,5,2)}')
CURSE_PROJECT  := $(shell grep "^\#\# X-Curse-Project-ID:" $(ADDON).toc | awk '{print $$3}')

# Packaged files are derived from the relevant .toc, never hand-listed or
# wildcarded, so a zip can never drift from what the game actually loads.
# Pull every .lua line the .toc references, drop CRLF, and turn backslash
# paths into forward slashes (\134 is octal for backslash).
toc_lua = $(shell grep -vE '^[[:space:]]*\#' $(1) | grep -iE '\.lua[[:space:]]*$$' | tr -d '\r' | tr '\134' '/')

SRC_LUA        := $(call toc_lua,$(ADDON).toc)
SRC_FILES      := $(SRC_LUA) $(ADDON).toc
DIST_FILES     := $(SRC_FILES)

# LoadOnDemand module sub-addons live in QoLify_*/ and ship in the suite zip
# as sibling top-level folders. Each module's file list comes from its
# QoLify_<X>.toc, which keeps standalone-only files (Host_Standalone.lua,
# minimap code, the standalone .toc, CHANGELOG.md) out of the suite zip.
MODULES        := $(patsubst %/,%,$(wildcard $(ADDON)_*/))
MODULE_FILES   := $(foreach m,$(MODULES),$(addprefix $(m)/,$(call toc_lua,$(m)/$(m).toc)) $(m)/$(m).toc)

# Modules that also ship as standalone CurseForge addons. Each has a second
# .toc named after the standalone folder (inert in a QoLify install, since
# WoW only reads the .toc matching the folder name) that carries its own
# version, project ID and file list.
STANDALONES    := SoundScaper DecorSpendwatch

SS_TOC         := $(ADDON)_SoundScaper/SoundScaper.toc
SS_VERSION     := $(shell grep "^\#\# Version:" $(SS_TOC) | awk '{print $$3}')
SS_PROJECT     := $(shell grep "^\#\# X-Curse-Project-ID:" $(SS_TOC) | awk '{print $$3}')
SS_FILES       := $(call toc_lua,$(SS_TOC))

DSW_TOC        := $(ADDON)_Decor/DecorSpendwatch.toc
DSW_VERSION    := $(shell grep "^\#\# Version:" $(DSW_TOC) | awk '{print $$3}')
DSW_PROJECT    := $(shell grep "^\#\# X-Curse-Project-ID:" $(DSW_TOC) | awk '{print $$3}')
DSW_FILES      := $(call toc_lua,$(DSW_TOC))

# Lint and format cover every Lua file, packaged or not. Kept as shell globs
# rather than make wildcards: they force make to run the recipe through sh,
# whose 64-bit process finds luacheck and stylua in system32 (32-bit GnuWin32
# make execs directly and WoW64 redirection hides them).
ALL_LUA        := *.lua QoL/*.lua $(ADDON)_*/*.lua

RELEASE_TYPE   ?= alpha
CHANGELOG      ?= See project page for changes.

.PHONY: help lint format check package package-min package-soundscaper package-decorspendwatch release release-soundscaper release-decorspendwatch release-all debug-release clean

help:
	@echo "make lint                    run luacheck over core, QoL and all modules"
	@echo "make format                  format all Lua files with stylua"
	@echo "make check                   check formatting without writing (for CI)"
	@echo "make package                 build $(ADDON)-$(VERSION).zip (suite: core + modules)"
	@echo "make package-min             build $(ADDON)-$(VERSION)-min.zip (comments stripped)"
	@echo "make package-soundscaper     build SoundScaper-$(SS_VERSION).zip (standalone)"
	@echo "make package-decorspendwatch build DecorSpendwatch-$(DSW_VERSION).zip (standalone)"
	@echo "make release                 upload the suite zip to CurseForge"
	@echo "make release-soundscaper     upload the standalone SoundScaper zip"
	@echo "make release-decorspendwatch upload the standalone DecorSpendwatch zip"
	@echo "make release-all             upload all three (only when all three changed)"
	@echo "make clean                   remove built zips"
	@echo ""
	@echo "Standalones only need a release when their own files changed and the"
	@echo "version in their standalone .toc was bumped. A suite release does not"
	@echo "imply standalone releases."

lint:
	luacheck $(ALL_LUA)

format:
	stylua $(ALL_LUA)

check:
	stylua --check $(ALL_LUA)

package:
	@echo "Packaging $(ADDON) suite v$(VERSION)..."
	@rm -f $(ADDON)-*.zip
	@rm -rf dist
	@mkdir -p dist/$(ADDON)
	@cp --parents $(SRC_FILES) dist/$(ADDON)/
	@cp --parents $(MODULE_FILES) dist/
	@pwsh -NoProfile -Command "Compress-Archive -Path 'dist/*' -DestinationPath '$(ADDON)-$(VERSION).zip'"
	@rm -rf dist
	@echo "Built $(ADDON)-$(VERSION).zip"

package-min:
	@echo "Packaging $(ADDON) suite v$(VERSION) (minified)..."
	@rm -f $(ADDON)-*-min.zip
	@rm -rf dist
	@mkdir -p dist/$(ADDON)
	@python minify.py dist/$(ADDON) $(DIST_FILES)
	@python minify.py dist $(MODULE_FILES)
	@pwsh -NoProfile -Command "Compress-Archive -Path 'dist/*' -DestinationPath '$(ADDON)-$(VERSION)-min.zip'"
	@rm -rf dist
	@echo "Built $(ADDON)-$(VERSION)-min.zip"

# Stages a standalone build from a module folder (arg 4, no longer always
# $(ADDON)_$(1) since the Decor module folder and its standalone kept
# different names). The zip contains a single folder named after the
# standalone (that name keys the SavedVariables file in WTF, so it must
# never change) holding only the files its standalone .toc lists, plus that
# .toc itself.
define PACKAGE_STANDALONE
	@echo "Packaging $(1) v$(2)..."
	@rm -f $(1)-*.zip
	@rm -rf dist
	@mkdir -p dist/$(1)
	@cd $(4) && cp --parents $(3) $(1).toc ../dist/$(1)/
	@pwsh -NoProfile -Command "Compress-Archive -Path 'dist/$(1)' -DestinationPath '$(1)-$(2).zip'"
	@rm -rf dist
	@echo "Built $(1)-$(2).zip"
endef

package-soundscaper:
	$(call PACKAGE_STANDALONE,SoundScaper,$(SS_VERSION),$(SS_FILES),$(ADDON)_SoundScaper)

package-decorspendwatch:
	$(call PACKAGE_STANDALONE,DecorSpendwatch,$(DSW_VERSION),$(DSW_FILES),$(ADDON)_Decor)

# Shared upload recipe. Arguments: zip file, CurseForge project ID,
# changelog path. The project ID comes from the matching .toc, so each
# artifact releases to its own CurseForge project.
define CURSE_UPLOAD
	@test -n "$(CURSEFORGE_TOKEN)" || { echo "Error: CURSEFORGE_TOKEN not set"; exit 1; }
	@test -n "$(2)" || { echo "Error: X-Curse-Project-ID missing from the .toc"; exit 1; }
	@test "$(2)" != "0" || { echo "Error: X-Curse-Project-ID is still 0, create the CurseForge project first"; exit 1; }
	@echo "Uploading $(1) (WoW $(TOC_DISPLAY)) to CurseForge project $(2)..."
	@GAME_VER_ID=$$(curl -sf \
	  -H "X-Api-Token: $(CURSEFORGE_TOKEN)" \
	  "https://wow.curseforge.com/api/game/versions" | \
	  python -c "import json,sys; v='$(TOC_DISPLAY)'; d=json.load(sys.stdin); print(next((x['id'] for x in d if x['name']==v),''))"); \
	test -n "$$GAME_VER_ID" || { echo "Error: WoW $(TOC_DISPLAY) not found in CurseForge API"; exit 1; }; \
	python -c "import json; open('.release_meta.json','w').write(json.dumps({'gameVersions':[int('$$GAME_VER_ID')],'releaseType':'$(RELEASE_TYPE)','changelog':open('$(3)').read(),'changelogType':'markdown'}))" && \
	curl -sf \
	  -H "X-Api-Token: $(CURSEFORGE_TOKEN)" \
	  -F "metadata=<.release_meta.json;type=application/json" \
	  -F "file=@$(1)" \
	  "https://wow.curseforge.com/api/projects/$(2)/upload-file" && \
	rm -f .release_meta.json && \
	echo "Released $(1) as '$(RELEASE_TYPE)'."
endef

release: package
	$(call CURSE_UPLOAD,$(ADDON)-$(VERSION).zip,$(CURSE_PROJECT),CHANGELOG.md)

release-soundscaper: package-soundscaper
	$(call CURSE_UPLOAD,SoundScaper-$(SS_VERSION).zip,$(SS_PROJECT),$(ADDON)_SoundScaper/CHANGELOG.md)

release-decorspendwatch: package-decorspendwatch
	$(call CURSE_UPLOAD,DecorSpendwatch-$(DSW_VERSION).zip,$(DSW_PROJECT),$(ADDON)_Decor/CHANGELOG.md)

# Convenience for the rare case where the core and both standalones all
# changed. Day to day, release each artifact on its own when it changes.
release-all: release release-soundscaper release-decorspendwatch

debug-release: package
	@test -n "$(CURSEFORGE_TOKEN)" || { echo "Error: CURSEFORGE_TOKEN not set"; exit 1; }
	@echo "Fetching game version ID for WoW $(TOC_DISPLAY)..."
	@GAME_VER_ID=$$(curl -sf \
	  -H "X-Api-Token: $(CURSEFORGE_TOKEN)" \
	  "https://wow.curseforge.com/api/game/versions" | \
	  python -c "import json,sys; v='$(TOC_DISPLAY)'; d=json.load(sys.stdin); print(next((x['id'] for x in d if x['name']==v),''))"); \
	test -n "$$GAME_VER_ID" || { echo "Error: WoW $(TOC_DISPLAY) not found"; exit 1; }; \
	echo "Game version ID: $$GAME_VER_ID"; \
	python -c "import json; open('.release_meta.json','w').write(json.dumps({'gameVersions':[int('$$GAME_VER_ID')],'releaseType':'$(RELEASE_TYPE)','changelog':open('CHANGELOG.md').read(),'changelogType':'markdown'}))" && \
	echo "Metadata:" && cat .release_meta.json && echo "" && \
	curl -v \
	  -H "X-Api-Token: $(CURSEFORGE_TOKEN)" \
	  -F "metadata=<.release_meta.json;type=application/json" \
	  -F "file=@$(ADDON)-$(VERSION).zip" \
	  "https://wow.curseforge.com/api/projects/$(CURSE_PROJECT)/upload-file"; \
	rm -f .release_meta.json

clean:
	@rm -f $(ADDON)-*.zip $(foreach s,$(STANDALONES),$(s)-*.zip)
	@rm -rf dist
