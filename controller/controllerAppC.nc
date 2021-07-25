#include "lights.h"
#define NEW_PRINTF_SEMANTICS

configuration controllerAppC {}
implementation {
	components MainC, controllerC as App, LedsC;
	components new AMSenderC(AM_MSG);
	components new AMReceiverC(AM_MSG);
	components new TimerMilliC();
	components ActiveMessageC;
	components PrintfC;
	components SerialStartC;

	App.Boot -> MainC.Boot;
    App.Receive -> AMReceiverC;
    App.AMSend -> AMSenderC;
    App.AMControl -> ActiveMessageC;
	App.PacketAcknowledgements -> ActiveMessageC;
    App.Leds -> LedsC;
    App.MilliTimer -> TimerMilliC;
    App.Packet -> AMSenderC;
}


