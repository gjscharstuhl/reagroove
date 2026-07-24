-- ============================================================
-- gjs - flkey - control.lua
-- Eerste minimale FLkey-controller
-- ============================================================

local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])")

if not script_path then
    reaper.ShowMessageBox(
        "Kon de map van het script niet bepalen.",
        "FLkey",
        0
    )
    return
end

local function load_file(name)
    local path = script_path .. name
    local ok, result = pcall(dofile, path)

    if not ok then
        reaper.ShowMessageBox(
            "Fout bij laden van:\n" .. path .. "\n\n" .. tostring(result),
            "FLkey",
            0
        )
        return nil
    end

    return result
end

local colors = load_file("gjs - flkey - colors.lua")
if not colors then return end
_G.GJS_FLKEY_COLORS = colors

local bridge = load_file("gjs - flkey - bridge.lua")
if not bridge then return end
_G.GJS_FLKEY_BRIDGE = bridge

local core = load_file("gjs - flkey - core.lua")
if not core then return end

local screen0 = load_file("gjs - flkey - screen0.lua")
if not screen0 then return end

core.start(screen0)
