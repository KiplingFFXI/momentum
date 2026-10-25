#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>

#ifndef MOMENTUM_SOURCE_HASH
#define MOMENTUM_SOURCE_HASH "unbuilt"
#endif
#ifndef MOMENTUM_LAUNCH_TEST_DELAY_BEFORE
#define MOMENTUM_LAUNCH_TEST_DELAY_BEFORE 0
#endif
#ifndef MOMENTUM_LAUNCH_TEST_DELAY_AFTER
#define MOMENTUM_LAUNCH_TEST_DELAY_AFTER 0
#endif
#ifndef MOMENTUM_LAUNCH_TEST_FAIL_CANCEL
#define MOMENTUM_LAUNCH_TEST_FAIL_CANCEL 0
#endif

extern "C" __declspec(dllexport) const char momentum_sound_launcher_source[] =
    "MOMENTUM_SOUND_LAUNCHER_SOURCE_SHA256=" MOMENTUM_SOURCE_HASH;
#if MOMENTUM_LAUNCH_TEST_DELAY_BEFORE > 0 || MOMENTUM_LAUNCH_TEST_DELAY_AFTER > 0 || MOMENTUM_LAUNCH_TEST_FAIL_CANCEL
extern "C" __declspec(dllexport) const char momentum_sound_launcher_test[] = "MOMENTUM_SOUND_LAUNCHER_TEST_BUILD";
#endif

#if defined(_WIN64)
static_assert(sizeof(STARTUPINFOW) == 104, "Unexpected Windows startup ABI.");
static_assert(sizeof(PROCESS_INFORMATION) == 24, "Unexpected Windows process ABI.");
#else
static_assert(sizeof(STARTUPINFOW) == 68, "Unexpected Windows startup ABI.");
static_assert(sizeof(PROCESS_INFORMATION) == 16, "Unexpected Windows process ABI.");
#endif

namespace
{
struct Request
{
    volatile LONG references;
    volatile LONG done;
    volatile LONG cancelled;
    volatile LONG transferred;
    HMODULE request_module;
    HMODULE thread_module;
    WCHAR* application;
    WCHAR* command;
    PROCESS_INFORMATION process;
    DWORD error;
    DWORD elapsed;
};

void close_process(PROCESS_INFORMATION& process)
{
    if (process.hProcess) TerminateProcess(process.hProcess, 125);
    if (process.hThread) CloseHandle(process.hThread);
    if (process.hProcess) CloseHandle(process.hProcess);
    process.hProcess = nullptr;
    process.hThread = nullptr;
}

bool cancel_created_process(PROCESS_INFORMATION& process)
{
#if MOMENTUM_LAUNCH_TEST_FAIL_CANCEL
    const BOOL terminated = FALSE;
#else
    const BOOL terminated = !process.hProcess || TerminateProcess(process.hProcess, 125);
#endif
    if (process.hProcess && !terminated)
    {
        DWORD exit = STILL_ACTIVE;
        if (!GetExitCodeProcess(process.hProcess, &exit) || exit == STILL_ACTIVE) return false;
    }
    if (process.hThread) CloseHandle(process.hThread);
    if (process.hProcess) CloseHandle(process.hProcess);
    process.hProcess = nullptr;
    process.hThread = nullptr;
    return true;
}

void drop_reference(Request* request)
{
    if (InterlockedDecrement(&request->references) != 0) return;
    if (InterlockedCompareExchange(&request->transferred, 0, 0) == 0) close_process(request->process);
    const HMODULE module = request->request_module;
    HeapFree(GetProcessHeap(), 0, request);
    FreeLibrary(module);
}

DWORD WINAPI launch_thread(void* data)
{
    Request* request = static_cast<Request*>(data);
    const HMODULE thread_module = request->thread_module;
    STARTUPINFOW startup = {};
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESHOWWINDOW;
    startup.wShowWindow = SW_HIDE;
    PROCESS_INFORMATION process = {};
#if MOMENTUM_LAUNCH_TEST_DELAY_BEFORE > 0
    Sleep(MOMENTUM_LAUNCH_TEST_DELAY_BEFORE);
#endif
    DWORD error = ERROR_CANCELLED;
    DWORD elapsed = 0;
    if (InterlockedCompareExchange(&request->cancelled, 0, 0) == 0)
    {
        const DWORD started = GetTickCount();
        const BOOL created = CreateProcessW(request->application, request->command, nullptr, nullptr, FALSE,
            CREATE_NO_WINDOW, nullptr, nullptr, &startup, &process);
        error = created ? ERROR_SUCCESS : GetLastError();
        elapsed = GetTickCount() - started;
    }
#if MOMENTUM_LAUNCH_TEST_DELAY_AFTER > 0
    Sleep(MOMENTUM_LAUNCH_TEST_DELAY_AFTER);
#endif
    if (InterlockedCompareExchange(&request->cancelled, 0, 0) != 0)
    {
        // Keep a live child's handles if cancellation could not stop it.
        error = cancel_created_process(process) ? ERROR_CANCELLED : ERROR_SUCCESS;
    }
    request->process.hProcess = process.hProcess;
    request->process.hThread = process.hThread;
    request->process.dwProcessId = process.dwProcessId;
    request->process.dwThreadId = process.dwThreadId;
    request->error = error;
    request->elapsed = elapsed;
    // Publish once. The caller owns any handles transferred after this point.
    InterlockedExchange(&request->done, 1);
    drop_reference(request);
    FreeLibraryAndExitThread(thread_module, 0);
}

SIZE_T text_length(const WCHAR* text)
{
    if (!text) return 0;
    for (SIZE_T index = 0; index < 32767; ++index) if (!text[index]) return index;
    return 0;
}

void copy_text(WCHAR* destination, const WCHAR* source, SIZE_T count)
{
    volatile WCHAR* output = destination;
    for (SIZE_T index = 0; index <= count; ++index) output[index] = source[index];
}
}

extern "C" void* __cdecl momentum_launch_begin(const WCHAR* application, const WCHAR* command)
{
    const SIZE_T app_length = text_length(application);
    const SIZE_T command_length = text_length(command);
    if (!app_length || !command_length) { SetLastError(ERROR_INVALID_PARAMETER); return nullptr; }
    Request* request = static_cast<Request*>(HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY,
        sizeof(Request) + (app_length + command_length + 2) * sizeof(WCHAR)));
    if (!request) { SetLastError(ERROR_NOT_ENOUGH_MEMORY); return nullptr; }
    const LPCWSTR address = reinterpret_cast<LPCWSTR>(&momentum_launch_begin);
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS, address, &request->request_module)
        || !GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS, address, &request->thread_module))
    {
        const DWORD error = GetLastError();
        if (request->request_module) FreeLibrary(request->request_module);
        HeapFree(GetProcessHeap(), 0, request);
        SetLastError(error);
        return nullptr;
    }
    request->references = 2;
    request->application = reinterpret_cast<WCHAR*>(request + 1);
    request->command = request->application + app_length + 1;
    copy_text(request->application, application, app_length);
    copy_text(request->command, command, command_length);
    HANDLE thread = CreateThread(nullptr, 0, launch_thread, request, 0, nullptr);
    if (!thread)
    {
        const DWORD error = GetLastError();
        FreeLibrary(request->thread_module);
        request->references = 1;
        drop_reference(request);
        SetLastError(error);
        return nullptr;
    }
    CloseHandle(thread);
    return request;
}

extern "C" int __cdecl momentum_launch_poll(void* value, PROCESS_INFORMATION* process, DWORD* error, DWORD* elapsed_ms)
{
    if (!value || !process || !error || !elapsed_ms) { SetLastError(ERROR_INVALID_PARAMETER); return -1; }
    Request* request = static_cast<Request*>(value);
    process->hProcess = nullptr;
    process->hThread = nullptr;
    process->dwProcessId = 0;
    process->dwThreadId = 0;
    *error = 0;
    *elapsed_ms = 0;
    if (InterlockedCompareExchange(&request->done, 0, 0) == 0) return 0;
    *elapsed_ms = request->elapsed;
    *error = request->error;
    if (*error != ERROR_SUCCESS) return -1;
    if (InterlockedCompareExchange(&request->transferred, 1, 0) != 0) { *error = ERROR_ALREADY_EXISTS; return -1; }
    process->hProcess = request->process.hProcess;
    process->hThread = request->process.hThread;
    process->dwProcessId = request->process.dwProcessId;
    process->dwThreadId = request->process.dwThreadId;
    return 1;
}

extern "C" void __cdecl momentum_launch_cancel(void* value)
{
    if (value) InterlockedExchange(&static_cast<Request*>(value)->cancelled, 1);
}

extern "C" void __cdecl momentum_launch_release(void* value)
{
    if (!value) return;
    Request* request = static_cast<Request*>(value);
    InterlockedExchange(&request->cancelled, 1);
    drop_reference(request);
}

BOOL WINAPI DllMain(HINSTANCE module, DWORD reason, LPVOID)
{
    if (reason == DLL_PROCESS_ATTACH) DisableThreadLibraryCalls(module);
    return TRUE;
}
