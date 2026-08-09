-- ============================================================
-- gjs - x - screen7.lua
-- Performance screen controller. The JSFX owns the 8x8 matrix.
-- ============================================================

local GMEM_NAME = "GJS_X_BRIDGE"
local PERF_LAYOUT_SLOT = 1200 -- 0 off, 1 drums, 2 piano
local PERF_REDRAW_SLOT = 1202

local function drawscreen7(api)
    local state = api.get_screen_state and api.get_screen_state(7) or nil
    if state and not state.performance_layout then
        state.performance_layout = "drums"
    end

    local function set_layout(layout)
        if state then state.performance_layout = layout end
        reaper.gmem_attach(GMEM_NAME)
        reaper.gmem_write(PERF_LAYOUT_SLOT, layout == "piano" and 2 or 1)
        reaper.gmem_write(PERF_REDRAW_SLOT, (reaper.gmem_read(PERF_REDRAW_SLOT) or 0) + 1)
    end

    reaper.gmem_attach(GMEM_NAME)
    set_layout(state and state.performance_layout or "drums")

    api.set_navigation(
        function() set_layout("drums") end,
        function() set_layout("piano") end,
        nil,
        nil
    )

    -- No matrix pads are drawn here. The Performance JSFX owns all 64 LEDs.
end

return drawscreen7
