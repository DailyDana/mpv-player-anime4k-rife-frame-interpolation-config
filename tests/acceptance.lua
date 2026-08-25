local mp = require 'mp'
local MEDIA = mp.get_opt('media') or ''
local bitti = false

local function vfs()
  local t = {}
  for _, f in ipairs(mp.get_property_native('vf', {})) do t[#t + 1] = '@' .. tostring(f.label) end
  return #t == 0 and '(empty)' or table.concat(t, ',')
end

mp.register_event('file-loaded', function()
  if bitti then return end
  bitti = true
  mp.add_timeout(1.2, function()
    mp.commandv('script-message', 'panel-goruntu-sec', '3')     -- sharpening profile
    mp.add_timeout(1.8, function()
      local p = mp.get_property_native('vo-passes')
      local dog, ups = 0, 0
      if p and p.fresh then
        for _, x in ipairs(p.fresh) do
          local d = tostring(x.desc)
          if d:match('Deblur%-DoG') then dog = dog + 1 end
          if d:match('Upscale%-CNN') then ups = ups + 1 end
        end
      end
      print(('T1| sharpening profile: DeblurDoG=%d UpscaleCNN=%d (both must be > 0)'):format(dog, ups))

      mp.commandv('script-message', 'panel-goruntu-rife')
      mp.add_timeout(1.2, function()
        print(('T2| 24fps RIFE: vf=%s (must contain @rife)'):format(vfs()))

        mp.set_property('lut', mp.command_native({ 'expand-path', '~~/luts/anime-clean.cube' }))
        mp.add_timeout(0.8, function()
          local l = tostring(mp.get_property('lut'))
          print(('T3| LUT anime-clean loaded: %s'):format(tostring(l:find('anime%-clean') ~= nil)))

          mp.commandv('loadfile', MEDIA .. '/cfr_60.mp4', 'replace')
          mp.add_timeout(2.0, function()
            mp.commandv('script-message', 'panel-goruntu-rife')
            mp.add_timeout(1.2, function()
              print(('T4| 60fps RIFE: vf=%s (must be empty)'):format(vfs()))
              mp.commandv('quit')
            end)
          end)
        end)
      end)
    end)
  end)
end)
