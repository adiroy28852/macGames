# cpu-probe

Prints the x86 instruction-set extensions a Windows program sees (CPUID), to
check that Rosetta advertises AVX/AVX2 (`ROSETTA_ADVERTISE_AVX=1`, macOS 15+).
`macgames doctor <bottle>` runs it.

Rebuild (needs `brew install mingw-w64`):

    x86_64-w64-mingw32-gcc -O2 probe.c -o probe.exe
