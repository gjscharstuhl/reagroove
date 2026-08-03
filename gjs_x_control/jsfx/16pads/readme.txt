16-Pads by Gert-Jan Scharstuhl

Features:

- 16pads with 8 sample layers each
- 8 midi choke groups
- note on/off editing
- 8 Layer groups
- custom presets
- adsr and volume  for each sample
- editable start and endpoint plus looping
- setup script
- play modes:selected velocity amd random

Instructions:

Instalation:
Place the 16padsetup.eel script in the Reaper scripts folder
Copy the gjs directory under the Reaper effects directory
Startup reaper and launch the 16padsetup.eel script
a 16pads midi channel and a folder with 16 sample tracks will be created,
with the proper routing and settings. 


Usage
Asign your midi controller on the 16 pads track.
For now any midi channel will do.
Press the fx button on 16pads.
You see an empty instance of 16pads.

Edit Pads:
Press edit pads on the menu.
You see now 4 little buttons on each pad.

First we want to asign each pad an midi note:
Click with your mouse on the pad and then the midi note
on your controller. The note will appear on the pad.

Next want put one or more samples on each pad.
Open the media exporer and drag the sample you want on the
pad you want. You can stack up to 8 samples on each pad. with the
+ and - button you can browse to the samples on each pad
you can right click on the pad to remove the top sample.
you can copy an pad to another pad with ctrl drag.
You can swap 2 pads with shift drag.
You can clear all samples on the pad  with shift click.
You can cycle the play modes to click the tiny m button. Selected,Velocity and Random.
If you assigned a note and at least one sample on the pad you should hear it by pressing the midi note 
on your midi controller.

Editing the wav

You can edit the selected sample further by pressing the tiny e button on the pad.
With ADSR knobs you can regulate the ADSR of the sample with the V knob the volume.
With the leftmarker button you can specify the begin point of your sample and with
right marker button the end point. If you want loop the sample press the loop button.
You can use the mousewheel to scroll the wave form left and right and shift mouse wheel
to zoom in and out of the sample. This will help you to set the looppoints more accurate.

Setting up midichoke groups

Midi choke groups will be used to mute eachother pad in the group
when another pad in the group is played. Its usefull for hihats etc.
Press from the main menu the Define choke groups button.
Click on the pad you want to add to the group. The pad will hilight green when its
in the group. You can remove it by clicking the hilighted button.
If you want define another group use the > button to select the next group.
withe the < you can go to the previous group

Edit Noteoffs:

By default each note on the pad will be played as long you
press the midi note on your controller. You can ignore the noteoffs
off the pad by pressing the pad after you pressed Edit note offs
in the main menu. The pad will hilight yellow and the samples will be played to iets and even you
releases the midi note on your controller.

Define layer groups.

You can assign a group by clicking on the pads (like in midichoke)

You can assign the 4 little kbobs with number zero on it by clicking it and then assign it by pressing
a midi note on your controller (or a different midi controller) Also not midi notes are accepted (knobs ,sliders)
the number of the the midinote/knob will appear in the litlle box.

When you press the note defined in the first box all the pads you defined in the group will be set to layer 1.
The second box will set the group to layer 2 and so on.
This way you can assign different chords to different layers.
For example on pad 1 you have an I chord on layer1 an IV cord on layer2 and an V chord on layer3 for guitar
on pad 2`you have the bass sasmples for those chords.
and on pad 3 you have the keyboard samples chords.

In this whey you can jam an entire blues with guitar bass keys and drums

Multiple instances.

If you want more than one 16samples you can create another 16pad.jsfx and additional drumtracks
by choosing group 2 (or higher) in both 16pads.jsfx and on the 16padstrack.jsfx plugins.
Its not in the setupscript yet so you have to configure it manually.
You have to use the slider on the 16padstrack to chose which pad it corresponds to. (The pad on the lowest left is pad1
on the highest right pad 16).You have to route the midi from the 16pads track to the drumtracks.




























































