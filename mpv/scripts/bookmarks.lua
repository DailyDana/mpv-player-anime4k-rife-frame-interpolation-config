-- bookmarks.lua - PotPlayer-style bookmarks
-- "Save This Moment" stores file + position; picking it from the list reopens
-- that file at that point. Stored in ~~/bookmarks.json

local mp = require 'mp'
local utils = require 'mp.utils'

local DOSYA = mp.command_native({ 'expand-path', '~~/bookmarks.json' })
local bekleyen_konum = nil

local function yukle()
    local f = io.open(DOSYA, 'r')
    if not f then return {} end
    local ok, data = pcall(utils.parse_json, f:read('*a'))
    f:close()
    return (ok and type(data) == 'table') and data or {}
end

local function kaydet(liste)
    local f = io.open(DOSYA, 'w')
    if not f then return end
    f:write(utils.format_json(liste))
    f:close()
end

local function sure_str(t)
    t = math.floor(t or 0)
    return string.format('%02d:%02d:%02d', t / 3600, (t / 60) % 60, t % 60)
end

local function open_menu(menu)
    mp.commandv('script-message-to', 'uosc', 'open-menu', utils.format_json(menu))
end

mp.register_script_message('yer-imi-ekle', function()
    local path = mp.get_property('path')
    if not path then return end
    local liste = yukle()
    liste[#liste + 1] = {
        path = path,
        time = mp.get_property_number('time-pos', 0),
        title = mp.get_property('media-title', path),
        tarih = os.date('%d.%m.%Y'),
    }
    kaydet(liste)
    mp.osd_message(('Bookmark saved: %s'):format(sure_str(mp.get_property_number('time-pos', 0))), 2)
end)

local function menu_olustur()
    local liste = yukle()
    local items = {}
    for i = #liste, 1, -1 do  -- newest first
        local b = liste[i]
        items[#items + 1] = { title = b.title, hint = sure_str(b.time) .. '  ' .. (b.tarih or ''),
                              value = 'script-message yer-imi-git ' .. i }
    end
    if #liste == 0 then
        items[#items + 1] = { title = 'No bookmarks yet', italic = true, muted = true, value = 'ignore' }
    else
        local sil = {}
        for i = #liste, 1, -1 do
            local b = liste[i]
            sil[#sil + 1] = { title = b.title, hint = sure_str(b.time),
                              value = 'script-message yer-imi-sil ' .. i, keep_open = true }
        end
        sil[#sil + 1] = { title = 'DELETE ALL', bold = true,
                          value = 'script-message yer-imi-sil hepsi' }
        items[#items + 1] = { title = 'Delete...', items = sil }
    end
    return { type = 'yer_imleri', title = 'Bookmarks', items = items }
end

mp.register_script_message('yer-imi-menu', function() open_menu(menu_olustur()) end)

mp.register_script_message('yer-imi-git', function(i)
    local b = yukle()[tonumber(i)]
    if not b then return end
    if mp.get_property('path') == b.path then
        mp.set_property_number('time-pos', b.time)
    else
        bekleyen_konum = b.time
        mp.commandv('loadfile', b.path, 'replace')
    end
end)

mp.register_event('file-loaded', function()
    if bekleyen_konum then
        mp.set_property_number('time-pos', bekleyen_konum)
        bekleyen_konum = nil
    end
end)

mp.register_script_message('yer-imi-sil', function(i)
    if i == 'hepsi' then
        kaydet({})
        mp.osd_message('All bookmarks deleted', 2)
        open_menu(menu_olustur())
        return
    end
    local liste = yukle()
    table.remove(liste, tonumber(i))
    kaydet(liste)
    open_menu(menu_olustur())
end)
