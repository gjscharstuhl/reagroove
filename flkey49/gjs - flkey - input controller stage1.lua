desc:GJS FLkey 49 single LED test
tags:midi novation flkey sysex

slider1:0<0,1,1{Off,On}>CC37 LED
slider2:0<0,127,1>Red
slider3:127<0,127,1>Green
slider4:0<0,127,1>Blue

@init

buf = 0;

last_on = -1;
last_r = -1;
last_g = -1;
last_b = -1;

send_pending = 1;


function send_daw_mode()
(
    midisend(0, $x9F, $x0C, $x7F);
);


function send_cc_rgb(cc, r, g, b)
(
    buf[0]  = $xF0;
    buf[1]  = $x00;
    buf[2]  = $x20;
    buf[3]  = $x29;
    buf[4]  = $x02;
    buf[5]  = $x11;
    buf[6]  = $x01;
    buf[7]  = $x53;
    buf[8]  = cc;
    buf[9]  = r;
    buf[10] = g;
    buf[11] = b;
    buf[12] = $xF7;

    midisend_buf(0, buf, 13);
);


@slider

send_pending = 1;


@block

slider1 != last_on ||
slider2 != last_r ||
slider3 != last_g ||
slider4 != last_b ? (
    send_pending = 1;
);

send_pending ? (
    send_daw_mode();

    slider1 > 0 ? (
        send_cc_rgb(37, slider2, slider3, slider4);
    ) : (
        send_cc_rgb(37, 0, 0, 0);
    );

    last_on = slider1;
    last_r = slider2;
    last_g = slider3;
    last_b = slider4;

    send_pending = 0;
);
