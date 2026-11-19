# macgames

Run Windows games on Apple Silicon Macs, with no VM and no paid CrossOver licence. This is a proof of concept.

## How it works

| Layer | Translates | Provided by |
|---|---|---|
| CPU | x86-64 → ARM64 | Rosetta 2 (built into macOS) |
| OS | Windows API → macOS | Wine 11.21 (wine-staging builds by Gcenx) |
| Graphics | Direct3D → Metal | DXMT (D3D10/11), or Wine's vkd3d (D3D12 → Vulkan → Metal via MoltenVK) |

`macgames` downloads pinned builds of these into `dependencies/`, keeps each Wine prefix ("bottle") in `bottles/`, and wires up the environment and DLLs for the chosen backend.

## Layout

```
macgames              -> src/macgames (run ./macgames from the repo root)
src/                  our code: the macgames script and tools/ (probes, Steam helpers, winemac build)
env/.env              your settings and secrets (git-ignored; copy env/.env.example)
dependencies/         third-party software, downloaded or built by `setup` (git-ignored)
  downloads/          release archives
  wine/               Wine Staging 11.21
  wine-dxmt/          Wine Staging 11.21 + DXMT, with the rebuilt winemac.so
  dxmt/  gptk/        DXMT 0.80, Apple Game Porting Toolkit 3.0
  wine-build/         Wine source and build tree for winemac.so
games/<steam appid>/  per-game settings (game.conf)
bottles/              Wine prefixes, with Steam and its game installs (git-ignored)
```

## Settings (env/.env)

```sh
cp env/.env.example env/.env
```

| Variable | Default | Effect |
|---|---|---|
| `STEAM_PIN` | empty | Steam Family View PIN; `launch` unlocks Family View first when set |
| `SHOW_BENCHMARKS` | `false` | Metal performance overlay (FPS, frame time, GPU time, memory) in the top-right corner |
| `METALFX` | `0` | MetalFX upscaling (dxmt) |
| `RETINA` | `1` | `0` for low-DPI mode |
| `DESKTOP` | screen size | Steam virtual desktop size, e.g. `1920x1080` |

A variable set in the shell overrides the file, e.g. `SHOW_BENCHMARKS=true ./macgames launch dxmt 3404260`.

Games are started by Steam and inherit Steam's environment, so `launch` remembers which `SHOW_BENCHMARKS`/`METALFX` values Steam was started with (`bottles/<bottle>/steam-session`) and restarts Steam when they've changed. With `SHOW_BENCHMARKS=true` the overlay then appears as soon as the game starts rendering, whether you use `launch` or the Play button.

### Which backend for DirectX 12?

The same Wine 11.21 build runs Steam **and** reaches D3D12 through its built-in
vkd3d (D3D12 → Vulkan → MoltenVK → Metal). On an Apple M5 this creates a working
D3D12 device at **feature level 11_0** — confirmed by `macgames doctor`, which
runs a tiny probe (`src/tools/d3d12-probe`) with no game installed:

```
CreateDXGIFactory1: 0x00000000
Adapter 0: NVIDIA GeForce 6800 (vendor 0x10de, dedVram 12124MB, flags 0x0)
  D3D12CreateDevice OK at feature level 0xb000
```

(vkd3d spoofs the adapter *name* for game compatibility; the 12 GB VRAM is the
real M5.) Apple's own D3DMetal is faster for D3D12, but it ships inside the Game
Porting Toolkit on Wine 7.7, which is far too old to run today's Steam client —
so it isn't usable as a Steam backend. For DX12 Steam games, use vkd3d; for DX11
games, use DXMT.

## Quick start

```sh
cp env/.env.example env/.env      # settings: Family View PIN, benchmarks overlay, ...
./macgames setup                  # Rosetta + Wine 11.21 + DXMT 0.80 + GPTK 3.0 (~500 MB)
./macgames create main dxmt       # new bottle using DXMT
./macgames install-steam main     # Windows Steam, already updated
./macgames steam main             # log in, install your game
./macgames games main             # list installed games and app IDs
./macgames launch main 3404260    # start a game; applies games/3404260/game.conf
SHOW_BENCHMARKS=true ./macgames launch main 3404260   # with the FPS/memory overlay
METALFX=1 ./macgames launch main 3404260   # MetalFX upscaling (DXMT)
RETINA=0 ./macgames steam main           # opt out of full Retina resolution
```

## Backends

- `dxmt` (default): Wine 11.21 with DXMT swapped in for d3d11/dxgi/d3d10core. Best for D3D11 games; D3D12 still goes through vkd3d. Runs Steam.
- `wined3d`: plain Wine 11.21. D3D9/10/11 → OpenGL (slower, most compatible), D3D12 → vkd3d. Runs Steam. Best for DX12 games, since DXMT's dxgi can get in vkd3d's way.
- `d3dmetal`: Apple's Game Porting Toolkit (Wine 7.7) + D3DMetal. Fastest D3D12, but Wine 7.7 can't run the modern Steam client — use it only to launch a game's own `.exe` directly (`macgames run`).

A bottle's backend is fixed when it's created. `dxmt` and `wined3d` share one Wine build; `d3dmetal` is a different, older one. Prefixes from different Wine builds shouldn't be mixed.

## Commands

```
setup                      download Rosetta, Wine, DXMT and GPTK runtimes
create <bottle> [backend]  new bottle (dxmt | wined3d | d3dmetal)
list                       list bottles
delete <bottle>            remove a bottle
run <bottle> <exe> [args]  run a Windows program
kill <bottle>              stop everything in a bottle
doctor <bottle>            check the Direct3D 12 path works, no game needed
install-steam <bottle>     install Windows Steam (dxmt/wined3d only)
steam <bottle>             open Steam
games <bottle>             list installed Steam games and app IDs
launch <bottle> <appid>    start a Steam game (applies games/<appid>/game.conf)
unlock <bottle> [pin]      leave Steam Family View (PIN defaults to STEAM_PIN)
```

## Per-game settings

`games/<steam-appid>/game.conf` holds per-game settings:

```sh
NAME="Dead as Disco"  # for your reference
ARGS="-dx11"          # extra game arguments
ENV="DXMT_LOG_LEVEL=none"   # extra environment variables
```

## Known issues

- DXMT can't draw with stock Wine 11 ("Failed to create metal view, it seems like your Wine has no exported symbols needed by DXMT"), so every D3D11 game aborts at startup. Wine hides the macOS-driver functions DXMT calls, and Wine 11 reshaped the window data DXMT reads. `setup` rebuilds `winemac.so` from the matching Wine source with `src/tools/winemac-dxmt` (exported symbols plus a small compatibility table), keeping the original as `winemac.so.orig`.
- The Steam overlay is disabled (`gameoverlayrenderer=d`): its DXGI hooks crash games on top of DXMT.
- Steam Family View relocks every time Steam starts and blocks launches (`AppError_45`). With `STEAM_PIN` in `env/.env`, `macgames launch` (or `macgames unlock <bottle>`) unlocks it through the Steam UI's DevTools port; the port opens from the Steam start after `.cef-enable-remote-debugging` is created.
- Launch from your own Terminal: processes started by a sandboxed tool (e.g. an AI coding agent's shell) get no audio device, and Unreal games exit when audio fails to start. Wine's CoreAudio output currently fails on this Mac (`Unit failed to start: 'what'`), so `games/3404260/game.conf` passes `-nosound`. `src/tools/audio-probe/probe.exe` checks audio output in a bottle.

- Steam's login and library windows paint solid black under Wine on macOS (Chromium/CEF 126). `macgames steam` and `launch` swap in a tiny wrapper (`src/tools/webhelper-wrapper`) for `steamwebhelper.exe` that runs Valve's helper with `--disable-gpu --single-process`, start Steam with `-noverifyfiles` so it doesn't undo that, and run it inside a Wine virtual desktop sized to the screen (override with `DESKTOP=1920x1080`).

- Steam's 32-bit updater crashes under wine-staging while fetching the 64-bit client, and that client crashes under GPTK Wine 7.7. `install-steam` works around this: it downloads the client in a hidden GPTK bottle (`bottles/.steam-bootstrap`) — where only the 32-bit updater runs — and copies the finished Steam folder into your bottle, where the modern Wine runs it.
- Kernel-level anti-cheat games (Valorant, Fortnite and others) won't run.
- The vkd3d D3D12 path tops out at feature level 11_0 on this hardware. Games that hard-require 12_1-only features won't start; most that offer a DX11 mode are better off in a `dxmt` bottle.
