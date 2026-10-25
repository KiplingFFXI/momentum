#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <mmsystem.h>
#include <shellapi.h>
#include <objbase.h>
#include <atomic>
#include <cwchar>
#include <cstdio>
#include <string>

static_assert(sizeof(STARTUPINFOW) == 68, "The worker must target x86.");
static_assert(sizeof(PROCESS_INFORMATION) == 16, "The worker must target x86.");

#ifndef MOMENTUM_SOURCE_HASH
#define MOMENTUM_SOURCE_HASH "unbuilt"
#endif

extern "C" __declspec(dllexport) const char momentum_sound_source[] =
    "MOMENTUM_SOUND_PLAYER_SOURCE_SHA256=" MOMENTUM_SOURCE_HASH;

namespace
{
constexpr wchar_t alias[] = L"momentum_worker_sound";
constexpr DWORD native_timeout = 10000;
constexpr DWORD log_limit = 1024 * 1024;
HANDLE parent_handle = nullptr;
HANDLE stop_event = nullptr;
std::atomic<ULONGLONG> deadline{0};
std::atomic<const char*> operation{"idle"};
std::wstring log_path;
const char* selected = "custom";
const ULONGLONG started_at = GetTickCount64();

void log(const char* event, DWORD code = 0)
{
    if (log_path.empty()) return;
    char line[512];
    SYSTEMTIME time{};
    GetSystemTime(&time);
    const int length = std::snprintf(line, sizeof(line),
        "{\"build\":\"1.4.0-sound-worker-1\",\"event\":\"%s\",\"operation\":\"%s\",\"selected\":\"%s\",\"code\":%lu,\"thread\":%lu,\"elapsed_ms\":%llu,\"time\":\"%04u-%02u-%02uT%02u:%02u:%02u.%03uZ\"}\n",
        event, operation.load(), selected, code, GetCurrentThreadId(), GetTickCount64() - started_at, time.wYear, time.wMonth,
        time.wDay, time.wHour, time.wMinute, time.wSecond, time.wMilliseconds);
    if (length <= 0 || length >= static_cast<int>(sizeof(line))) return;
    HANDLE file = CreateFileW(log_path.c_str(), FILE_APPEND_DATA | FILE_READ_ATTRIBUTES,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return;
    LARGE_INTEGER size{};
    if (GetFileSizeEx(file, &size) && size.QuadPart + length <= log_limit)
    {
        DWORD written = 0;
        if (WriteFile(file, line, static_cast<DWORD>(length), &written, nullptr) && written == static_cast<DWORD>(length)) FlushFileBuffers(file);
    }
    CloseHandle(file);
}

[[noreturn]] void terminate(DWORD code)
{
    TerminateProcess(GetCurrentProcess(), code);
    ExitProcess(code);
}

DWORD WINAPI watchdog(void*)
{
    while (WaitForSingleObject(stop_event, 0) == WAIT_TIMEOUT)
    {
        const DWORD state = WaitForSingleObject(parent_handle, 50);
        if (state == WAIT_OBJECT_0) terminate(125);
        if (state == WAIT_FAILED) terminate(9);
        const ULONGLONG end = deadline.load();
        if (end != 0 && GetTickCount64() >= end) terminate(7);
    }
    return 0;
}

MCIERROR call(const char* name, const std::wstring& command, wchar_t* answer = nullptr, UINT size = 0, bool trace = true)
{
    operation.store(name);
    deadline.store(GetTickCount64() + native_timeout);
    if (trace) log("worker.native.before");
    const MCIERROR code = mciSendStringW(command.c_str(), answer, size, nullptr);
    if (trace || code != 0) log("worker.native.after", code);
    deadline.store(0);
    return code;
}

bool number(const wchar_t* text, DWORD maximum, DWORD& value)
{
    if (text == nullptr || *text == 0) return false;
    unsigned long long total = 0;
    for (const wchar_t* at = text; *at; ++at)
    {
        if (*at < L'0' || *at > L'9') return false;
        total = total * 10 + (*at - L'0');
        if (total > maximum) return false;
    }
    value = static_cast<DWORD>(total);
    return true;
}

bool full_path(const wchar_t* path)
{
    if (path == nullptr || std::wcslen(path) < 3 || std::wcslen(path) >= 32768) return false;
    for (const wchar_t* at = path; *at; ++at) if (*at < 32 || *at == L'"') return false;
    return (path[1] == L':' && (path[2] == L'\\' || path[2] == L'/')) || (path[0] == L'\\' && path[1] == L'\\');
}

int run(int argc, wchar_t** argv)
{
    if (argc == 2 && std::wcscmp(argv[1], L"--self-test") == 0) return 0;
    const bool parent_test = argc == 3 && std::wcscmp(argv[1], L"--self-test-parent") == 0;
    const bool timeout_test = argc == 3 && std::wcscmp(argv[1], L"--self-test-timeout") == 0;
    DWORD parent = 0, volume = 0;
    if (parent_test || timeout_test)
    {
        if (!number(argv[2], MAXDWORD, parent) || parent == 0) return 2;
    }
    else
    {
        if (argc != 5 || !full_path(argv[1]) || !number(argv[2], 1000, volume)
            || !number(argv[3], MAXDWORD, parent) || parent == 0 || (*argv[4] && !full_path(argv[4]))) return 2;
        log_path = argv[4];
        const wchar_t* base = argv[1];
        for (const wchar_t* at = argv[1]; *at; ++at) if (*at == L'\\' || *at == L'/') base = at + 1;
        if (_wcsicmp(base, L"FF VII Save.mp3") == 0) selected = "bundled_save";
        else if (_wcsicmp(base, L"FF IX Moogle.mp3") == 0) selected = "bundled_moogle";
        const wchar_t* extension = std::wcsrchr(base, L'.');
        if (!extension || (_wcsicmp(extension, L".mp3") != 0 && _wcsicmp(extension, L".wav") != 0)) return 2;
    }
    parent_handle = OpenProcess(SYNCHRONIZE, FALSE, parent);
    if (!parent_handle) return 125;
    stop_event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    if (!stop_event) { CloseHandle(parent_handle); return 9; }
    HANDLE monitor = CreateThread(nullptr, 0, watchdog, nullptr, 0, nullptr);
    if (!monitor) { CloseHandle(stop_event); CloseHandle(parent_handle); return 9; }
    if (parent_test || timeout_test)
    {
        if (timeout_test) { operation.store("self_test"); deadline.store(GetTickCount64() + native_timeout); }
        Sleep(INFINITE);
    }
    log("worker.start");
    operation.store("com_init");
    deadline.store(GetTickCount64() + native_timeout);
    log("worker.native.before");
    const HRESULT com = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    log("worker.native.after", static_cast<DWORD>(com));
    deadline.store(0);
    int result = SUCCEEDED(com) ? 0 : 9;
    const DWORD attributes = GetFileAttributesW(argv[1]);
    bool opened = false;
    if (result == 0 && (attributes == INVALID_FILE_ATTRIBUTES || (attributes & FILE_ATTRIBUTE_DIRECTORY))) result = 3;
    else if (result == 0)
    {
        // Both formats use per-device volume and one decoder open in this process.
        const std::wstring command = std::wstring(L"open \"") + argv[1] + L"\" type mpegvideo alias " + alias;
        if (call("open", command) != 0) result = 3;
        else
        {
            opened = true;
            wchar_t length_text[64]{};
            DWORD length = 0;
            if (call("time_format", std::wstring(L"set ") + alias + L" time format milliseconds") != 0
                || call("length", std::wstring(L"status ") + alias + L" length", length_text, 64) != 0
                || !number(length_text, MAXDWORD, length) || length == 0) result = 6;
            else if (call("volume", std::wstring(L"setaudio ") + alias + L" volume to " + std::to_wstring(volume)) != 0) result = 4;
            else if (call("play", std::wstring(L"play ") + alias + L" from 0") != 0) result = 5;
            else
            {
                bool first = true;
                bool playing = false;
                const ULONGLONG play_started = GetTickCount64();
                for (;;)
                {
                    MSG message{};
                    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE))
                    {
                        if (message.message == WM_QUIT) { result = 125; break; }
                        TranslateMessage(&message);
                        DispatchMessageW(&message);
                    }
                    if (result != 0) break;
                    wchar_t status[64]{};
                    if (call("status", std::wstring(L"status ") + alias + L" mode", status, 64, first) != 0) { result = 6; break; }
                    first = false;
                    if (_wcsicmp(status, L"playing") == 0)
                    {
                        if (!playing) { playing = true; log("worker.playback.started"); }
                    }
                    else if (_wcsicmp(status, L"stopped") == 0)
                    {
                        if (playing) { log("worker.playback.completed"); break; }
                        wchar_t position_text[64]{};
                        DWORD position = 0;
                        if (call("position", std::wstring(L"status ") + alias + L" position", position_text, 64, false) != 0
                            || !number(position_text, MAXDWORD, position)) { result = 6; break; }
                        // A short sound can finish before the first status check.
                        if (position >= length) { log("worker.playback.started"); log("worker.playback.completed"); break; }
                        // Give asynchronous playback time to start before treating it as finished.
                        if (GetTickCount64() - play_started >= 1000) { result = 6; break; }
                    }
                    else { result = 6; break; }
                    Sleep(50);
                }
            }
        }
    }
    if (opened)
    {
        const MCIERROR stopped = call("stop", std::wstring(L"stop ") + alias);
        const MCIERROR closed = call("close", std::wstring(L"close ") + alias);
        if (result == 0 && (stopped != 0 || closed != 0)) result = 8;
    }
    if (SUCCEEDED(com))
    {
        operation.store("com_close");
        deadline.store(GetTickCount64() + native_timeout);
        log("worker.native.before");
        CoUninitialize();
        log("worker.native.after");
        deadline.store(0);
    }
    log("worker.exit", static_cast<DWORD>(result));
    SetEvent(stop_event);
    WaitForSingleObject(monitor, INFINITE);
    CloseHandle(monitor);
    CloseHandle(stop_event);
    CloseHandle(parent_handle);
    return result;
}
}

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int)
{
    SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX | SEM_NOOPENFILEERRORBOX);
    int argc = 0;
    wchar_t** argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (!argv) return 2;
    int result = 9;
    try { result = run(argc, argv); }
    catch (...) { log("worker.failure", 9); }
    LocalFree(argv);
    return result;
}
