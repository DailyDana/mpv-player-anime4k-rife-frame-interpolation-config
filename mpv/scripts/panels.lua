-- ============================================================
--  panels.lua - live settings panels for uosc ("keep_open" menus)
--
--  ARCHITECTURE: policy lives here, math in VapourSynth, real state in mpv.
--   * THIS layer decides whether RIFE runs at all (source fps and
--     resolution thresholds). rife.vpy is a pure transform layer.
--   * Filters are always added/removed BY LABEL; "vf set/clr" is never used
--     (it used to wipe the user's mirror/matrix/sharpening filters).
--   * "Is this profile active?" is verified against vo-passes; a shader that
--     failed to load never shows up as "active" in the UI.
-- ============================================================

local mp = require 'mp'
local utils = require 'mp.utils'

local function ac(menu)        -- ilk acilis
    mp.commandv('script-message-to', 'uosc', 'open-menu', utils.format_json(menu))
end
local function guncelle(menu)  -- acik menuyu yerinde guncelle (navigasyon korunur)
    mp.commandv('script-message-to', 'uosc', 'update-menu', utils.format_json(menu))
end
local function msg(fmt, ...)
    mp.osd_message(select('#', ...) > 0 and string.format(fmt, ...) or fmt, 2)
end
local function vf_aktif(label)
    for _, f in ipairs(mp.get_property_native('vf', {})) do
        if f.label == label then return true end
    end
    return false
end
local function af_aktif(label)
    for _, f in ipairs(mp.get_property_native('af', {})) do
        if f.label == label then return true end
    end
    return false
end

-- ============================================================
--  RIFE POLICY LAYER  (script-opts/rife.conf = single source of truth)
-- ============================================================
local RIFE_CONF = mp.command_native({'expand-path', '~~/script-opts/rife.conf'})
local RIFE_VARSAYILAN = {
    mode = 'performance', work_height = 720, skip_above_height = 1440,
    fps_threshold = 40, multiplier = 2, scene_detect = 1, model = 23, gpu = 0, gpu_thread = 2,
}

local function rife_ayar()
    local a = {}
    for k, v in pairs(RIFE_VARSAYILAN) do a[k] = v end
    local f = io.open(RIFE_CONF, 'r')
    if f then
        for satir in f:lines() do
            local temiz = satir:gsub('#.*', '')
            local k, v = temiz:match('^%s*([%w_]+)%s*=%s*(.-)%s*$')
            if k and a[k] ~= nil then
                if type(RIFE_VARSAYILAN[k]) == 'number' then
                    a[k] = tonumber(v) or a[k]
                else
                    a[k] = v:lower()
                end
            end
        end
        f:close()
    end
    return a
end

-- Updates a single key without disturbing the comments
local function rife_ayar_yaz(anahtar, deger)
    local satirlar, bulundu = {}, false
    local f = io.open(RIFE_CONF, 'r')
    if f then
        for satir in f:lines() do
            if satir:match('^%s*' .. anahtar .. '%s*=') then
                satirlar[#satirlar + 1] = anahtar .. '=' .. tostring(deger)
                bulundu = true
            else
                satirlar[#satirlar + 1] = satir
            end
        end
        f:close()
    end
    if not bulundu then satirlar[#satirlar + 1] = anahtar .. '=' .. tostring(deger) end
    local w = io.open(RIFE_CONF, 'w')
    if w then w:write(table.concat(satirlar, '\n') .. '\n'); w:close() end
end

-- Source bit depth. Hardware decoding reports nv12 for 8-bit and p010 for
-- 10-bit; software decoding reports yuv420p / yuv420p10. Both must be handled.
local function kaynak_bit_derinligi()
    local pf = (mp.get_property('video-params/pixelformat') or ''):lower()
    if pf == '' then return 8 end
    if pf:find('^nv1') or pf:find('^nv2') then return 8 end
    if pf:find('^p010') then return 10 end
    if pf:find('^p016') then return 16 end
    return tonumber(pf:match('p(%d+)l?e?$')) or 8
end

-- "Should RIFE run for this file?" -> applicable, reason
local function rife_karar()
    local a = rife_ayar()
    local h = mp.get_property_number('video-params/h')
    local fps = mp.get_property_number('container-fps')
    if a.skip_above_height > 0 and h and h > a.skip_above_height then
        return false, string.format('%dp source - RIFE off above %dp (detail preserved)',
                                    h, a.skip_above_height)
    end
    -- If fps is unknown, do NOT block: silently disabling the feature is a
    -- worse failure than running it unnecessarily.
    if a.fps_threshold > 0 and fps and fps > a.fps_threshold then
        return false, string.format('%.4g fps source is already smooth - RIFE skipped (threshold %d fps)',
                                    fps, a.fps_threshold)
    end
    return true, nil
end

local function rife_acik_mi() return vf_aktif('rife') end

local function rife_kapa()
    if vf_aktif('rife') then mp.commandv('vf', 'remove', '@rife') end
    if vf_aktif('rifefmt') then mp.commandv('vf', 'remove', '@rifefmt') end
end

-- force=true ignores the thresholds (the user asked for it deliberately)
local function rife_ac(zorla)
    local ok, sebep = rife_karar()
    if not ok and not zorla then
        rife_kapa()
        msg(sebep)
        return false, sebep
    end
    rife_kapa()
    -- For 10-bit and deeper sources, preserve depth at the bridge INPUT: mpv
    -- hands VapourSynth 8-bit by default (measured). 12-bit+ is raised to
    -- 10-bit as well; the bridge accepting 12-bit has not been verified.
    if kaynak_bit_derinligi() > 8 then
        mp.commandv('vf', 'add', '@rifefmt:format=yuv420p10')
    end
    mp.commandv('vf', 'add', '@rife:vapoursynth=~~/rife.vpy')
    return true, nil
end

-- Rebuild an active RIFE filter after a settings change, so the .vpy re-reads the conf
local function rife_yenile()
    if rife_acik_mi() then rife_kapa(); rife_ac(true) end
end

-- ============================================================
--  REAL STATE VERIFICATION (vo-passes)
-- ============================================================
local function pass_metni()
    local p = mp.get_property_native('vo-passes')
    if not p or not p.fresh or #p.fresh == 0 then return nil end
    local t = {}
    for _, ps in ipairs(p.fresh) do t[#t + 1] = tostring(ps.desc) end
    return table.concat(t, '\n')
end

-- true = running, false = failed to load, nil = unknown (no render / paused)
local function imza_dogrula(imza)
    if not imza then return nil end
    local metin = pass_metni()
    if not metin then return nil end
    return metin:find(imza) ~= nil
end

-- ============================================================
--  VIDEO QUALITY
-- ============================================================
local S = '~~/shaders/'
-- Official Anime4K Mode A is 6 passes. (This used to load 3 shaders and call it "Mode A".)
local Z_A  = { 'Anime4K_Clamp_Highlights', 'Anime4K_Restore_CNN_VL', 'Anime4K_Upscale_CNN_x2_VL',
               'Anime4K_AutoDownscalePre_x2', 'Anime4K_AutoDownscalePre_x4', 'Anime4K_Upscale_CNN_x2_M' }
local Z_AA = { 'Anime4K_Clamp_Highlights', 'Anime4K_Restore_CNN_VL', 'Anime4K_Upscale_CNN_x2_VL',
               'Anime4K_Restore_CNN_M', 'Anime4K_AutoDownscalePre_x2', 'Anime4K_AutoDownscalePre_x4',
               'Anime4K_Upscale_CNN_x2_M' }
local function arti(t, ek)
    local out = {}
    for _, v in ipairs(t) do out[#out + 1] = v end
    out[#out + 1] = ek
    return out
end

-- SCALER RULE: a chain may contain only ONE scaler family.
-- CAS is a scaler (it resizes LUMA to output size) and invalidates Anime4K's
-- upscale conditions -> Anime4K would end up silently disabled.
-- Sharpening uses Deblur_DoG instead: MAIN hook, does not resize, runs at the
-- end of the chain and leaves Anime4K's passes untouched (measured).
local profiller = {
    { ad = 'Anime4K Mode A (HQ)',          tus = 'CTRL+1', chain = Z_A,
      imza = 'Upscale%-CNN%-x2%-%(VL%)' },
    { ad = 'Anime4K Mode A+A (HQ)',        tus = 'CTRL+2', chain = Z_AA,
      imza = 'Restore%-CNN%-%(M%)' },
    { ad = 'Anime4K A+A + Sharpening', tus = 'CTRL+3', chain = arti(Z_AA, 'Anime4K_Deblur_DoG'),
      imza = 'Deblur%-DoG' },
    { ad = 'Anime4K A+A + RIFE',           tus = 'CTRL+4', chain = Z_AA, rife = true,
      imza = 'Restore%-CNN%-%(M%)' },
    { ad = 'FSRCNNX Light (general content)', tus = 'CTRL+5', mpv_profil = 'fsrcnnx-light',
      chain = { 'FSRCNNX_x2_8-0-4-1', 'KrigBilateral' }, imza = 'Krig' },
    { ad = 'AMD CAS (light, standalone)',  tus = 'CTRL+6', chain = { 'CAS-scaled' },
      imza = 'FidelityFX' },
}

local function chain_str(chain)
    local out = {}
    for _, n in ipairs(chain) do out[#out + 1] = S .. n .. '.glsl' end
    return table.concat(out, ';')
end
local function chain_key(chain) return table.concat(chain, '|') end
local function aktif_shaderlar()
    local out = {}
    for _, s in ipairs(mp.get_property_native('glsl-shaders', {})) do
        out[#out + 1] = s:match('([^/\\]+)%.glsl$') or s
    end
    return table.concat(out, '|')
end

local function goruntu_menu()
    local su_an, rife = aktif_shaderlar(), rife_acik_mi()
    local a = rife_ayar()
    local items = {}
    for i, p in ipairs(profiller) do
        local secili = (chain_key(p.chain) == su_an and (p.rife or false) == rife)
        local ipucu = p.tus
        if secili then
            local d = imza_dogrula(p.imza)
            if d == false then ipucu = p.tus .. '  FAILED TO LOAD'
            elseif d == true then ipucu = p.tus .. '  ✓' end
        end
        items[#items + 1] = { title = p.ad, hint = ipucu, active = secili, keep_open = true,
                              value = 'script-message panel-goruntu-sec ' .. i }
    end
    -- RIFE status: spell out what will happen for this file
    local uygun, sebep = rife_karar()
    local rife_ipucu
    if rife then
        rife_ipucu = string.format('%dx · %s', a.multiplier, a.mode)
    elseif not uygun then
        rife_ipucu = 'not suitable for this file'
    else
        rife_ipucu = 'CTRL+9'
    end
    items[#items + 1] = { title = 'RIFE Frame Interpolation', hint = rife_ipucu, active = rife,
                          keep_open = true, value = 'script-message panel-goruntu-rife' }
    if not uygun and sebep then
        items[#items + 1] = { title = sebep, italic = true, muted = true, selectable = false,
                              value = 'ignore' }
    end
    items[#items + 1] = { title = 'RIFE Settings...', value = 'script-message panel-rife' }
    items[#items + 1] = { title = 'Deband (toggle)', hint = 'h', keep_open = true,
                          active = mp.get_property_native('deband', false),
                          value = 'script-message panel-goruntu-deband' }
    items[#items + 1] = { title = 'Deband Strength (light/medium/strong)', hint = 'k', keep_open = true,
                          value = 'script-message panel-goruntu-deband-kademe' }
    items[#items + 1] = { title = 'Interpolation / Judder Removal', keep_open = true,
                          active = mp.get_property_native('interpolation', false),
                          value = 'script-message panel-goruntu-interp' }
    items[#items + 1] = { title = 'Turn Everything Off', hint = 'CTRL+0', italic = true, keep_open = true,
                          active = (su_an == '' and not rife),
                          value = 'script-message panel-goruntu-kapat' }
    return { type = 'panel_goruntu', title = 'Video Quality', keep_open = true, items = items }
end

local function profil_uygula(i)
    local p = profiller[tonumber(i)]
    if not p then return end
    if p.mpv_profil then
        mp.commandv('change-list', 'glsl-shaders', 'clr', '')
        mp.commandv('apply-profile', p.mpv_profil)
    else
        -- SYMMETRY: restore scaler defaults first, then build the chain
        mp.commandv('apply-profile', 'scaler-defaults')
        mp.commandv('change-list', 'glsl-shaders', 'set', chain_str(p.chain))
    end
    if p.rife then rife_ac(false) else rife_kapa() end
    msg(p.ad)
end

mp.register_script_message('panel-goruntu', function() ac(goruntu_menu()) end)
mp.register_script_message('panel-goruntu-sec', function(i)
    profil_uygula(i)
    mp.add_timeout(0.35, function() guncelle(goruntu_menu()) end)  -- pass listesi dolsun
end)
mp.register_script_message('panel-goruntu-rife', function()
    if rife_acik_mi() then rife_kapa(); msg('RIFE off')
    else
        local ok, sebep = rife_ac(false)
        if ok then msg('RIFE 2x frame interpolation on') end
    end
    guncelle(goruntu_menu())
end)
-- Enable while deliberately ignoring the thresholds ("Enable anyway" in the menu)
mp.register_script_message('panel-goruntu-rife-zorla', function()
    rife_ac(true); msg('RIFE forced (thresholds ignored)')
    guncelle(goruntu_menu())
end)
mp.register_script_message('panel-goruntu-deband', function()
    mp.commandv('cycle', 'deband'); guncelle(goruntu_menu())
end)
mp.register_script_message('panel-goruntu-deband-kademe', function()
    mp.command('no-osd set deband yes ; cycle-values deband-iterations "2" "4" "6" ; ' ..
               'cycle-values deband-threshold "32" "48" "64" ; cycle-values deband-range "16" "24" "32"')
    local sev = { ['2'] = 'light', ['4'] = 'medium', ['6'] = 'strong' }
    msg('Deband: %s', sev[mp.get_property('deband-iterations', '?')] or '?')
    guncelle(goruntu_menu())
end)
mp.register_script_message('panel-goruntu-interp', function()
    mp.commandv('cycle', 'interpolation'); guncelle(goruntu_menu())
end)
mp.register_script_message('panel-goruntu-kapat', function()
    mp.commandv('apply-profile', 'scaler-defaults')
    mp.commandv('change-list', 'glsl-shaders', 'clr', '')
    rife_kapa()   -- yalniz kendi etiketlerimiz; kullanicinin filtreleri kalir
    msg("Shaders and RIFE turned off")
    guncelle(goruntu_menu())
end)

-- ============================================================
--  RIFE SETTINGS (resolution policy / multiplier / thresholds)
-- ============================================================
local MODLAR = {
    { 'performance', 'Performance - downscale above %dp',
      "Fastest. 1080p is processed at %dp; shaders upscale it back." },
    { 'balanced',    'Balanced - full resolution up to 1080p',
      "No detail loss at 1080p, ~2x GPU. Above 1080p is downscaled." },
    { 'quality',     'Quality - never downscale',
      'Full detail at any resolution. Needs a strong GPU.' },
}

local function rife_menu()
    local a = rife_ayar()
    local h = mp.get_property_number('video-params/h')
    local fps = mp.get_property_number('container-fps')
    local uygun, sebep = rife_karar()
    local items = {}

    -- What happens to this file: make the trade-off visible
    local durum
    if not uygun then durum = sebep
    elseif h then
        local calisma = h
        if (a.mode == 'performance' and h > a.work_height)
           or (a.mode == 'balanced' and h > 1080) then calisma = a.work_height end
        durum = string.format("%dp / %.4g fps -> processed at %dp, %dx", h, fps or 0, calisma, a.multiplier)
    else
        durum = 'no file loaded'
    end
    items[#items + 1] = { title = durum, italic = true, muted = true, selectable = false, value = 'ignore' }

    for _, m in ipairs(MODLAR) do
        items[#items + 1] = { title = string.format(m[2], a.work_height),
                              hint = string.format(m[3], a.work_height),
                              active = (a.mode == m[1]), keep_open = true,
                              value = 'script-message panel-rife-mod ' .. m[1] }
    end
    for _, c in ipairs({ 2, 3, 4 }) do
        items[#items + 1] = { title = 'Multiplier: ' .. c .. 'x',
                              hint = (c == 4 and '~2x GPU load' or (c == 3 and '~1.5x GPU load' or 'default')),
                              active = (a.multiplier == c), keep_open = true,
                              value = 'script-message panel-rife-multiplier ' .. c }
    end
    for _, y in ipairs({ 480, 720, 1080 }) do
        items[#items + 1] = { title = 'Working height: ' .. y .. 'p',
                              active = (a.work_height == y), keep_open = true,
                              value = 'script-message panel-rife-calisma ' .. y }
    end
    items[#items + 1] = { title = 'RIFE off at 4K and above',
                          hint = a.skip_above_height > 0 and (a.skip_above_height .. 'p and above') or 'off',
                          active = (a.skip_above_height > 0), keep_open = true,
                          value = 'script-message panel-rife-atlama' }
    items[#items + 1] = { title = "RIFE off at high fps",
                          hint = a.fps_threshold > 0 and (a.fps_threshold .. ' fps and above') or 'off',
                          active = (a.fps_threshold > 0), keep_open = true,
                          value = 'script-message panel-rife-fps' }
    if not uygun then
        items[#items + 1] = { title = 'Enable anyway (ignore thresholds)', italic = true,
                              value = 'script-message panel-goruntu-rife-zorla' }
    end
    return { type = 'panel_rife', title = 'RIFE Settings', keep_open = true, items = items }
end

mp.register_script_message('panel-rife', function() ac(rife_menu()) end)
local function rife_ayarla(anahtar, deger)
    rife_ayar_yaz(anahtar, deger)
    rife_yenile()
    guncelle(rife_menu())
end
mp.register_script_message('panel-rife-mod', function(v) rife_ayarla('mode', v) end)
mp.register_script_message('panel-rife-multiplier', function(v) rife_ayarla('multiplier', tonumber(v) or 2) end)
mp.register_script_message('panel-rife-calisma', function(v) rife_ayarla('work_height', tonumber(v) or 720) end)
mp.register_script_message('panel-rife-atlama', function()
    local a = rife_ayar()
    rife_ayarla('skip_above_height', a.skip_above_height > 0 and 0 or 1440)
end)
mp.register_script_message('panel-rife-fps', function()
    local a = rife_ayar()
    rife_ayarla('fps_threshold', a.fps_threshold > 0 and 0 or 40)
end)

-- The RIFE decision is re-evaluated on file change: what suited the previous
-- file may not suit the next one (switching to 60fps, for example).
mp.register_event('file-loaded', function()
    if rife_acik_mi() then
        local uygun, sebep = rife_karar()
        if not uygun then rife_kapa(); msg(sebep) end
    end
end)

-- ============================================================
--  VIDEO
-- ============================================================
local aspectler = {
    { -1,      'Original' },
    { 16 / 9,  '16:9' },
    { 4 / 3,   '4:3' },
    { 2.35,    '2.35:1 (cinemascope)' },
    { 1.85,    '1.85:1' },
}

local function video_menu()
    local asp = mp.get_property_number('video-aspect-override', -1)
    local zoom = mp.get_property_number('video-zoom', 0)
    local rot = mp.get_property_number('video-rotate', 0)
    local items = {}
    for i, a in ipairs(aspectler) do
        items[#items + 1] = { title = 'Aspect: ' .. a[2], keep_open = true,
                              active = math.abs(asp - a[1]) < 0.01,
                              value = 'script-message panel-video-aspect ' .. i }
    end
    items[#items + 1] = { title = 'Zoom  +', hint = string.format('%.1f', zoom), keep_open = true,
                          value = 'script-message panel-video-zoom 0.1' }
    items[#items + 1] = { title = 'Zoom  −', hint = string.format('%.1f', zoom), keep_open = true,
                          value = 'script-message panel-video-zoom -0.1' }
    items[#items + 1] = { title = 'Reset View (zoom/pan)', italic = true, keep_open = true,
                          value = 'script-message panel-video-sifirla' }
    items[#items + 1] = { title = 'Rotate 90 deg', hint = rot .. '°', keep_open = true,
                          active = rot ~= 0, value = 'script-message panel-video-dondur' }
    items[#items + 1] = { title = 'Mirror (flip horizontal)', keep_open = true, active = vf_aktif('ayna'),
                          value = 'script-message panel-video-vf ayna hflip' }
    items[#items + 1] = { title = 'Flip Vertical', keep_open = true, active = vf_aktif('ters'),
                          value = 'script-message panel-video-vf ters vflip' }
    items[#items + 1] = { title = 'Deinterlace', hint = tostring(mp.get_property('deinterlace')),
                          keep_open = true, active = mp.get_property('deinterlace') ~= 'no',
                          value = 'script-message panel-video-deint' }
    items[#items + 1] = { title = 'Color Matrix: Force BT.709', hint = 'K', keep_open = true,
                          active = vf_aktif('bt709'),
                          value = 'script-message panel-video-matris bt709' }
    items[#items + 1] = { title = 'Color Matrix: Force BT.601', hint = 'L', keep_open = true,
                          active = vf_aktif('bt601'),
                          value = 'script-message panel-video-matris bt601' }
    items[#items + 1] = { title = "Lock to 23.976 fps", hint = 'M', keep_open = true,
                          active = vf_aktif('film'),
                          value = 'script-message panel-video-vf film fps=23.976:round=near' }
    items[#items + 1] = { title = 'Hardware Decoding (H/W)', keep_open = true,
                          active = (mp.get_property('hwdec', 'no') ~= 'no'),
                          hint = tostring(mp.get_property('hwdec-current') or 'software'),
                          value = 'script-message panel-video-hwdec' }
    items[#items + 1] = { title = 'HDR / Tone Mapping...', value = 'script-message panel-hdr' }
    items[#items + 1] = { title = 'Color Adjustments...', value = 'script-message panel-renk' }
    items[#items + 1] = { title = 'Fine Tuning (Soften/Sharpen/Deblock)...', value = 'script-message panel-ince' }
    return { type = 'panel_video', title = 'Video', keep_open = true, items = items }
end

mp.register_script_message('panel-video', function() ac(video_menu()) end)
mp.register_script_message('panel-video-aspect', function(i)
    local a = aspectler[tonumber(i)]
    if a then mp.set_property_number('video-aspect-override', a[1]) end
    guncelle(video_menu())
end)
mp.register_script_message('panel-video-zoom', function(d)
    mp.set_property_number('video-zoom', mp.get_property_number('video-zoom', 0) + tonumber(d))
    guncelle(video_menu())
end)
mp.register_script_message('panel-video-sifirla', function()
    mp.set_property_number('video-zoom', 0)
    mp.set_property_number('video-pan-x', 0)
    mp.set_property_number('video-pan-y', 0)
    guncelle(video_menu())
end)
mp.register_script_message('panel-video-dondur', function()
    mp.command('cycle-values video-rotate "90" "180" "270" "0"')
    guncelle(video_menu())
end)
mp.register_script_message('panel-video-deint', function()
    mp.command('cycle-values deinterlace "auto" "yes" "no"')
    guncelle(video_menu())
end)
mp.register_script_message('panel-video-vf', function(label, filtre)
    mp.commandv('vf', 'toggle', '@' .. label .. ':' .. filtre)
    guncelle(video_menu())
end)
-- BT.709 and BT.601 are mutually exclusive: never both in the chain at once
mp.register_script_message('panel-video-matris', function(hangi)
    local digeri = (hangi == 'bt709') and 'bt601' or 'bt709'
    if vf_aktif(digeri) then mp.commandv('vf', 'remove', '@' .. digeri) end
    local deger = (hangi == 'bt709') and 'bt.709' or 'bt.601'
    mp.commandv('vf', 'toggle', '@' .. hangi .. ':format=colormatrix=' .. deger)
    guncelle(video_menu())
end)
mp.register_script_message('panel-video-hwdec', function()
    local yeni = mp.get_property('hwdec', 'no') == 'no' and 'auto-copy' or 'no'
    mp.set_property('hwdec', yeni)
    msg(yeni == 'no' and 'Software decoding' or 'Hardware decoding (auto-copy)')
    guncelle(video_menu())
end)

-- ============================================================
--  HDR / TONE MAPPING
-- ============================================================
local ton_yontemleri = {
    { 'auto',    'Auto (recommended)' },
    { 'bt.2390', 'BT.2390 (standard, balanced)' },
    { 'spline',  'Spline (soft)' },
    { 'hable',   'Hable (filmic, keeps shadows)' },
    { 'reinhard','Reinhard (keeps highlights)' },
    { 'mobius',  'Mobius (keeps colors vivid)' },
}

local function hdr_menu()
    local cur = mp.get_property('tone-mapping', 'auto')
    local items = {}
    for _, y in ipairs(ton_yontemleri) do
        items[#items + 1] = { title = 'Method: ' .. y[2], active = (cur == y[1]), keep_open = true,
                              value = 'script-message panel-hdr-yontem ' .. y[1] }
    end
    items[#items + 1] = { title = 'Dynamic Peak Detection', keep_open = true,
                          hint = tostring(mp.get_property('hdr-compute-peak')),
                          active = mp.get_property('hdr-compute-peak') ~= 'no',
                          value = 'script-message panel-hdr-peak' }
    items[#items + 1] = { title = "Pass HDR to Display (if HDR screen)", keep_open = true,
                          active = mp.get_property('target-colorspace-hint') == 'yes',
                          value = 'script-message panel-hdr-hint' }
    items[#items + 1] = { title = 'Note: only affects HDR content', italic = true, muted = true,
                          selectable = false, value = 'ignore' }
    return { type = 'panel_hdr', title = 'HDR / Tone Mapping', keep_open = true, items = items }
end

mp.register_script_message('panel-hdr', function() ac(hdr_menu()) end)
mp.register_script_message('panel-hdr-yontem', function(y)
    mp.set_property('tone-mapping', y); guncelle(hdr_menu())
end)
mp.register_script_message('panel-hdr-peak', function()
    mp.set_property('hdr-compute-peak', mp.get_property('hdr-compute-peak') == 'no' and 'auto' or 'no')
    guncelle(hdr_menu())
end)
mp.register_script_message('panel-hdr-hint', function()
    mp.set_property('target-colorspace-hint',
        mp.get_property('target-colorspace-hint') == 'yes' and 'no' or 'yes')
    guncelle(hdr_menu())
end)

-- ============================================================
--  AUDIO CHANNELS / HEADPHONES
-- ============================================================
local kanal_duzenleri = {
    { 'auto-safe', 'Auto (as-is, safe)' },
    { 'mono',      '1.0 Mono' },
    { 'stereo',    '2.0 Stereo' },
    { '5.1',       '5.1 Channels' },
    { '7.1',       '7.1 Channels' },
}
local kulaklik_filtreleri = {
    { 'crossfeed', 'Headphones: Crossfeed (natural stage)',
      'lavfi=[aformat=channel_layouts=stereo,crossfeed=strength=0.5]' },
    { 'genis',     'Headphones: Stereo Widening',
      'lavfi=[aformat=channel_layouts=stereo,stereowiden=delay=18:feedback=0.35:crossfeed=0.35]' },
    { 'upmix',     'Pro Logic II Upmix (stereo → 5.1)',
      'lavfi=[aformat=channel_layouts=stereo,surround]' },
}

local function kanal_menu()
    local cur = mp.get_property('audio-channels', 'auto-safe')
    local items = {}
    for _, k in ipairs(kanal_duzenleri) do
        items[#items + 1] = { title = k[2], active = (cur == k[1]), keep_open = true,
                              value = 'script-message panel-kanal-sec ' .. k[1] }
    end
    for _, f in ipairs(kulaklik_filtreleri) do
        items[#items + 1] = { title = f[2], active = af_aktif(f[1]), keep_open = true,
                              value = 'script-message panel-kanal-af ' .. f[1] }
    end
    return { type = 'panel_kanal', title = 'Audio Channels / Headphones', keep_open = true, items = items }
end

mp.register_script_message('panel-kanal', function() ac(kanal_menu()) end)
mp.register_script_message('panel-kanal-sec', function(k)
    mp.set_property('audio-channels', k)
    mp.command('ao-reload')
    guncelle(kanal_menu())
end)
mp.register_script_message('panel-kanal-af', function(id)
    for _, f in ipairs(kulaklik_filtreleri) do
        if f[1] == id then mp.commandv('af', 'toggle', '@' .. f[1] .. ':' .. f[3]) end
    end
    guncelle(kanal_menu())
end)

-- ============================================================
--  COLOR ADJUSTMENTS
-- ============================================================
local renk_props = {
    { 'brightness', 'Brightness' },
    { 'contrast',   'Contrast' },
    { 'saturation', 'Saturation' },
    { 'gamma',      'Gamma' },
    { 'hue',        'Hue' },
}

local function renk_menu()
    local items = {}
    for _, p in ipairs(renk_props) do
        local val = mp.get_property_number(p[1], 0)
        items[#items + 1] = { title = p[2] .. '  −', hint = tostring(val),
                              value = 'script-message panel-renk-adj ' .. p[1] .. ' -2', keep_open = true }
        items[#items + 1] = { title = p[2] .. '  +', hint = tostring(val),
                              value = 'script-message panel-renk-adj ' .. p[1] .. ' 2', keep_open = true }
    end
    items[#items + 1] = { title = 'Reset All', italic = true,
                          value = 'script-message panel-renk-adj sifirla 0', keep_open = true }
    return { type = 'panel_renk', title = 'Color Adjustments', keep_open = true, items = items }
end

mp.register_script_message('panel-renk', function() ac(renk_menu()) end)
mp.register_script_message('panel-renk-adj', function(prop, delta)
    if prop == 'sifirla' then
        for _, p in ipairs(renk_props) do mp.set_property_number(p[1], 0) end
    else
        local v = mp.get_property_number(prop, 0) + tonumber(delta)
        mp.set_property_number(prop, math.max(-100, math.min(100, v)))
    end
    guncelle(renk_menu())
end)

-- ============================================================
--  EQUALIZER
-- ============================================================
local eq_presets = {
    { 'kapali',   'Off (flat)',        nil },
    { 'bas',      'Bass Boost',       '1b=4:2b=3.5:3b=2.5:4b=1.8' },
    { 'tiz',      'Treble Boost',       '14b=2:15b=2.5:16b=3:17b=3:18b=3' },
    { 'vokal',    'Vocal Clarity',     '6b=1.6:7b=2:8b=2.2:9b=2:10b=1.6' },
    { 'loudness', 'Loudness (V curve)', '1b=3:2b=2.5:3b=1.8:16b=2:17b=2.5:18b=2.5' },
    { 'gece',     'Night (reduced bass)',    '1b=0.3:2b=0.4:3b=0.6' },
}

-- superequalizer has 18 fixed bands; the UI groups them in pairs into 9.
-- Gains are stored in dB and handed to the filter as a factor (0 dB = 1.0).
local EQ_BANDS = {
    { '65 Hz',  { 1, 2 } },
    { '130 Hz', { 3, 4 } },
    { '260 Hz', { 5, 6 } },
    { '520 Hz', { 7, 8 } },
    { '1 kHz',  { 9, 10 } },
    { '2 kHz',  { 11, 12 } },
    { '4 kHz',  { 13, 14 } },
    { '8 kHz',  { 15, 16 } },
    { '16 kHz', { 17, 18 } },
}
local EQ_ADIM, EQ_SINIR = 2, 12          -- tiklama basina dB, +/- sinir
local EQ_CONF = mp.command_native({ 'expand-path', '~~/script-opts/eq.conf' })
local eq_gain = {}
for i = 1, #EQ_BANDS do eq_gain[i] = 0 end
local eq_applied = 'kapali'              -- son uyguladigimiz kimlik

local function eq_load()
    local f = io.open(EQ_CONF, 'r')
    if not f then return end
    for satir in f:lines() do
        local v = satir:match('^%s*bands%s*=%s*(.+)$')
        if v then
            local i = 0
            for n in v:gmatch('%-?%d+%.?%d*') do
                i = i + 1
                if eq_gain[i] then eq_gain[i] = tonumber(n) or 0 end
            end
        end
    end
    f:close()
end
eq_load()

local function eq_save()
    local t = {}
    for i = 1, #EQ_BANDS do t[#t + 1] = string.format('%.0f', eq_gain[i]) end
    local w = io.open(EQ_CONF, 'w')
    if w then
        w:write('# Custom equalizer - gain in dB per band\n')
        w:write('# 65 / 130 / 260 / 520 Hz, 1 / 2 / 4 / 8 / 16 kHz\n')
        w:write('bands=' .. table.concat(t, ',') .. '\n')
        w:close()
    end
end

local function eq_custom_str()
    local p = {}
    for i, b in ipairs(EQ_BANDS) do
        local kat = 10 ^ (eq_gain[i] / 20)
        if kat > 20 then kat = 20 elseif kat < 0 then kat = 0 end
        for _, n in ipairs(b[2]) do p[#p + 1] = string.format('%db=%.3f', n, kat) end
    end
    return table.concat(p, ':')
end

local function eq_apply(id)
    if af_aktif('eq') then mp.commandv('af', 'remove', '@eq') end
    if id == 'custom' then
        mp.commandv('af', 'add', '@eq:superequalizer=' .. eq_custom_str())
    else
        for _, p in ipairs(eq_presets) do
            if p[1] == id and p[3] then
                mp.commandv('af', 'add', '@eq:superequalizer=' .. p[3])
            end
        end
    end
    eq_applied = id
end

-- On/off comes from the REAL af chain; which preset it is comes from what we
-- applied last (anything added externally counts as 'custom').
local function eq_aktif_id()
    if not af_aktif('eq') then eq_applied = 'kapali'; return 'kapali' end
    if eq_applied == 'kapali' then return 'custom' end
    return eq_applied
end

local function eq_menu()
    local cur = eq_aktif_id()
    local items = {}
    for _, p in ipairs(eq_presets) do
        items[#items + 1] = { title = p[2], active = (cur == p[1]), keep_open = true,
                              value = 'script-message panel-eq-sec ' .. p[1] }
    end
    items[#items + 1] = { title = 'Custom Equalizer...', active = (cur == 'custom'),
                          hint = '9 bands', value = 'script-message panel-eq-custom' }
    return { type = 'panel_eq', title = 'Equalizer', keep_open = true, items = items }
end

local function eq_custom_menu()
    local acik = (eq_aktif_id() == 'custom')
    local items = {}
    items[#items + 1] = { title = acik and 'Custom EQ is ON' or 'Turn Custom EQ on',
                          active = acik, keep_open = true,
                          value = 'script-message panel-eq-custom-on' }
    for i, b in ipairs(EQ_BANDS) do
        local h = string.format('%+d dB', math.floor(eq_gain[i] + 0.5))
        items[#items + 1] = { title = b[1] .. '   +', hint = h, keep_open = true,
                              value = 'script-message panel-eq-band ' .. i .. ' ' .. EQ_ADIM }
        items[#items + 1] = { title = b[1] .. '   -', hint = h, keep_open = true,
                              value = 'script-message panel-eq-band ' .. i .. ' -' .. EQ_ADIM }
    end
    items[#items + 1] = { title = 'Flatten (all bands to 0 dB)', italic = true, keep_open = true,
                          value = 'script-message panel-eq-flat' }
    return { type = 'panel_eq_custom', title = 'Custom Equalizer', keep_open = true, items = items }
end

mp.register_script_message('panel-eq', function() ac(eq_menu()) end)
mp.register_script_message('panel-eq-sec', function(id)
    eq_apply(id)
    guncelle(eq_menu())
end)
mp.register_script_message('panel-eq-custom', function() ac(eq_custom_menu()) end)
mp.register_script_message('panel-eq-custom-on', function()
    if eq_aktif_id() == 'custom' then
        if af_aktif('eq') then mp.commandv('af', 'remove', '@eq') end
        eq_applied = 'kapali'
    else
        eq_apply('custom')
    end
    guncelle(eq_custom_menu())
end)
mp.register_script_message('panel-eq-band', function(i, d)
    i, d = tonumber(i), tonumber(d)
    if not i or not eq_gain[i] then return end
    eq_gain[i] = math.max(-EQ_SINIR, math.min(EQ_SINIR, eq_gain[i] + d))
    eq_save()
    if eq_aktif_id() == 'custom' then eq_apply('custom') end
    guncelle(eq_custom_menu())
end)
mp.register_script_message('panel-eq-flat', function()
    for i = 1, #EQ_BANDS do eq_gain[i] = 0 end
    eq_save()
    if eq_aktif_id() == 'custom' then eq_apply('custom') end
    guncelle(eq_custom_menu())
end)

-- ============================================================
--  FINE TUNING: soften / sharpen / deblock
-- ============================================================
local ince_filtreler = {
    { 'sharp',   'Sharpen', 'lavfi=[unsharp=la=1.0]' },
    { 'soft',    'Soften',       'lavfi=[unsharp=la=-0.8]' },
    { 'deblock', 'Deblock',   'lavfi=[deblock=filter=strong:block=8]' },
}

local function ince_menu()
    local items = {}
    for _, f in ipairs(ince_filtreler) do
        items[#items + 1] = { title = f[2], active = vf_aktif(f[1]),
                              value = 'script-message panel-ince-sec ' .. f[1], keep_open = true }
    end
    return { type = 'panel_ince', title = 'Fine Tuning', keep_open = true, items = items }
end

mp.register_script_message('panel-ince', function() ac(ince_menu()) end)
mp.register_script_message('panel-ince-sec', function(id)
    for _, f in ipairs(ince_filtreler) do
        if f[1] == id then mp.commandv('vf', 'toggle', '@' .. f[1] .. ':' .. f[3]) end
    end
    guncelle(ince_menu())
end)

-- ============================================================
--  COLORS (LUT tree) - built by scanning the luts/ folder
--  No hardcoded list: only .cube files the user actually has are listed, so a
--  missing LUT can never show up as "available" in the menu.
-- ============================================================
local LUT_DIZIN = mp.command_native({ 'expand-path', '~~/luts' })

-- Build a readable label: prefer the TITLE line inside the .cube, otherwise
-- prettify the file name (short tokens are upper-cased).
local function lut_etiket(dosya)
    local f = io.open(LUT_DIZIN .. '/' .. dosya .. '.cube', 'r')
    if f then
        local bas = f:read(400) or ''
        f:close()
        local t = bas:match('TITLE%s+"([^"]+)"')
        if t and #t > 0 then return t end
    end
    local ad = dosya:gsub('%-', ' ')
    ad = ad:gsub('(%a[%w]*)', function(k)
        if #k <= 3 and k:match('^%a+$') then return k:upper() end
        return k:sub(1, 1):upper() .. k:sub(2)
    end)
    return ad
end

local function lut_listesi()
    local hepsi = {}
    local dosyalar = utils.readdir(LUT_DIZIN, 'files') or {}
    for _, d in ipairs(dosyalar) do
        local ad = d:match('^(.+)%.cube$')
        if ad then hepsi[#hepsi + 1] = ad end
    end
    table.sort(hepsi)
    return hepsi
end

local function aktif_lut()
    local cur = mp.get_property('lut', '')
    return cur:match('([^/\\]+)%.cube$') or ''
end

local BASIT = {
    ['anime-boost'] = 'Anime Boost', ['canli'] = 'Vivid',
    ['sinematik'] = 'Cinematic (teal-orange)', ['sicak'] = 'Warm',
    ['soguk'] = 'Cool', ['pastel'] = 'Pastel (matte)', ['sepya'] = 'Sepia',
    ['siyah-beyaz'] = 'Black and White', ['gece'] = 'Night (low blue)',
}

local function renkler_menu()
    local aktif = aktif_lut()
    local ust, speedlooks, basit = {}, {}, {}
    for _, ad in ipairs(lut_listesi()) do
        local oge = { title = BASIT[ad] or lut_etiket(ad), active = (ad == aktif),
                      value = 'script-message panel-lut-sec ' .. ad, keep_open = true }
        if BASIT[ad] then basit[#basit + 1] = oge
        elseif ad:match('^sl%-') then speedlooks[#speedlooks + 1] = oge
        else ust[#ust + 1] = oge end
    end
    local items = ust
    if #speedlooks > 0 then items[#items + 1] = { title = 'SpeedLooks', items = speedlooks } end
    if #basit > 0 then items[#items + 1] = { title = 'Simple Modes', items = basit } end
    if #items == 0 then
        items[#items + 1] = { title = 'No LUT files in luts/', italic = true, muted = true,
                              selectable = false, value = 'ignore' }
    end
    items[#items + 1] = { title = 'Off', italic = true, active = (aktif == ''),
                          value = 'script-message panel-lut-sec -', keep_open = true }
    return { type = 'panel_renkler', title = 'Colors', keep_open = true, items = items }
end

mp.register_script_message('panel-renkler', function() ac(renkler_menu()) end)
mp.register_script_message('panel-lut-sec', function(dosya)
    if dosya == '-' then
        mp.set_property('lut', '')
        msg('Color mode off')
    else
        local yol = LUT_DIZIN .. '/' .. dosya .. '.cube'
        if not utils.file_info(yol) then
            msg('LUT file missing: %s.cube', dosya)
        else
            mp.set_property('lut', yol)
            msg('Color: %s', BASIT[dosya] or dosya)
        end
    end
    guncelle(renkler_menu())
end)

-- ============================================================
--  SECONDARY SUBTITLE
-- ============================================================
local function sub2_menu()
    local sec = mp.get_property_native('secondary-sid')
    local birincil = mp.get_property_native('sid')
    local items = {}
    for _, t in ipairs(mp.get_property_native('track-list', {})) do
        if t.type == 'sub' then
            local ad = string.format('%s%s%s', t.title or ('Subtitle ' .. t.id),
                t.lang and ('  [' .. t.lang .. ']') or '',
                t.id == birincil and '  (primary)' or '')
            items[#items + 1] = { title = ad, active = (t.id == sec),
                                  value = 'script-message panel-sub2-sec ' .. t.id, keep_open = true }
        end
    end
    if #items == 0 then
        items[#items + 1] = { title = 'No subtitle track', italic = true, muted = true, value = 'ignore' }
    end
    items[#items + 1] = { title = 'Off', italic = true, active = (sec == nil),
                          value = 'script-message panel-sub2-sec -', keep_open = true }
    return { type = 'panel_sub2', title = 'Secondary Subtitle (top)', keep_open = true, items = items }
end

mp.register_script_message('panel-sub2', function() ac(sub2_menu()) end)
mp.register_script_message('panel-sub2-sec', function(id)
    if id == '-' then
        mp.set_property('secondary-sid', 'no')
    else
        mp.set_property('secondary-sid', id)
        mp.set_property('secondary-sub-visibility', 'yes')
    end
    guncelle(sub2_menu())
end)
