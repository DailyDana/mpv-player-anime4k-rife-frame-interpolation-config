# Credits and third-party components

This repository ships configuration only. Everything below belongs to its own
authors and is fetched from source by `tools/setup.ps1` or installed by you.
Each project keeps its own license — check it before redistributing anything.

## Player and runtime

| Component | Source | Fetched by setup? |
|---|---|---|
| mpv | https://mpv.io | no — install it yourself |
| ffmpeg | bundled with most mpv builds | no |
| yt-dlp | https://github.com/yt-dlp/yt-dlp | no |
| VapourSynth | https://www.vapoursynth.com | no — needed only for RIFE |
| RIFE plugin (`librife`) and models | vs-mlrt / RIFE ncnn projects | no |

## mpv scripts

| Script | Source | Fetched |
|---|---|---|
| uosc (menu and OSC) | https://github.com/tomasklaen/uosc | yes |
| thumbfast (timeline thumbnails) | https://github.com/po5/thumbfast | yes |
| memo (recently played) | https://github.com/po5/memo | yes |
| autoload (queue folder) | mpv `TOOLS/lua` | yes |
| quality-menu (yt-dlp formats) | https://github.com/christoph-heinrich/mpv-quality-menu | yes |
| sponsorblock_minimal | https://codeberg.org/jouni/mpv_sponsorblock_minimal | yes |

## Shaders

| Shader | Source | Fetched |
|---|---|---|
| Anime4K | https://github.com/bloc97/Anime4K | yes |
| FSRCNNX | https://github.com/igv/FSRCNN-TensorFlow | yes |
| KrigBilateral, SSimDownscaler, adaptive-sharpen | https://gist.github.com/igv | yes |
| ArtCNN | https://github.com/Artoriuz/ArtCNN | yes |
| CfL Prediction | https://github.com/Artoriuz/glsl-chroma-from-luma-prediction | yes |
| AMD FidelityFX CAS | AMD FidelityFX (MIT) | yes |

## Color LUTs

`tools/gen_luts.py` generates nine simple LUTs (warm, cool, vivid, cinematic,
pastel, sepia, black and white, night, anime boost) from plain math — those are
part of this repository's own work.

Film emulation packs, vendor LUTs and commercial look packs are **not** included
and are not downloaded. If you own them, drop the `.cube` files into your
`luts/` folder and they will appear in the Colors menu automatically.

## This repository

`mpv.conf`, `input.conf`, `rife.vpy`, the four Lua scripts under `mpv/scripts/`,
the configs under `mpv/script-opts/`, and the tools and tests are MIT licensed —
see [LICENSE](LICENSE).
