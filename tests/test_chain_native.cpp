#include "../server/momentum_chain.cpp"

namespace
{
constexpr auto testNow = timer::time_point(std::chrono::milliseconds(100000));
constexpr auto neverStarted = ReadMomentumChain({ 0, timer::time_point::min() }, testNow);
static_assert(neverStarted.known && neverStarted.count == 0 && neverStarted.deadlineMs == 0 && neverStarted.serverNowMs == 100000);

constexpr auto expired = ReadMomentumChain({ 8, testNow - std::chrono::milliseconds(1) }, testNow);
static_assert(expired.known && expired.count == 0 && expired.deadlineMs == 0 && expired.serverNowMs == 100000);

constexpr auto atDeadline = ReadMomentumChain({ 8, testNow }, testNow);
static_assert(atDeadline.known && atDeadline.count == 0 && atDeadline.deadlineMs == 0);

constexpr auto firstKill = ReadMomentumChain({ 1, testNow + std::chrono::seconds(300) }, testNow);
static_assert(firstKill.known && firstKill.count == 0 && firstKill.deadlineMs == 400000);

constexpr auto chainThree = ReadMomentumChain({ 4, testNow + std::chrono::seconds(120) }, testNow);
static_assert(chainThree.known && chainThree.count == 3 && chainThree.deadlineMs == 220000);

constexpr auto outsideProfile = ReadMomentumChain({ 4, testNow + std::chrono::milliseconds(300001) }, testNow);
static_assert(!outsideProfile.known && outsideProfile.serverNowMs == 0 && outsideProfile.deadlineMs == 0);

constexpr auto invalidFuture = ReadMomentumChain({ 4, timer::time_point::max() }, testNow);
static_assert(!invalidFuture.known);

constexpr auto invalidClock = ReadMomentumChain({ 0, timer::time_point::min() }, timer::time_point(std::chrono::milliseconds(-1)));
static_assert(!invalidClock.known);
} // namespace
