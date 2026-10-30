Momentum rules and release tools
===============================

Run these commands from the project folder with Python 3.12. Packaging uses the
standard library. Phoenix source exports need PyYAML; offline Lua checks
need lupa:

  python -m pip install -r tools/requirements.txt

Rendered UI checks use tests/requirements.txt instead. See tests/README.txt.

Phoenix rules
-------------

export_rules.py reads one pinned Phoenix Git revision and writes the small rules
bundle loaded by the addon:

  momentum/data/phoenix_rules.lua

It reads data/experience.yaml with the enabled module overlays, chain rules,
merit conversion, Level Sync penalty tiers, effect/message definitions, EXP ring
values, and the module list. It also checks the EXP dataset and loader. The output
records the source revision and hashes. Assertions stop the export when a reviewed
source assumption changes. It does not edit the Phoenix checkout or contact the
running server.

Check the bundled rules against the pinned revision:

  python tools/export_rules.py --source ../Phoenix --check

The default source is a Phoenix checkout next to this project. The default revision
is pinned in export_rules.py; it is not a moving branch and is not fetched for you.
Use --help for the available arguments. An intentional update can name a reviewed
commit with --ref COMMIT and a comparison file with --output PATH. Check the diff,
the relevant loaded modules, and the affected tests before replacing the bundle.

Phoenix Dynamis
---------------

export_dynamis.py writes momentum/data/dynamis_rules.lua from one pinned Phoenix
Git revision. It reads the active era and Phoenix overlays in module order, along
with hourglass timing, extensions, objectives, boss weakening, currency, and drops.
The current Phoenix zone overlays live directly under modules/phoenix/data/zones.
The exporter checks that the enabled era spawn data is present before using it.
The output records the source revision and input hashes. Assertions reject source
changes that need review. It does not edit, switch, or fetch the Phoenix checkout.

Check the existing bundle:

  python tools/export_dynamis.py --source ../Phoenix --check

For an intentional refresh after reviewing the source and loaded modules:

  python tools/export_dynamis.py --source ../Phoenix --ref COMMIT

--source is required. The default revision is pinned in export_dynamis.py.
Omitting --check writes the bundle in place, so inspect that diff and run the
Dynamis tests before including it in a release. No running server is needed.

Phoenix Assault and battlefields
--------------------------------

export_events.py writes momentum/data/event_rules.lua from one pinned Phoenix
Git revision. It reads the supported Assault missions, legacy Limbus routes,
BCNM/KSNM/ENM definitions, objectives, entry items, seals, drops, messages, and
entry cooldowns. Applicable loaded era and Phoenix overlays are included.
The output records the revision and input hashes. Source assumptions that need
review stop the export. It does not change, switch, fetch, or query a running server.

Check the existing bundle:

  python tools/export_events.py --source ../Phoenix --check

For an intentional refresh after reviewing the source and loaded overlays:

  python tools/export_events.py --source ../Phoenix --ref COMMIT

--source is required. The default revision is pinned in export_events.py.
Omitting --check replaces the bundled data, so inspect the diff and run the event
rules, runtime, client, layout, and UI tests before including it in a release.
The catalog is reference data; it does not imply hidden progress or entry eligibility.

ENM key-item waits start on acquisition. Limbus starts its character wait on
entry, and Dynamis starts its account-wide lockout at successful registration.
The optional Limbus account group is a local reminder, not a server restriction.
Normal NPC timestamps take priority over estimated acquisition or entry times.
Shami event fields and orb costs are source-derived; the client observer still
waits for a successful normal transaction before changing a stored seal total.

All three exporters are pinned to Phoenix live commit
ed41f351f63b24e015059c5a58f1c29eb3f198ac, reviewed October 30, 2026. Each generated
bundle records that revision and the hashes of its source inputs. A passing
--check confirms that recorded source, not that Phoenix live has not changed.

Before a release, compare the pins with the published live branch as described
in docs/RELEASING.md. For a deliberate refresh, update PINNED_REF in all three
tools to the reviewed commit and regenerate the bundles. --ref COMMIT selects a
revision for one invocation only; it does not change PINNED_REF. Keep each tool's
default pin and the generated source_ref in sync.

Ordinary verification and packaging do not regenerate any rules bundle. There is
no scheduled data-refresh workflow.

Sound helper
------------

The runtime includes bin/momentum-sound.exe, bin/momentum-sound-launch.dll, and
core/sound_worker.lua. The player handles sounds in a separate process. The small
launcher starts that process from its own native thread; it does not call Lua or
load a decoder in the game. Native source lives in native/sound_player.cpp and
native/sound_launcher.cpp. Their Windows builds and source verification are in
tools/build_sound_player.py and tools/build_sound_launcher.py. Bundled and custom
MP3/WAV files and per-alert volume remain supported. The Linux-safe sound-directory
scan is separate and must not be replaced by the old shared directory helper.

Check the shipped helper without compiling or playing a sound:

  python tools/build_sound_player.py --check
  python tools/build_sound_launcher.py --check

After a reviewed native-source change, rebuild on Windows with the Visual Studio
x86 C++ tools and Windows SDK installed:

  python tools/build_sound_player.py
  python tools/build_sound_launcher.py

--out PATH selects another output. The player uses a static C++ runtime and the
Windows subsystem. The launcher uses only Kernel32 imports, with no C++ runtime,
WinMM, or COM. Ordinary release packaging verifies the existing binaries; it does
not compile native code or require Visual Studio on the packaging machine.

The release builder accepts only the named x86 PE32 Windows executable and DLL.
It checks their DLL flags, section bounds, embedded source digests, and private
paths and credential markers in plain and UTF-16 text. Each source digest covers
its native source and build script, so changes need a fresh binary before
packaging. Launcher builds with forced test delays or cancellation failures carry
a separate marker and cannot be packaged. No source files, build reports, or extra
executables or DLLs are copied into the runtime archive.

Offline verification
--------------------

  python tests/verify.py

This runs the Lua suites, Python tests, and tools/check_repository.py. It needs
Ashita's Lua libraries; ASHITA_LIBS can select another installation. The Verify
workflow runs on Windows with a pinned Ashita library checkout, matching the
settings library's path handling. Rendered UI checks are separate:

  python tests/preview/verify_preview.py

check_repository.py validates public text, required release documents, local
Markdown links, and the current changelog heading. It excludes local test outputs,
virtual environments, and extracted preview fonts.

Build a runtime archive
-----------------------

  python tools/build_release.py

The default output is the user's Downloads folder. The archive is named
momentum-<version>.zip using addon.version in momentum/momentum.lua. A successful
build prints its file count and SHA-256.

  python tools/build_release.py --out dist

--out chooses a different output directory for CI or a local build. Output must
stay outside the runtime addon folder.

The builder permits only the reviewed runtime manifest, including the checked
sound helper, LICENSE, the sound notice, and the bundled sounds. It rejects
unknown or linked files, missing
files, private-path or credential markers, and sound files with changed hashes.
Text line endings, ZIP timestamps, file modes, and entry order are normalized.
Identical reviewed input produces the same archive in the same build environment.
A temporary archive is verified before replacing an existing output.

The Farming runtime is included in the same addon archive: core/farming.lua,
core/farming_client.lua, and ui/farming.lua. Its saved statistics and manual
prices stay under the normal Momentum configuration folder. There is no
separate Farming package, sound variant, server component, or data request.

Job artwork, player settings, profiles, sessions, event histories, local account
groups and cooldown records, tests, source notes, and developer tools are not copied
into the runtime archive.

Momentum is fully client-side. Do not add or package server modules, custom
server data feeds, or server commands. Rules exporters read source for reference;
they do not change Phoenix or require anything to be installed on the server.

Release notes and GitHub
-----------------------

  python tools/release_notes.py --out tests/out/release-notes.md

This extracts the current version's entry from CHANGELOG.md. Keep temporary output
outside tracked source, or remove it after review.

For a next-release draft before assigning a new version:

  python tools/release_notes.py --unreleased --out tests/out/next-release-notes.md

Unreleased may appear above the current numbered changelog entry. Repository
checks still require that numbered entry to match addon.version. Before building
a release, assign its version and promote the Unreleased notes into that entry.

.github/workflows/verify.yml runs on pull requests, manual requests, or a call from
another workflow. .github/workflows/draft-release.yml runs only when a maintainer
requests it manually. It verifies on Windows first, builds the runtime archive
on Ubuntu, attaches a SHA-256 file, and creates a draft. It refuses an existing
release or version tag so an archive cannot be attached to different source.
It does not run from a version edit, a tag, or a schedule, and it never publishes.

See docs/RELEASING.md for the full checklist. Offline checks, source checks, live
client checks, and publication are separate results.
