Momentum status companion

These optional modules have not been deployed. The addon and its local chain
countdown work without them. Applied sync penalty, remaining Dedication bonus
and the native server chain deadline then remain unavailable.

Source contract: phoenix/live 071c401048bdb97bcbe12ad93651574fcf867407.
Review against the deployed server before installing. A maintainer can place
momentum_status.lua under modules/custom/lua and list that exact path AFTER the
Phoenix Lua directory in modules/init.txt. This is not part of the client addon.
No changes to the Phoenix checkout or server configuration are made by Momentum.

The optional momentum_chain.cpp module exposes GetMomentumChain to Lua. To
enable native chain timing, a maintainer must also place that file under
modules/custom/cpp, list its path in modules/init.txt, rebuild xi_map, and deploy
the rebuilt server through the normal maintenance process. This package does
none of those steps. Without that C++ module, the Lua companion sends an unknown
chain state while its existing EXP status feed continues to work.

Players opt in themselves with !momentumstatus on, and stop with
!momentumstatus off. The preference is a character variable and survives zones
and login. The addon never sends either command. Only consenting characters
receive a snapshot every five seconds and after relevant effect/EXP events.
The module reads EXP state and writes only its own subscription/timer metadata.
It does not change EXP, modifiers, effects, items, or player actions.

Protocol version 1 uses incoming packet 0x017, SYSTEM_3 (29), sender Momentum,
and text starting MOM1|. Ordered decimal fields are player ID, zone ID, main
job, actual level, effective level, sequence, server UTC seconds, sync flag,
stored sync penalty, stored rate (tenths of a percent per level), Dedication
flag, remaining bonus pool, bonus percent, remaining whole seconds, enabled.
There are exactly 15 numeric fields. Text is at most 150 bytes. The standard
packet also carries zone ID; the decoder checks both. Player chat cannot select
SYSTEM_3. This identifies the server channel; it is not a cryptographic signature.

The client accepts only its own current job/zone/level/effect snapshot and a
newer sequence. Snapshots expire after 12 seconds. When game UTC is available,
timestamps outside the freshness allowance are rejected. Only a fully parsed,
accepted frame may be hidden; normal chat, malformed frames and other senders
must be left untouched. A user who disables the addon while still subscribed
can see the protocol messages until they use !momentumstatus off.

Applied sync penalty comes from [SyncPenalty]Amount, not a fresh estimate.
Rate comes from [SyncPenalty]RatePerLevel. The original sampled population is
not stored by Phoenix and is not claimed. Effect changes are sampled after
their callbacks finish, including complete Dedication removal. A five-second
heartbeat also catches sync-target level changes that do not regain the effect.

Native chain timing uses a separate MOMC1 frame on the same server channel and
sender. Its 12 decimal fields are player ID, zone ID, main job, actual level,
effective level, sequence, server UTC seconds, enabled, known, current chain
count, server monotonic time in milliseconds, native deadline in milliseconds.
MOM1 and MOMC1 share a sequence for each paired snapshot; receivers keep separate
replay state for the two protocols. Decimal numbers are at most 2^53-1 and the
complete message stays below the 150-byte packet limit.

Known active timing has deadline greater than server time, with no more than
300000 milliseconds remaining. The deadline is read from expChain.chainTime;
it is never rebuilt from a monster level or the time the addon saw a reward.
Heartbeats preserve that same deadline until the engine replaces it. The engine
stores the next chain number, so the exported count is that number minus one.
An active count of zero is the first eligible kill's window. A zero-EXP kill can
refresh the native deadline without incrementing the reward chain count.
Known inactive state has count and deadline zero. Unknown state or opt-out has
known, count, server time, and deadline zero. No gameplay state is changed.

The engine clock is monotonic and not shared with the client. Receivers subtract
server time from deadline, account for the report's known UTC age, and count down
locally. Subsecond delivery time and UTC precision still limit synchronization.
This removes the bracket range without claiming a perfectly synchronized clock. Accepted snapshots
must retain the same character, job, zone, freshness and replay checks as MOM1.

Source references at the pinned revision:
- src/map/entities/char_entity.h:133-137 stores expChain.
- src/map/utils/charutils.cpp:4693-4724 sets its native deadline.
- src/map/utils/charutils.cpp:5087-5114 sends and then increments chainNumber.
- src/common/timer.h defines the steady clock and millisecond conversion.
- modules/phoenix/cpp/player_count.cpp registers a global from CPPModule::OnInit.
- modules/phoenix_archive/beta/tester_gear.cpp verifies the entity binding shape.

Developer validation: run python tests/check_chain_module.py from a Visual
Studio Developer PowerShell. It requires the existing Phoenix compile database,
its dependency headers, and Python's ruamel.yaml, Jinja2 and jsonschema packages.
It extracts pinned source headers into a temporary directory, regenerates enum
headers there, and runs MSVC syntax checks only. It does not change the Phoenix
checkout, build a server executable, access a database, or start a server.
