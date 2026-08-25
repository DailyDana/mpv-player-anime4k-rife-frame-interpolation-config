-- clip-cutter.lua - save an A-B clip while watching (via ffmpeg, no re-encode)
-- Menu: Tools > Clip Cutter. Output lands next to the video as "<name>.klip-XX.mp4"
-- Note: fast-copy mode snaps to a keyframe, so the start may be 1-2 s early.

local mp = require 'mp'
local utils = require 'mp.utils'

local A, B = nil, nil

local function ffmpeg_yolu()
    local adaylar = {
        mp.command_native({ 'expand-path', '~~exe_dir/ffmpeg.exe' }),  -- portable package
        'C:\\Program Files (x86)\\MPV Player\\ffmpeg.exe',
    }
    for _, aday in ipairs(adaylar) do
        if aday and utils.file_info(aday) then return aday end
    end
    return 'ffmpeg'  -- last resort: PATH
end

local function sure_str(t)
    t = math.floor(t or 0)
    return string.format('%02d:%02d:%02d', t / 3600, (t / 60) % 60, t % 60)
end

mp.register_script_message('klip-basla', function()
    A = mp.get_property_number('time-pos', 0)
    mp.osd_message('Clip start: ' .. sure_str(A), 2)
end)

mp.register_script_message('klip-bitir', function()
    B = mp.get_property_number('time-pos', 0)
    if A and B <= A then
        mp.osd_message('End cannot be before start.', 2)
        B = nil
        return
    end
    mp.osd_message(('Clip end: %s%s'):format(sure_str(B),
        A and ('  (length ' .. sure_str(B - A) .. ')') or '  - mark the start first'), 2)
end)

mp.register_script_message('klip-kaydet', function()
    if not A or not B then
        mp.osd_message('Mark start and end first (Tools > Clip Cutter)', 3)
        return
    end
    local path = mp.get_property('path')
    if not path or path:match('^https?://') then
        mp.osd_message('Clip cutter works on local files only', 3)
        return
    end
    local klasor, ad = utils.split_path(path)
    local govde = ad:gsub('%.[^.]+$', '')
    local cikti = utils.join_path(klasor,
        string.format('%s.klip-%s-%s.mp4', govde,
            sure_str(A):gsub(':', ''), sure_str(B):gsub(':', '')))
    mp.osd_message('Saving clip...', 60)
    mp.command_native_async({
        name = 'subprocess', playback_only = false, capture_stderr = true,
        args = { ffmpeg_yolu(), '-y', '-ss', tostring(A), '-i', path,
                 '-t', tostring(B - A), '-c', 'copy',
                 '-avoid_negative_ts', 'make_zero', cikti },
    }, function(ok, sonuc)
        if ok and sonuc.status == 0 then
            mp.osd_message('Clip saved: ' .. cikti, 4)
        else
            mp.osd_message('Clip save failed (ffmpeg error - see console)', 4)
            print(sonuc and sonuc.stderr or 'ffmpeg calistirilamadi')
        end
        A, B = nil, nil
    end)
end)
