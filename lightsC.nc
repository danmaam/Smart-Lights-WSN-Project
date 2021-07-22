#include "Timer.h"
#include "lights.h"
#include "printf.h"
#define TREE_DEPTH 3
#define toggle_bitmask 7

module lightsC @safe() {
	uses {
		interface Leds;
		interface Boot;
		interface Receive;
		interface AMSend;
		interface Timer<TMilli> as MilliTimer;
		interface Timer<TMilli> as NextSend;
		interface SplitControl as AMControl;
		interface Packet;
		interface PacketAcknowledgements;
	}
}

implementation {

	//uint8_t routing_table[netSize];
	message_t packet;

	bool locked = FALSE;

	uint8_t nextaction = 0;


	am_addr_t last_send; //for acking purposed

	//reserved for led switching
	am_addr_t current_node;
	uint8_t current_pattern;

	void sendPayload(nx_uint8_t action, nx_uint8_t dst, nx_uint8_t snd, am_addr_t addr) {
		light_msg_t* payload = (light_msg_t*) call Packet.getPayload(&packet, sizeof(light_msg_t));
		last_send = addr;
		payload -> action = action;
		payload -> dst = dst;
		payload -> snd = snd;
		printf("Sending to %u packet for dst: %u \n", addr, dst);
		printfflush();
		call PacketAcknowledgements.requestAck(&packet);
		if (call AMSend.send(addr, &packet, sizeof(light_msg_t)) == SUCCESS) {
			locked = TRUE;
		}
	}

	event void Boot.booted() {
		call AMControl.start();
	}

	void toggleNextLed() {
		am_addr_t next_hop;
		if (2 <= current_node && current_node <= 4) next_hop = 2;
		else if (5 <= current_node && current_node <= 7) next_hop = 5;
		else if (8 <= current_node && current_node <= 10) next_hop = 8;
		if (current_node <= 10) {
			sendPayload(nextaction, current_node, TOS_NODE_ID, next_hop);
			current_node++;
		}
	}

	void startLedToggling() {
		nextaction = nextaction ^ 1;
		current_node = 2;
		current_pattern = TOGGLE;
		toggleNextLed();
	}



	event void AMControl.startDone(error_t err) {
		if (err == SUCCESS) {
			if (TOS_NODE_ID == 1) {
				call MilliTimer.startPeriodic(3000);
				printf("Started timer on %u \n", TOS_NODE_ID);
				printfflush();
			}
		}
		else {
			call AMControl.start();
		}
	}
	event void AMControl.stopDone(error_t err) {}

	event void MilliTimer.fired() {
		printf("Timer Fired on %u \n", TOS_NODE_ID);
		printfflush();
		if (locked) {
			return;
		}
		else {
			startLedToggling();
		}
	}

	event void NextSend.fired() {
		toggleNextLed();
	}

	event void AMSend.sendDone(message_t* bufPtr, error_t error) {
		if (&packet == bufPtr && error == SUCCESS) {
			locked = FALSE;
			if (call PacketAcknowledgements.wasAcked(bufPtr)) {
				printf("Packed acked from %u\n", last_send);
				printfflush();
				//continue the pattern
				last_send = -1;
				if (TOS_NODE_ID == 1) {
					//printf("Hey i'm working until here\n");
					//printfflush();
					if (current_pattern == TOGGLE) {
						call NextSend.startOneShot(10);
						//toggleNextLed();
					}
				}
			}
			else {
				printf("Non acked message from %u\n", last_send);
				printfflush();
				if (last_send == -1) {
					printf("fatal error in retransmission\n");
					printfflush();
				}
				printf("Resending to %u\n", last_send);
				printfflush();
				call PacketAcknowledgements.requestAck(&packet);
				if (call AMSend.send(last_send, &packet, sizeof(light_msg_t)) == SUCCESS) {
					locked = TRUE;
				}
			}

		}
	}

	//message receiver handler
	event message_t* Receive.receive(message_t* bufPtr, void* payload, uint8_t len) {
		if (len != sizeof(light_msg_t)) {
			printf("ERROR! \n");
			printfflush();
			return bufPtr;}
		else {
			light_msg_t* msg = (light_msg_t*)payload;
			printf("Received from %u : dst: %u , action: %u \n", msg->snd, msg->dst, msg->action);
			printfflush();
			if (TOS_NODE_ID == msg->dst) { 	//unicast command message
				//message correctly received. turning on or off leds
				printf("Changing my leds!\n");
				printfflush();
				call Leds.set(msg->action * toggle_bitmask);
			}
			else {
				//not the message destination. must redirect
				am_addr_t destination;
				if (msg->dst > TOS_NODE_ID) destination = TOS_NODE_ID + 1;
				else destination = TOS_NODE_ID - 1;
				printf("Redirecting payload to %u\n", destination);
				printfflush();
				sendPayload(msg->action, msg->dst, TOS_NODE_ID, destination);
			}
			return bufPtr;
		}
	}
}
