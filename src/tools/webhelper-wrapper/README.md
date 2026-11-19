# webhelper-wrapper

Stand-in for Steam's `steamwebhelper.exe`. Under Wine on macOS, Steam's
Chromium UI paints a black window; running Valve's helper with
`--disable-gpu --single-process` fixes it. `macgames steam` moves Valve's
helper to `steamwebhelper_real.exe` and puts this wrapper in its place, which
starts the real helper with those flags plus Steam's own arguments.

Rebuild (needs `brew install mingw-w64`):

    x86_64-w64-mingw32-gcc -O2 -municode -mwindows -static wrapper.c -o steamwebhelper.exe
