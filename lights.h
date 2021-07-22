#ifndef RADIO_COUNT_TO_LEDS_H
#define RADIO_COUNT_TO_LEDS_H

typedef nx_struct light_msg {
  nx_uint8_t action; //1 to turn on light, 0 to turn off light
  nx_uint8_t dst; //the destination light bulb
  nx_uint8_t snd; //the light bulb sender
  nx_uint8_t hop_count; //maximum number of hops
} light_msg_t;

enum {
  AM_MSG = 6,


  TOGGLE = 0,
};



#endif
