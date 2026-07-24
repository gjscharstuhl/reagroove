GJS FLkey - minimale controller test
====================================

Bestanden
---------
- GJS FLkey 49 Lua Bridge.jsfx
- gjs - flkey - control.lua
- gjs - flkey - core.lua
- gjs - flkey - bridge.lua
- gjs - flkey - colors.lua
- gjs - flkey - screen0.lua

Installatie
-----------
1. Kopieer de JSFX naar ~/.config/REAPER/Effects/
2. Kopieer de vijf Lua-bestanden samen naar je REAPER Scripts-map.
3. Maak een track met de JSFX erop.
4. Maak vanaf die track een MIDI hardware send naar de tweede FLkey/DAW-poort.
5. Zorg dat de FLkey MIDI-input in REAPER is ingeschakeld.
6. Voeg 'gjs - flkey - control.lua' toe aan de Action List en start hem.
7. Druk op het eerste pad. Het pad wordt wit en er verschijnt een messagebox.
8. Na het sluiten van de messagebox en loslaten wordt het pad weer groen.

Voorbeeld-API
-------------
api.drawpad(
    96,
    C.GREEN,
    api.MODE_HIGHLIGHT,
    {
        active_color = C.WHITE,
        on_press = function()
            reaper.ShowMessageBox("Hallo!", "FLkey", 0)
        end
    }
)

Opmerking
---------
De messagebox blokkeert de deferred loop zolang hij openstaat. Dat is voor deze
kleine test juist handig en zichtbaar. Voor de echte controller gebruiken we
normale callbacks zonder blokkerende messagebox.
