desc:gjs - Circuit page LEDs

@init
channel = 3; // MIDI channel 4

page1_trigger = 73;
page2_trigger = 75;

page1_led = 73;
page2_led = 75;

led_on = 127;
led_off = 0;

current_page = 1;

@block
while (midirecv(offset, msg1, msg2, msg3)) (
  status = msg1 & 240;
  ch = msg1 & 15;

  is_note_on = status == 144 && msg3 > 0;
  is_note_off = status == 128 || (status == 144 && msg3 == 0);

  is_page_note =
    ch == channel &&
    (
      msg2 == page1_trigger ||
      msg2 == page2_trigger
    );

  // Page 1
  is_note_on && ch == channel && msg2 == page1_trigger ? (
    current_page = 1;
  );

  // Page 2
  is_note_on && ch == channel && msg2 == page2_trigger ? (
    current_page = 2;
  );

  // Note-off van page pads niet doorlaten
  !(is_page_note && is_note_off) ? (
    midisend(offset, msg1, msg2, msg3);
  );
);

// LED state forceren
current_page == 1 ? (
  midisend(0, 0x90 + channel, page1_led, led_on);
  midisend(0, 0x80 + channel, page2_led, led_off);
);

current_page == 2 ? (
  midisend(0, 0x80 + channel, page1_led, led_off);
  midisend(0, 0x90 + channel, page2_led, led_on);
);
