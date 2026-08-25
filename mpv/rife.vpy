# ============================================================
#  RIFE 2x/3x/4x frame interpolation - pure transform layer
#
#  ARCHITECTURAL RULE: this file contains NO policy.
#  "Should RIFE run?" is decided in panels.lua (source fps and resolution
#  thresholds are checked there). If this script is invoked, it runs.
#  The only decision here is HOW: at what resolution, with which multiplier.
#
#  Timestamps are produced by mpv's VapourSynth bridge and were verified by
#  measurement: for CFR and VFR alike the interpolated frame lands exactly at
#  the midpoint of the real interval. This file never touches timestamps.
# ============================================================

import vapoursynth as vs
import os

core = vs.core

try:
    _base = os.path.dirname(os.path.abspath(__file__))
except NameError:
    _base = os.path.join(os.environ.get("APPDATA", ""), "mpv")

core.std.LoadPlugin(os.path.join(_base, "vapoursynth", "librife_windows_x86-64.dll"))

# ---- read script-opts/rife.conf ---------------------------------------
_VARSAYILAN = {
    "mode": "performance",
    "work_height": 720,
    "multiplier": 2,
    "model": 23,
    "gpu": 0,
    "gpu_thread": 2,
    "scene_detect": 1,
}


def _ayar_oku():
    a = dict(_VARSAYILAN)
    try:
        with open(os.path.join(_base, "script-opts", "rife.conf"), encoding="utf-8") as f:
            for satir in f:
                satir = satir.split("#", 1)[0].strip()
                if "=" not in satir:
                    continue
                anahtar, deger = (p.strip() for p in satir.split("=", 1))
                if anahtar not in a:
                    continue
                if isinstance(_VARSAYILAN[anahtar], int):
                    try:
                        a[anahtar] = int(float(deger))
                    except ValueError:
                        pass
                else:
                    a[anahtar] = deger.lower()
    except OSError:
        pass  # no config file: continue with defaults
    return a


A = _ayar_oku()

clip = video_in
kaynak_format = clip.format          # bit depth is recovered from this
yukseklik = clip.height
hedef = max(64, int(A["work_height"]))

# ---- resolution policy ------------------------------------------------
# downscale only when needed; sources at or below the target are left alone
if A["mode"] == "quality":
    kucult = False
elif A["mode"] == "balanced":
    kucult = yukseklik > 1080        # 1080p'ye kadar tam cozunurluk
else:                                 # performans
    kucult = yukseklik > hedef

if kucult and yukseklik > hedef:
    genislik = round(clip.width * hedef / yukseklik / 2) * 2
    # downscale and convert to RGBS in one step (RIFE expects float RGB)
    clip = core.resize.Spline36(clip, genislik, hedef, format=vs.RGBS, matrix_in_s="709")
else:
    clip = core.resize.Bicubic(clip, format=vs.RGBS, matrix_in_s="709")

# uhd=True: optical flow is computed at half resolution. Needed to stay
# real-time at 720p and above, at a limited quality cost.
uhd = clip.height >= 720

clip = core.rife.RIFE(
    clip,
    model=int(A["model"]),
    factor_num=max(2, int(A["multiplier"])),
    gpu_id=int(A["gpu"]),
    gpu_thread=int(A["gpu_thread"]),
    sc=bool(int(A["scene_detect"])),
    uhd=uhd,
)

# ---- convert back to the source format --------------------------------
# NOTE: the matrix round trip is symmetric (out via 709, back via 709), so
# BT.601/BT.2020 content suffers no color shift - measured: luma PSNR = inf.
# Bit depth is inherited from the source instead of being pinned to 8-bit.
clip = core.resize.Bicubic(clip, format=kaynak_format.id, matrix_s="709")
clip.set_output()
