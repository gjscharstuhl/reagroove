-- ============================================================
-- gjs - x - control.lua
-- Main entry point
-- Keep this file in the same folder as core.lua and screen*.lua
-- ============================================================


reaper.SetExtState("GJS_MULTI", "Page", "1", true)

local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])")

if not script_path then
    reaper.ShowMessageBox(
        "Kon de map van het script niet bepalen.",
        "Launchpad X",
        0
    )
    return
end

local function load_file(name)
    local full_path = script_path .. name
    local ok, result = pcall(dofile, full_path)

    if not ok then
        reaper.ShowMessageBox(
            "Fout bij laden van:\n" .. full_path .. "\n\n" .. tostring(result),
            "Launchpad X",
            0
        )
        return nil
    end

    return result
end


-- SysEx-bridge initialiseren
local bridge = load_file("gjs - x - bridge.lua")
bridge.init()

-- Beschikbaar maken voor core.lua
_G.GJS_X_BRIDGE = bridge

local transport =
    load_file("gjs - x - transport.lua")

if not transport then
    return
end

_G.GJS_X_TRANSPORT = transport

local pattern =
    load_file("gjs - x - pattern.lua")

if not pattern then
    return
end

_G.GJS_X_PATTERN = pattern

local core = load_file("gjs - x - core.lua")
if not core then return end

local screens = {}

for screen = 0, 7 do
    local module = load_file(
        string.format("gjs - x - screen%d.lua", screen)
    )

    if not module then return end
    screens[screen] = module
end

core.start(screens)
