#ifndef RADIO_COUNT_TO_LEDS_H
#define RADIO_COUNT_TO_LEDS_H

typedef nx_struct light_msg {
  nx_uint8_t action; //1 to turn on light, 0 to turn off light
  nx_uint8_t dst; //the destination light bulb
} light_msg_t;

typedef nx_struct confirm_msg {
  nx_uint8_t snd; //the sender
} confirm_msg_t;

enum {
  AM_MSG = 6,
  COMMAND = 0,
  CONFIRM = 1,

  TOGGLE = 0,
  CROSS_SWITCH = 1,
  TRIANGLE_SWITCH = 2,
};


#endif
