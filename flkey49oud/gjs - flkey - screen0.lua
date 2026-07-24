-- Simpel eerste FLkey-scherm.
-- Pad note 96 is het eerste pad in de Channel Rack-layout.

return function(api)
    local C = api.COLOR

    api.drawpad(
        96,
        C.GREEN,
        api.MODE_HIGHLIGHT,
        {
            active_color = C.WHITE,

            on_press = function()
                reaper.ShowMessageBox(
                    "Hallo vanaf FLkey-pad 1!",
                    "FLkey test",
                    0
                )
            end
        }
    )
end
