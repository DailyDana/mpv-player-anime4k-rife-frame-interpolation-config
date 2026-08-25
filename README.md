# mpv-anime-config

An mpv configuration built around **anime upscaling (Anime4K / FSRCNNX)** and
**RIFE frame interpolation**, with a right-click menu system that reports what
the player is *actually* doing rather than what it was told to do.

Every non-obvious choice in here was verified by measurement, not assumption —
see [Why it is built this way](#why-it-is-built-this-way).

> This repository contains **configuration only**. No player binaries, no
> shaders, no LUTs — those are fetched from their own sources by `tools/setup.ps1`
> or installed by you. See [What is not included](#what-is-not-included).

---

## Features

- **Right-click menu** covering file, playback, video, audio, subtitles, colors
  and tools, built on [uosc](https://github.com/tomasklaen/uosc).
- **Live settings panels** that stay open while you adjust, so you can compare
  changes on the running video instead of reopening a menu every time.
- **RIFE frame interpolation** with a configurable resolution policy — the panel
  tells you exactly what will happen to the file you have open, for example
  `1080p / 24 fps -> processed at 720p, 2x`.
- **Shader profiles** for Anime4K (Mode A, Mode A+A, +sharpening), FSRCNNX and
  AMD CAS, with a rule that prevents two scalers from fighting each other.
- **Color LUT menu** built by scanning your `luts/` folder — only LUTs you
  actually have are listed.
- **Custom 9-band equalizer** alongside presets, saved between sessions.
- **Brightness bar** on the left screen edge, mirroring uosc's volume bar.
- **Bookmarks** and an **A-B clip cutter** (fast ffmpeg copy, no re-encode).

## Requirements

| Component | Needed for | Notes |
|---|---|---|
| mpv (recent build with `vo=gpu-next`) | everything | libplacebo based renderer |
| VapourSynth + `librife` plugin + a RIFE model | RIFE only | optional; everything else works without it |
| ffmpeg on PATH | clip cutter only | optional |
| yt-dlp | streaming URLs | optional |

Without VapourSynth the player still works fully; only frame interpolation is
unavailable.

## Install

```powershell
git clone https://github.com/<user>/mpv-anime-config.git
cd mpv-anime-config
.\tools\setup.ps1            # fetches uosc, shaders and helper scripts
```

`setup.ps1` copies the contents of `mpv/` into your mpv config directory
(`%APPDATA%\mpv` on Windows) and downloads the third-party scripts and shaders
listed in [CREDITS.md](CREDITS.md). It never overwrites without telling you.

To generate the nine simple color LUTs (warm, cool, vivid, cinematic, ...):

```powershell
python tools\gen_luts.py
```

## Keybindings

| Key | Profile |
|---|---|
| `CTRL+1` | Anime4K Mode A (HQ) |
| `CTRL+2` | Anime4K Mode A+A (HQ) |
| `CTRL+3` | Anime4K A+A + Sharpening |
| `CTRL+4` | Anime4K A+A + RIFE |
| `CTRL+5` | FSRCNNX Light (general content) |
| `CTRL+6` | AMD CAS (light, standalone) |
| `CTRL+9` | RIFE on/off |
| `CTRL+0` | turn all shaders off |

Right-click opens the full menu. `I` then `2` shows mpv's render pass list,
which is the ground truth for *which shader is actually running*.

## RIFE settings

All policy lives in `script-opts/rife.conf`, editable by hand or from
**Video Quality > RIFE Settings**:

| Mode | Behaviour |
|---|---|
| `performance` | anything above `work_height` is downscaled before interpolation |
| `balanced` | full resolution up to 1080p, only larger sources are downscaled |
| `quality` | never downscales |

Two guards are on by default and can be switched off in the menu:

- `skip_above_height=1440` — RIFE stays off for 4K. Downscaling 4K to 720p and
  interpolating destroys the detail that made it 4K in the first place.
- `fps_threshold=40` — RIFE stays off for 50/60fps sources. Doubling 60fps to
  120fps is a load no GPU keeps up with, and it shows up as slow motion.

`multiplier` accepts `2`, `3` or `4`.

## Why it is built this way

These are not style preferences; each one is a bug that was found by measuring
the running player, and the configuration is shaped to avoid it.

- **The interpolation policy lives in Lua, not in the `.vpy` script.** mpv's
  VapourSynth bridge reports the clip frame rate as `0/1`, so a guard written
  inside the script can never fire. The real value is available to mpv as
  `container-fps`, so the decision belongs on that side.
- **Filters are added and removed by label.** `vf set` and `vf clr` replace the
  whole chain and silently delete the user's own filters (mirror, color matrix,
  sharpening).
- **Sharpening uses a `MAIN`-hooked shader.** Shaders hooked at `OUTPUT` are
  registered by libplacebo but never executed under `vo=gpu-next`, so they look
  enabled while doing nothing.
- **A chain may contain only one scaler family.** CAS resizes luma to output
  size, which makes Anime4K's upscale conditions false and disables it silently.
- **Every profile writes the full scaler set.** mpv profiles cannot be undone,
  so a profile that only sets some properties leaves the rest dirty forever.
- **Bit depth is preserved at the bridge input.** mpv hands VapourSynth 8-bit by
  default, so a 10-bit source loses depth before the script ever sees it.
- **The menu verifies state against `vo-passes`.** A shader that fails to load
  stays in the `glsl-shaders` property, so the property alone cannot tell you
  whether it is running.

## Repository layout

```
mpv/                 files that go into your mpv config directory
  mpv.conf
  input.conf
  rife.vpy           RIFE transform layer (no policy)
  scripts/           panels.lua, brightness-bar.lua, bookmarks.lua, clip-cutter.lua
  script-opts/       rife.conf, uosc.conf
tools/
  setup.ps1          fetch third-party components, install config
  gen_luts.py        generate the nine simple color LUTs
tests/
  acceptance.lua     runtime checks for the behaviours listed above
```

## What is not included

Deliberately absent, because they belong to their authors and are better taken
from source:

- mpv, ffmpeg, yt-dlp, VapourSynth, Python, the RIFE plugin and model
- uosc, thumbfast, memo, autoload, quality-menu, sponsorblock_minimal
- Anime4K, FSRCNNX, ArtCNN, KrigBilateral, SSimDownscaler, CAS shaders
- Commercial and vendor colour LUTs (film emulation packs, SpeedLooks, etc.)

`tools/setup.ps1` fetches the freely licensed ones. See [CREDITS.md](CREDITS.md).

## License

The configuration, Lua scripts and `rife.vpy` in this repository are MIT
licensed — see [LICENSE](LICENSE). Third-party components keep their own
licenses.
