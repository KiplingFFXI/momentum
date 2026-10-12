# Releasing Momentum

This checklist prepares a reviewable release. It does not publish one or establish live-client or server testing.

## Prepare the version

1. Set `addon.version` in `momentum/momentum.lua` to the intended `major.minor.patch` version.
2. Put that same version at the top of [CHANGELOG.md](../CHANGELOG.md), with player-facing notes for the final change.
3. Update installation examples and the [guide](GUIDE.md) when names or behavior change. Preserve saved settings, profiles, and session compatibility.
4. For game-rule changes, review the pinned Phoenix revision and loaded modules, regenerate the rules deliberately, and run the source check. A release build does not refresh them.

The initial public version is **1.0.0**.

## Verify

From the project folder with Python 3.12 and the dependencies described in [tests/README.txt](../tests/README.txt):

```powershell
python tests/verify.py
python tests/preview/verify_preview.py
python tools/export_rules.py --source ../Phoenix --check
```

The first command runs the offline Lua suites, Python tests, and repository checks. The second draws the real Lua UI with simulated client data and replays input. The source check requires the pinned Phoenix revision in a local checkout.

For a performance change, compare operation counts with a previous archive and review the affected behavior checks. Inspect relevant screenshots after a UI change. Record any client checks separately, including loading or reloading, chat placement, real EXP/LP gains, merit conversion, effect timers, and chosen alerts. Do not describe offline results as live testing.

## Build and inspect

```powershell
python tools/build_release.py
```

The archive goes to Downloads by default. Use `--out PATH` for another output folder. The builder prints its SHA-256. Inspect the ZIP contents and use the printed hash when recording the build.

The runtime ZIP contains `momentum/` with the reviewed addon files and license. It must not include settings, profiles, sessions, test output, private paths, or developer files. See [tools/README.txt](../tools/README.txt) for the manifest checks and reproducibility rules.

If an operator specifically needs the optional server package, build it separately with `--server` and review [its instructions](../server/README.txt). Packaging it is not deployment, and the client addon does not require it.

## Create a draft

After the reviewed source is available in the GitHub repository, a maintainer can open **Actions > Draft release > Run workflow** and choose the intended branch. The workflow:

1. Runs the reusable **Verify** workflow on Windows with pinned Ashita libraries.
2. Reads the current version and changelog entry.
3. Refuses an existing release or tag named `v<version>`, keeping the archive tied to the reviewed source.
4. Builds the runtime ZIP and a SHA-256 file on Ubuntu.
5. Creates a draft named `Momentum <version>` for the selected commit.

The workflow runs only by manual request. Version edits, pushes, tags, and schedules do not create a release. It does not regenerate Phoenix data or upload the optional server package.

Review the draft's version, target commit, notes, archive, and checksum. Publishing remains a separate maintainer action on the Releases page. An existing release's files should not be silently replaced.

## Update an installed copy

If Momentum is running, enter `/addon unload momentum` before replacing `addons/momentum/` with the reviewed runtime folder. Keep `config/addons/momentum/`, which holds settings, profiles, shared layouts, sessions, and custom sounds. Enter `/addon load momentum` after replacing the files.
