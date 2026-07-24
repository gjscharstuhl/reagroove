GJS FLkey v1
============

Dit is de eerste modulaire versie van de FLkey-controller voor REAPER.

Structuur
--------
control.lua
    Hoofdscript en tijdelijke demo-mapping.

core.lua
    Leest MIDI-input van hw:F49,0,1 en dispatcht events.

controls.lua
    Registratie van callbacks voor CC's en noten.

api.lua
    Publieke controller-API.

bridge.lua
    Betrouwbare Lua -> gmem verbinding.
    Er wordt maar één commando tegelijk verstuurd.
    Het volgende commando gaat pas weg nadat de JSFX een ACK heeft gegeven.

constants.lua
    Device, kanaal, commandonummers en bekende ranges.

colors.lua
    RGB-kleuren.

display.lua
    Voorbereiding voor displayfuncties.

jsfx/GJS FLkey Bridge.jsfx
    Zet bridgecommando's om naar MIDI en SysEx.

Installatie
-----------
1. Kopieer de Lua-bestanden samen naar bijvoorbeeld:

   ~/.config/REAPER/Scripts/gjs/flkey/

2. Kopieer:

   jsfx/GJS FLkey Bridge.jsfx

   naar bijvoorbeeld:

   ~/.config/REAPER/Effects/gjs/

3. Voeg de JSFX toe aan een track.

4. Maak op die track een MIDI hardware-send naar de tweede
   FLkey/DAW MIDI-uitgang.

5. Laad en start control.lua via de REAPER Action List.

Huidige demo
------------
CC37 t/m CC44 toggelen elk hun eigen lamp.

API-voorbeelden
---------------
local api = require("api")
local colors = require("colors")

api.set_cc_rgb(37, colors.ORANGE)
api.set_cc_rgb(38, 0, 127, 0)

api.set_pad_rgb(96, colors.RED)
api.set_pad_rgb(97, 0, 0, 127)

api.set_daw_mode(true)
api.set_layout(2)
api.clear_display()
api.set_tempo(120)

Callbacks
---------
local controls = require("controls")

controls.on_cc_press(37, function(cc, value)
    -- knop ingedrukt
end)

controls.on_cc_release(37, function(cc, value)
    -- knop losgelaten
end)

controls.on_note_press(96, function(note, velocity)
    -- pad ingedrukt
end)

Belangrijk
----------
De tekstfuncties voor het display staan al in de API, maar zijn in deze
eerste versie bewust nog niet geïmplementeerd. De LED- en inputbasis is
wel volledig aangesloten.

Begin eerst met exact dezelfde test als stage 3:
de acht faderknoppen moeten hun eigen led toggelen.
