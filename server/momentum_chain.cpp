/************************************************************************
 * Momentum chain timing
 * Read-only snapshots of the native EXP chain deadline.
 * Source profile: Phoenix 071c401048bdb97bcbe12ad93651574fcf867407
 ************************************************************************/

#include "common/lua.h"
#include "common/timer.h"
#include "map/entities/char_entity.h"
#include "map/lua/lua_base_entity.h"
#include "map/utils/moduleutils.h"

namespace
{
struct MomentumChainSnapshot
{
    bool   known{ false };
    uint16 count{ 0 };
    int64  serverNowMs{ 0 };
    int64  deadlineMs{ 0 };
};

constexpr auto ReadMomentumChain(const expChain_t& chain, const timer::time_point now) -> MomentumChainSnapshot
{
    const auto nowMs = std::chrono::floor<std::chrono::milliseconds>(now.time_since_epoch()).count();
    if (nowMs < 0 || nowMs > 9007199254740991LL)
    {
        return {};
    }

    // The initialized minimum sentinel and expired deadlines both mean no active chain.
    if (chain.chainTime <= now)
    {
        return { true, 0, nowMs, 0 };
    }

    const auto deadlineMs = std::chrono::floor<std::chrono::milliseconds>(chain.chainTime.time_since_epoch()).count();
    // The pinned Phoenix profile has no chain window longer than five minutes.
    if (deadlineMs > 9007199254740991LL || deadlineMs <= nowMs || deadlineMs - nowMs > 300000)
    {
        return {};
    }

    // The engine increments this counter after sending the reward message.
    const auto count = static_cast<uint16>(chain.chainNumber > 0 ? chain.chainNumber - 1 : 0);
    return { true, count, nowMs, deadlineMs };
}
} // namespace

class MomentumChainModule : public CPPModule
{
public:
    void OnInit() override
    {
        ::lua.set_function("GetMomentumChain", [](CLuaBaseEntity* entity) -> sol::table
                           {
                               auto result = ::lua.create_table();
                               result["known"]         = false;
                               result["count"]         = 0;
                               result["server_now_ms"] = 0;
                               result["deadline_ms"]   = 0;

                               if (!entity || !entity->GetBaseEntity() || entity->GetBaseEntity()->objtype != TYPE_PC)
                               {
                                   return result;
                               }

                               const auto* player = static_cast<const CCharEntity*>(entity->GetBaseEntity());
                               if (player->GetMJob() == xi::Job::MON)
                               {
                                   return result;
                               }

                               const auto snapshot     = ReadMomentumChain(player->expChain, timer::now());
                               result["known"]         = snapshot.known;
                               result["server_now_ms"] = snapshot.serverNowMs;
                               result["deadline_ms"]   = snapshot.deadlineMs;
                               result["count"]         = snapshot.count;
                               return result;
                           });
    }
};

REGISTER_CPP_MODULE(MomentumChainModule);
