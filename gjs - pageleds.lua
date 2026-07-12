local oldtrack = reaper.GetExtState("GJS_PAGES", "current")

if oldtrack ~= "" then
   set_led(oldtrack, false)
end

set_led(THIS_PAGE, true)

reaper.SetExtState("GJS_PAGES", "current", THIS_PAGE, false)
