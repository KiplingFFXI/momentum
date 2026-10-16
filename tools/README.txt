Momentum rules and release tools
===============================

Run these commands from the project folder with Python 3.12. Packaging uses the
standard library. Dynamis source export needs PyYAML; offline Lua checks need lupa:

  python -m pip install -r tools/requirements.txt

Rendered UI checks use tests/requirements.txt instead. See tests/README.txt.

Phoenix rules
-------------

export_rules.py reads one pinned Phoenix Git revision and writes the small rules
bundle loaded by the addon:

  momentum/data/phoenix_rules.lua

It reads the server's EXP and chain rules, merit conversion, Level Sync penalty
tiers, effect/message definitions, EXP ring values, and the module list. The output
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
The output records the source revision and input hashes. Assertions reject source
changes that need review. It does not edit, switch, or fetch the Phoenix checkout.

Check the existing bundle:

  python tools/export_dynamis.py --source ../Phoenix --check

For an intentional refresh after reviewing the source and loaded modules:

  python tools/export_dynamis.py --source ../Phoenix --ref COMMIT

--source is required. The default revision is pinned in export_dynamis.py.
Omitting --check writes the bundle in place, so inspect that diff and run the
Dynamis tests before including it in a release. No running server is needed.

Ordinary verification and packaging do not regenerate either rules bundle. There is no
scheduled data-refresh workflow.

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

The builder permits only the reviewed runtime manifest, LICENSE, the sound notice,
and the bundled sounds. It rejects unknown or linked files, missing
files, private-path or credential markers, and sound files with changed hashes.
Text line endings, ZIP timestamps, file modes, and entry order are normalized.
Identical reviewed input produces the same archive in the same build environment.
A temporary archive is verified before replacing an existing output.

Job artwork, player settings, profiles, session and Dynamis files, tests, source notes, and
developer tools are not copied into the runtime archive.

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
