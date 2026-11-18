# d3d12-probe

Tiny Direct3D 12 probe: creates a DXGI factory, enumerates adapters, and tries
`D3D12CreateDevice` at feature levels 12_1 → 11_0. Used to confirm the
D3D12 → vkd3d → Vulkan → MoltenVK → Metal path works in a bottle, independent
of any game.

`macgames doctor <bottle>` runs the prebuilt `probe.exe`.

Rebuild (needs `brew install mingw-w64`):

    x86_64-w64-mingw32-gcc -O2 probe.c -o probe.exe -ld3d12 -ldxgi

Result on Apple M5, Wine 11.21, macOS 26.6: device created at feature level
11_0; adapter reports the M5's real VRAM (vkd3d spoofs the adapter *name*).
