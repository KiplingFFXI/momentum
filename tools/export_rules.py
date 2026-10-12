"""Export Momentum's small Phoenix rules bundle from a pinned checkout."""

import argparse
import hashlib
from pathlib import Path
import re
import subprocess


PINNED_REF = "071c401048bdb97bcbe12ad93651574fcf867407"
SOURCES = (
    "modules/era/lua/globals/toau_experience_points.lua",
    "scripts/globals/experience_points.lua",
    "sql/exp_base.sql",
    "src/map/merit.cpp",
    "src/map/utils/charutils.cpp",
    "modules/init.txt",
    "data/status_effects.yaml",
    "src/map/status_effect_container.cpp",
    "src/map/ai/states/death_state.cpp",
    "src/map/enums/msg_std.h",
    "src/map/packets/s2c/0x029_battle_message.h",
    "src/map/packets/s2c/0x029_battle_message.cpp",
    "modules/phoenix/lua/custom/level_sync_penalty.lua",
    "modules/phoenix/cpp/player_count.cpp",
    "modules/phoenix/lua/items/era_items.lua",
    "sql/item_usable.sql",
    "modules/phoenix/sql/pxi_item_usable.sql",
    "scripts/enum/item.lua",
    "src/map/enums/msg_basic.h",
    "src/map/packets/s2c/0x017_chat_std.h",
    "src/map/packets/s2c/0x017_chat_std.cpp",
    "src/map/packets/s2c/0x020_item_attr.cpp",
    "src/map/packets/s2c/0x028_battle2.cpp",
    "src/map/entities/char_entity.cpp",
    "src/map/action/action.h",
    "src/map/enums/action/resolution.h",
    "scripts/items/meat_mithkabob.lua",
    "src/map/lua/lua_base_entity.cpp",
    "src/map/lua/lua_statuseffect.cpp",
    "src/map/lua/luautils.cpp",
    "modules/module_utils.lua",
    "scripts/globals/player.lua",
    "scripts/effects/level_sync.lua",
    "scripts/effects/dedication.lua",
)


def read_source(repo, ref, path):
    return subprocess.check_output(
        ["git", "-C", str(repo), "show", f"{ref}:{path}"]
    ).decode("utf-8").replace("\r\n", "\n")


def render(repo, ref):
    revision = subprocess.check_output(
        ["git", "-C", str(repo), "rev-parse", f"{ref}^{{commit}}"], text=True
    ).strip()
    texts = {path: read_source(repo, revision, path) for path in SOURCES}
    era, base, sql, merit, charutils, init = (texts[path] for path in SOURCES[:6])
    if not re.search(r"^era/lua/?$", init, re.M):
        raise ValueError("The pinned module list does not load era/lua.")
    if "xi.pre(xi.expansion.WOTG)" not in era:
        raise ValueError("The ToAU experience gate changed.")
    if "mob:getMainLvl() + mob:getMod(xi.mod.EXP_LVL_MOD)" not in base:
        raise ValueError("The chain level source changed.")
    if "data.mobDifficulty > xi.mobDifficulty.DECENT_CHALLENGE" not in base:
        raise ValueError("The chain eligibility rule changed.")
    if "g_ExpPerLevel[level] = rset->get<uint16>(\"exp\")" not in charutils:
        raise ValueError("The EXP table loader changed.")
    status_data = texts["data/status_effects.yaml"]
    food_block = re.search(r"^  food:\n(.*?)(?=^  \S|\Z)", status_data, re.M | re.S)
    if food_block is None or not re.search(r"^    id: 251$", food_block.group(1), re.M):
        raise ValueError("The Food effect ID changed.")
    if "wear_off_message_id:" in food_block.group(1) or "- death" not in food_block.group(1):
        raise ValueError("Food's loss message or death flag changed.")
    for name, effect_id in (("dedication", 249), ("level_sync", 269)):
        block = re.search(r"^  " + name + r":\n(.*?)(?=^  \S|\Z)", status_data, re.M | re.S)
        if block is None or not re.search(r"^    id: " + str(effect_id) + r"$", block.group(1), re.M):
            raise ValueError("The " + name + " effect ID changed.")
    if not re.search(r"\bEffectWearsOff\s*=\s*206\s*,", texts["src/map/enums/msg_std.h"]):
        raise ValueError("The default effect-loss message changed.")
    effects = texts["src/map/status_effect_container.cpp"]
    if "data.WearOffMessageId == 0 ? MsgStd::EffectWearsOff" not in effects:
        raise ValueError("The default loss-message selection changed.")
    if "PChar, PChar, PStatusEffect->GetIcon(), 0, messageId" not in effects:
        raise ValueError("The owner effect-loss packet changed.")
    if "DelStatusEffectsByFlag(xi::StatusEffectFlag::Death, EffectNotice::Silent)" not in texts["src/map/ai/states/death_state.cpp"]:
        raise ValueError("The silent death-removal path changed.")
    packet_fields = re.findall(
        r"(?:uint32_t|uint16_t|uint8_t|MsgStd)\s+(\w+)\s*;",
        texts["src/map/packets/s2c/0x029_battle_message.h"].split("struct PacketData", 1)[1].split("};", 1)[0],
    )
    if packet_fields != ["UniqueNoCas", "UniqueNoTar", "Data", "Data2", "ActIndexCas", "ActIndexTar", "MessageNum", "Type", "padding1B"]:
        raise ValueError("The 0x029 effect-loss packet layout changed.")
    windows_block = era.split("xi.experiencePoints.chainWindows =", 1)[1]
    windows = re.findall(
        r"maxLevel\s*=\s*(\d+),\s*start\s*=\s*(\d+),\s*windows\s*=\s*\{([^}]+)\}",
        windows_block,
    )
    if len(windows) != 7:
        raise ValueError("Expected seven ToAU chain brackets.")
    multiplier_block = base.split("xi.experiencePoints.chainMultipliers =", 1)[1]
    multiplier_block = multiplier_block.split("}", 1)[0]
    multipliers = re.findall(r"^\s*(\d+(?:\.\d+)?)\s*,?\s*-- Chain", multiplier_block, re.M)
    if len(multipliers) != 6:
        raise ValueError("Expected six chain multipliers.")
    rows = dict((int(a), int(b)) for a, b in re.findall(
        r"INSERT INTO `exp_base` VALUES \((\d+),(\d+)\);", sql
    ))
    if set(rows) != set(range(1, 101)):
        raise ValueError("Expected all 100 EXP threshold rows.")
    lp = int(re.search(r"#define MAX_LIMIT_POINTS (\d+)", merit).group(1))
    sync = texts["modules/phoenix/lua/custom/level_sync_penalty.lua"]
    for contract in ("local graceLevels = 10", "local maxPenalty = 50", "(levelDiff * penaltyPerLevel) / 10",
                     "player:getJobLevel(player:getMainJob())", "player:getLocalVar('[SyncPenalty]Amount')"):
        if not re.search(re.escape(contract).replace(r"\ ", r"\s+"), sync):
            raise ValueError("The sync penalty source contract changed: " + contract)
    tiers = re.findall(r"threshold\s*=\s*(\d+|math.huge),\s*rate\s*=\s*(\d+)", sync)
    if tiers != [("500", "0"), ("1000", "15"), ("2000", "20"), ("math.huge", "25")]:
        raise ValueError("The sync population tiers changed.")
    ring_rows = []
    ring_source = texts["modules/phoenix/lua/items/era_items.lua"]
    for name in ("chariot_band", "empress_band", "emperor_band", "anniversary_ring"):
        block = re.search(r"xi.items\." + name + r"\.onItemUse', function\(target\)(.*?)\nend\)", ring_source, re.S).group(1)
        values = {key: int(re.search(r"local " + key + r"\s*=\s*(\d+)", block).group(1)) for key in ("power", "duration", "subpower")}
        item_id = int(re.search(r"\b" + name.upper() + r"\s*=\s*(\d+)", texts["scripts/enum/item.lua"]).group(1))
        row = re.search(r"VALUES \(" + str(item_id) + r",'" + name + r"',([^;]+)\);", texts["sql/item_usable.sql"]).group(1).split(",")
        charges, use_delay, recast = int(row[4]), int(row[5]), int(row[6])
        overlay = re.search(r'UPDATE `item_usable` SET reuseDelay = (\d+), useDelay = (\d+) WHERE `name` = "' + name + r'";', texts["modules/phoenix/sql/pxi_item_usable.sql"])
        if overlay:
            recast, use_delay = map(int, overlay.groups())
        ring_rows.append((item_id, name.replace("_", " ").title(), values, charges, use_delay, recast))
    lines = [
        "-- Phoenix source rules. Refresh with tools/export_rules.py.",
        "return {",
        f"    source_ref = '{revision}',",
        "    source_profile = 'Phoenix pre-WotG',",
        "    -- The server profile uses a 75 cap; client values still drive progress.",
        "    level_cap = 75,",
        f"    lp_per_merit = {lp},",
        "    food_effect = 251,",
        "    food_end_message = 206,",
        "    sync_effect = 269,",
        "    dedication_effect = 249,",
        "    source_sha256 = {",
    ]
    for path in SOURCES:
        digest = hashlib.sha256(texts[path].encode("utf-8")).hexdigest()
        lines.append(f"        ['{path}'] = '{digest}',")
    lines.extend(["    },", "    tnl = {"])
    for level in range(1, 100):
        lines.append(f"        [{level}] = {rows[level + 1]},")
    lines.extend(["    },", "    chain_multipliers = { " + ", ".join(multipliers) + " },", "    chain_windows = {"])
    for maximum, initial, values in windows:
        nums = [int(value.strip()) for value in values.split(",") if value.strip()]
        if len(nums) != 5:
            raise ValueError("Expected five windows in each chain bracket.")
        lines.append("        { max_level = %s, start = %s, windows = { %s } }," % (
            maximum, initial, ", ".join(str(value) for value in nums)
        ))
    lines.extend(["    },", "    sync_tiers = {",
                  "        { minimum = 0, rate = 0 }, { minimum = 500, rate = 15 },",
                  "        { minimum = 1000, rate = 20 }, { minimum = 2000, rate = 25 },",
                  "    },", "    rings = {"])
    for item_id, name, values, charges, use_delay, recast in ring_rows:
        lines.append("        [%d] = { name = '%s', bonus = %d, cap = %d, duration = %d, max_charges = %d, use_delay = %d, recast_delay = %d }," % (
            item_id, name, values["power"], values["subpower"], values["duration"], charges, use_delay, recast))
    lines.extend(["    },", "}", ""])
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[2] / "Phoenix")
    parser.add_argument("--ref", default=PINNED_REF)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / "momentum/data/phoenix_rules.lua")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    result = render(args.source, args.ref)
    if args.check:
        if not args.output.is_file() or args.output.read_text(encoding="utf-8") != result:
            raise SystemExit("Phoenix rules differ. Run tools/export_rules.py to refresh them.")
        print("Phoenix rules match the pinned source.")
        return
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(result, encoding="utf-8", newline="\n")
    print(f"Wrote {args.output}")


if __name__ == "__main__":
    main()
