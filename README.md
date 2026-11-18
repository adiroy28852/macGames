# macgames

Run Windows games on Apple Silicon Macs, with no VM and no paid CrossOver licence. This is a proof of concept.

## How it works

| Layer | Translates | Provided by |
|---|---|---|
| CPU | x86-64 → ARM64 | Rosetta 2 (built into macOS) |
| OS | Windows API → macOS | Wine (wine-staging builds by Gcenx) |
| Graphics | Direct3D → Metal | DXMT (D3D10/11), Apple's D3DMetal (via GPTK Wine), or WineD3D |

`macgames` downloads pinned builds of these into `runtime/`, keeps each Wine prefix ("bottle") in `bottles/`, and wires up the environment and DLLs for the chosen backend.

## Quick start

```sh
./macgames setup                  # Rosetta + Wine 11.21 + DXMT 0.80 + GPTK 3.0 (~500 MB)
./macgames create main dxmt       # new bottle using DXMT
./macgames install-steam main     # Windows Steam, already updated
./macgames steam main             # log in, install your game
./macgames games main             # list installed games and app IDs
./macgames launch main 3404260    # start a game; applies compat/3404260.conf
HUD=1 ./macgames launch main 3404260   # with the Metal FPS overlay
```

## Backends

- `dxmt`: wine-staging with DXMT swapped in for d3d11/dxgi/d3d10core. Best for D3D11 games.
- `wined3d`: plain Wine (D3D → OpenGL). Slow, but the most compatible fallback.
- `d3dmetal`: Wine from Apple's Game Porting Toolkit, which can run D3D12. The current 64-bit Windows Steam client crashes under this Wine, so it's only usable for non-Steam games for now.

A bottle's backend is fixed when it's created. Prefixes from different Wine builds shouldn't be mixed.

## Per-game settings

`compat/<steam-appid>.conf` holds per-game settings:

```sh
ARGS="-dx11"          # extra game arguments
ENV="DXMT_LOG_LEVEL=none"   # extra environment variables
```

## Known issues

- Steam's 32-bit updater crashes under wine-staging while fetching the 64-bit client, and that client crashes under GPTK Wine. `install-steam` works around this: it runs the update in a hidden GPTK bottle (`bottles/.steam-bootstrap`) and copies the finished Steam folder into your bottle.
- Kernel-level anti-cheat games (Valorant, Fortnite and others) won't run.
- D3D12-only games need `d3dmetal`, which can't run Steam yet (see above).
