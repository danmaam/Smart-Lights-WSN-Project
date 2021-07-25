#include "lights.h"
#define NEW_PRINTF_SEMANTICS

configuration bulbAppC {}
implementation {
	components MainC, bulbC as App, LedsC;
	components new AMSenderC(AM_MSG);
	components new AMReceiverC(AM_MSG);
	components ActiveMessageC;
	components PrintfC;
	components SerialStartC;

	App.Boot -> MainC.Boot;
    App.Receive -> AMReceiverC;
    App.AMSend -> AMSenderC;
    App.AMControl -> ActiveMessageC;
	App.PacketAcknowledgements -> ActiveMessageC;
    App.Leds -> LedsC;
    App.Packet -> AMSenderC;
}


