-- brightness-bar.lua
-- A brightness bar on the left edge, mirroring uosc's volume bar on the right.
-- Appears when the mouse nears the left edge. Wheel = adjust, click/drag = jump
-- to a value, middle click = reset. Colors match the uosc.conf theme.

local mp = require 'mp'
local assdraw = require 'mp.assdraw'

local cfg = {
    zone_w     = 80,   -- mouse detection zone width (px)
    bar_w      = 10,   -- bar thickness (close to uosc volume look)
    hit_w      = 38,   -- clickable area width
    margin_x   = 26,   -- distance from the left edge
    height_pct = 0.42, -- fraction of screen height
    step       = 5,    -- wheel step
    prop       = "brightness",  -- -100..100
    -- ASS colors are in BGR order; converted from the uosc theme:
    fg   = "F65C8B",   -- 8b5cf6 (violet)
    bg   = "2E1E1E",   -- 1e1e2e (dark)
    text = "F4D6CD",   -- cdd6f4
}

local state = { shown = false, dragging = false, mx = -1, my = -1 }
local overlay = mp.create_osd_overlay("ass-events")

local function bar_rect()
    local dim = mp.get_property_native("osd-dimensions")
    if not dim or dim.w == 0 or dim.h == 0 then return nil end
    local h = math.floor(dim.h * cfg.height_pct)
    local y0 = math.floor((dim.h - h) / 2)
    return dim.w, dim.h, cfg.margin_x, y0, cfg.margin_x + cfg.bar_w, y0 + h
end

local function in_zone(x, y)
    local w, h, x0, y0, x1, y1 = bar_rect()
    if not w then return false end
    return x >= 0 and x <= cfg.zone_w and y >= y0 - 60 and y <= y1 + 60
end

local function draw()
    local w, h, x0, y0, x1, y1 = bar_rect()
    if not w then return end
    local val = mp.get_property_number(cfg.prop, 0)          -- -100..100
    local frac = (val + 100) / 200
    local fill_y = y1 - (y1 - y0) * frac
    local a = assdraw.ass_new()
    -- background
    a:new_event()
    a:append(string.format("{\\pos(0,0)\\an7\\1c&H%s&\\1a&H30&\\bord0\\shad0}", cfg.bg))
    a:draw_start(); a:rect_cw(x0, y0, x1, y1); a:draw_stop()
    -- fill
    a:new_event()
    a:append(string.format("{\\pos(0,0)\\an7\\1c&H%s&\\1a&H10&\\bord0\\shad0}", cfg.fg))
    a:draw_start(); a:rect_cw(x0, fill_y, x1, y1); a:draw_stop()
    -- value text (below the bar)
    a:new_event()
    a:append(string.format(
        "{\\an8\\pos(%d,%d)\\fs%d\\1c&H%s&\\bord1\\3c&H%s&\\shad0}%s%d",
        math.floor((x0 + x1) / 2), y1 + 8, 20, cfg.text, cfg.bg,
        val > 0 and "+" or "", val))
    overlay.res_x, overlay.res_y = w, h
    overlay.data = a.text
    overlay:update()
end

local function hide()
    if not state.shown then return end
    state.shown = false
    overlay:remove()
    mp.disable_key_bindings("brightness_bar")
end

local function show()
    if not state.shown then
        state.shown = true
        mp.enable_key_bindings("brightness_bar", "allow-vo-dragging")
    end
    draw()
end

local function set_from_y(y)
    local w, h, x0, y0, x1, y1 = bar_rect()
    if not w then return end
    local frac = 1 - (y - y0) / (y1 - y0)
    frac = math.max(0, math.min(1, frac))
    mp.set_property_number(cfg.prop, math.floor(frac * 200 - 100 + 0.5))
    draw()
end

local function adjust(delta)
    local v = mp.get_property_number(cfg.prop, 0)
    mp.set_property_number(cfg.prop, math.max(-100, math.min(100, v + delta)))
    draw()
end

-- key bindings that only apply while the zone is active (bounded by mouse_area)
mp.set_key_bindings({
    {"WHEEL_UP",   function() adjust(cfg.step)  end},
    {"WHEEL_DOWN", function() adjust(-cfg.step) end,},
    {"MBTN_MID",   function() mp.set_property_number(cfg.prop, 0); draw() end},
    {"MBTN_LEFT",  function(e)  -- on release
                        state.dragging = false
                   end,
                   function(e)  -- on press
                        local _, _, x0, y0, x1, y1 = bar_rect()
                        if state.my >= y0 - 20 and state.my <= y1 + 20
                           and state.mx <= cfg.hit_w + cfg.margin_x then
                            state.dragging = true
                            set_from_y(state.my)
                        end
                   end},
}, "brightness_bar", "force")
mp.set_mouse_area(0, 0, cfg.zone_w + cfg.margin_x, 100000, "brightness_bar")

mp.observe_property("mouse-pos", "native", function(_, pos)
    if not pos then return end
    state.mx, state.my = pos.x, pos.y
    if state.dragging then
        -- if the mouse left the zone, the release event may have been missed
        if pos.x > cfg.zone_w + 160 or not pos.hover then
            state.dragging = false
            hide()
            return
        end
        set_from_y(pos.y)
    elseif pos.hover and in_zone(pos.x, pos.y) then
        show()
    else
        hide()
    end
end)

mp.observe_property("osd-dimensions", "native", function()
    if state.shown then draw() end
end)
