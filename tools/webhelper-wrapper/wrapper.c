/* Stand-in for Steam's steamwebhelper.exe. Wine on macOS paints Chromium's
 * multi-process / GPU output as a black window, so run the real helper
 * (steamwebhelper_real.exe, next to this file) with software raster in a
 * single process. Steam's own arguments are passed through unchanged. */
#include <windows.h>
#include <stdio.h>
#include <wchar.h>

#define EXTRA L"--disable-gpu --disable-gpu-compositing --single-process"

int WINAPI wWinMain(HINSTANCE inst, HINSTANCE prev, LPWSTR args, int show) {
    (void)inst; (void)prev; (void)show;
    wchar_t real[MAX_PATH];
    DWORD n = GetModuleFileNameW(NULL, real, MAX_PATH);
    wchar_t *slash = wcsrchr(real, L'\\');
    if (!n || !slash) return 1;
    wcscpy(slash + 1, L"steamwebhelper_real.exe");

    size_t len = wcslen(real) + wcslen(EXTRA) + wcslen(args) + 8;
    wchar_t *cmd = HeapAlloc(GetProcessHeap(), 0, len * sizeof(wchar_t));
    if (!cmd) return 1;
    _snwprintf(cmd, len, L"\"%ls\" %ls %ls", real, EXTRA, args);

    STARTUPINFOW si = { .cb = sizeof si };
    PROCESS_INFORMATION pi;
    if (!CreateProcessW(real, cmd, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi))
        return 1;
    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 1;
    GetExitCodeProcess(pi.hProcess, &code);
    return (int)code;
}
