GJS - X - CONTROL
=================

Plaats alle .lua-bestanden uit deze map samen in dezelfde map.
Start alleen:

    gjs - x - control.lua

Bestanden:
- gjs - x - control.lua   hoofdscript / loader
- gjs - x - core.lua      gedeelde API, state en MIDI-logica
- gjs - x - screen0.lua   hoofdscherm
- gjs - x - screen1.lua   pattern launcher
- gjs - x - screen2.lua   mixerfaders
- gjs - x - screen3.lua t/m screen7.lua tijdelijke testschermen

De MIDI-output wordt gezocht op DEVICE_NAME = "X" in core.lua.
De Programmer Mode SysEx is nog een hook/comment in auto_program_mode().
