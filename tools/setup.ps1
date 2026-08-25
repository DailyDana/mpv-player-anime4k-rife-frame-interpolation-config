<#
  setup.ps1 - install this configuration and fetch the third-party parts.

  What it does:
    1. copies mpv/ into your mpv config directory (never silently overwriting)
    2. downloads the freely licensed scripts and shaders listed in CREDITS.md

  What it does NOT do:
    - install mpv, VapourSynth, the RIFE plugin or any LUT pack
    - touch anything outside your mpv config directory

  Usage:
    .\tools\setup.ps1                 # install into %APPDATA%\mpv
    .\tools\setup.ps1 -Target <path>  # install somewhere else (portable_config)
    .\tools\setup.ps1 -Force          # overwrite existing config files
    .\tools\setup.ps1 -SkipDownload   # only copy config, fetch nothing
#>
[CmdletBinding()]
param(
    [string]$Target = (Join-Path $env:APPDATA 'mpv'),
    [switch]$Force,
    [switch]$SkipDownload
)

$ErrorActionPreference = 'Stop'
$Repo = Split-Path $PSScriptRoot -Parent
$Src  = Join-Path $Repo 'mpv'

function Say([string]$m, [string]$c = 'Gray') { Write-Host $m -ForegroundColor $c }

Say "Target config directory: $Target" 'Cyan'
New-Item -ItemType Directory -Force $Target | Out-Null
foreach ($d in 'scripts', 'script-opts', 'shaders', 'luts') {
    New-Item -ItemType Directory -Force (Join-Path $Target $d) | Out-Null
}

# ---------------------------------------------------------------- config files
Say "`n[1/3] Installing configuration" 'Cyan'
$copied = 0; $skipped = 0
Get-ChildItem $Src -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($Src.Length).TrimStart('\')
    $dst = Join-Path $Target $rel
    New-Item -ItemType Directory -Force (Split-Path $dst -Parent) | Out-Null
    if ((Test-Path $dst) -and -not $Force) {
        Say "  skip (exists): $rel" 'DarkYellow'; $skipped++
    } else {
        Copy-Item $_.FullName $dst -Force; Say "  $rel" 'DarkGray'; $copied++
    }
}
Say "  $copied copied, $skipped skipped (use -Force to overwrite)"

if ($SkipDownload) { Say "`nSkipping downloads (-SkipDownload)." 'Yellow'; return }

# ------------------------------------------------------------------- downloads
Say "`n[2/3] Fetching mpv scripts" 'Cyan'

$scripts = @(
    @{ n = 'thumbfast.lua';             u = 'https://raw.githubusercontent.com/po5/thumbfast/master/thumbfast.lua' }
    @{ n = 'memo.lua';                  u = 'https://raw.githubusercontent.com/po5/memo/master/memo.lua' }
    @{ n = 'autoload.lua';              u = 'https://raw.githubusercontent.com/mpv-player/mpv/master/TOOLS/lua/autoload.lua' }
    @{ n = 'quality-menu.lua';          u = 'https://raw.githubusercontent.com/christoph-heinrich/mpv-quality-menu/master/quality-menu.lua' }
    @{ n = 'sponsorblock_minimal.lua';  u = 'https://codeberg.org/jouni/mpv_sponsorblock_minimal/raw/branch/master/sponsorblock_minimal.lua' }
)

function Get-File($url, $path, $label) {
    try {
        Invoke-WebRequest -Uri $url -OutFile $path -UseBasicParsing -TimeoutSec 40
        Say "  ok   $label" 'DarkGray'; return $true
    } catch {
        Say "  FAIL $label  ($($_.Exception.Message))" 'Red'; return $false
    }
}

$ok = 0; $fail = 0
foreach ($s in $scripts) {
    $p = Join-Path $Target "scripts\$($s.n)"
    if ((Test-Path $p) -and -not $Force) { Say "  skip $($s.n) (exists)" 'DarkYellow'; continue }
    if (Get-File $s.u $p $s.n) { $ok++ } else { $fail++ }
}

Say "`n  uosc must be installed from its own release archive:" 'Yellow'
Say "    https://github.com/tomasklaen/uosc/releases/latest" 'Yellow'
Say "    (extract scripts\uosc\ and fonts\ into $Target)" 'Yellow'

Say "`n[3/3] Fetching shaders" 'Cyan'
$shaders = @(
    @{ n = 'FSRCNNX_x2_8-0-4-1.glsl'; u = 'https://raw.githubusercontent.com/igv/FSRCNN-TensorFlow/master/FSRCNNX_x2_8-0-4-1.glsl' }
    @{ n = 'FSRCNNX_x2_16-0-4-1.glsl'; u = 'https://raw.githubusercontent.com/igv/FSRCNN-TensorFlow/master/FSRCNNX_x2_16-0-4-1.glsl' }
    @{ n = 'ArtCNN_C4F16.glsl';       u = 'https://raw.githubusercontent.com/Artoriuz/ArtCNN/main/GLSL/ArtCNN_C4F16.glsl' }
    @{ n = 'CfL_Prediction.glsl';     u = 'https://raw.githubusercontent.com/Artoriuz/glsl-chroma-from-luma-prediction/main/CfL_Prediction.glsl' }
    @{ n = 'CAS-scaled.glsl';         u = 'https://raw.githubusercontent.com/iwalton3/default-shader-pack/master/shaders/CAS-scaled.glsl' }
)
foreach ($s in $shaders) {
    $p = Join-Path $Target "shaders\$($s.n)"
    if ((Test-Path $p) -and -not $Force) { Say "  skip $($s.n) (exists)" 'DarkYellow'; continue }
    if (Get-File $s.u $p $s.n) { $ok++ } else { $fail++ }
}

Say "`n  Anime4K, KrigBilateral and SSimDownscaler are released as archives or" 'Yellow'
Say "  gists; grab them and drop the .glsl files into $Target\shaders :" 'Yellow'
Say "    https://github.com/bloc97/Anime4K/releases/latest" 'Yellow'
Say "    https://gist.github.com/igv" 'Yellow'

# ---------------------------------------------------------------------- report
Say "`n----------------------------------------------------------" 'Cyan'
Say "Downloaded: $ok   Failed: $fail" $(if ($fail) { 'Yellow' } else { 'Green' })
Say @"

Still to do by hand:
  * mpv itself (a build with vo=gpu-next / libplacebo)
  * uosc + its fonts, Anime4K and igv's shaders (links above)
  * optional: VapourSynth + librife + a RIFE model, for frame interpolation
  * optional: python tools\gen_luts.py   -> nine simple colour LUTs

Colour LUTs you own can simply be dropped into $Target\luts as .cube files;
the Colors menu scans that folder and lists whatever is there.
"@
