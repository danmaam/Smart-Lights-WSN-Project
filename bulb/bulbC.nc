#include "Timer.h"
#include "lights.h"
#include "printf.h"
#define TREE_DEPTH 3
#define toggle_bitmask 7

module bulbC @safe() {
	uses {
		interface Leds;
		interface Boot;
		interface Receive;
		interface AMSend;
		interface SplitControl as AMControl;
		interface Packet;
		interface PacketAcknowledgements;
	}
}

implementation {


	message_t packet;

	bool locked = FALSE;

	//variables used for acking purposes
	am_addr_t last_send = -1;
	uint8_t last_msg_type = -1;



	//send a confirmation of light change to the controller; this code will never be executed by the controller
	void sendConfirmation(am_addr_t snd) {

		confirm_msg_t* confirm_msg = (confirm_msg_t*) call Packet.getPayload(&packet, sizeof(confirm_msg_t));
		am_addr_t next_hop;

		if (TOS_NODE_ID % TREE_DEPTH == 2) next_hop = 1;
		else next_hop = TOS_NODE_ID - 1;

		printf("ID: %u | Sending confirmation, next-hop: %u\n", TOS_NODE_ID, next_hop);
		printfflush();
		last_msg_type = CONFIRM;
		confirm_msg -> snd = snd;
		call PacketAcknowledgements.requestAck(&packet);
		if (call AMSend.send(next_hop, &packet, sizeof(confirm_msg_t))) {
			locked = TRUE;
		}
	}


	void sendPayload(nx_uint8_t action, nx_uint8_t dst, nx_uint8_t snd) {
		light_msg_t* payload = (light_msg_t*) call Packet.getPayload(&packet, sizeof(light_msg_t));
		am_addr_t addr;
		//setting next hop
		if (TOS_NODE_ID % TREE_DEPTH == 1) addr = TOS_NODE_ID - 1; //end of the tree of depth 3
		else if (dst > TOS_NODE_ID) addr = TOS_NODE_ID + 1;
		else addr = TOS_NODE_ID - 1;

		//variables used for acking purposes
		last_msg_type = COMMAND;
		last_send = addr;

		payload -> action = action;
		payload -> dst = dst;

		printf("ID: %u | Sending to %u packet for dst: %u \n", TOS_NODE_ID, addr, dst);
		printfflush();
		call PacketAcknowledgements.requestAck(&packet);
		if (call AMSend.send(addr, &packet, sizeof(light_msg_t)) == SUCCESS) {
			locked = TRUE;
		}
	}

	event void Boot.booted() {
		call AMControl.start();
	}


	event void AMControl.startDone(error_t err) {
		if (!(err == SUCCESS)) {
			call AMControl.start();
		}
	}
	event void AMControl.stopDone(error_t err) {}


	event void AMSend.sendDone(message_t* bufPtr, error_t error) {
		if (&packet == bufPtr && error == SUCCESS) {
			locked = FALSE;
			if (call PacketAcknowledgements.wasAcked(bufPtr)) {
				//printf("Packed acked from %u\n", last_send);
				//printfflush();
				//continue the pattern
				last_send = -1;
				last_msg_type = -1;
			}
			else {
				//printf("Non acked message from %u\n", last_send);
				//printfflush();
				if (last_send == -1 || last_msg_type == -1) {
					//printf("fatal error in retransmission\n");
					//printfflush();
				}
				else {
					size_t msg_size;
					//printf("Resending to %u\n", last_send);
					//printfflush();
					if (last_msg_type == COMMAND) msg_size = sizeof(light_msg_t);
					else msg_size = sizeof(confirm_msg_t);
					call PacketAcknowledgements.requestAck(&packet);
					if (call AMSend.send(last_send, &packet, msg_size) == SUCCESS) {
						locked = TRUE;
					}
				}
			}
		}
	}

	//message receiver handler
	event message_t* Receive.receive(message_t* bufPtr, void* payload, uint8_t len) {
		if (len == sizeof(confirm_msg_t)) {
			confirm_msg_t *msg = (confirm_msg_t*) payload;
			printf("ID: %u | Redirecting confirmation\n", TOS_NODE_ID);
			printfflush();
			sendConfirmation(msg -> snd);
			return bufPtr;
		}

		else if (len == sizeof(light_msg_t)) {
			light_msg_t* msg = (light_msg_t*)payload;
			printf("ID: %u | Received dst: %u , action: %u \n", TOS_NODE_ID, msg->dst, msg->action);
			printfflush();
			if (TOS_NODE_ID == msg->dst) { 	//unicast command message
				//message correctly received. turning on or off leds
				printf("ID: %u | Changing my leds!\n", TOS_NODE_ID);
				printfflush();
				call Leds.set(msg->action * toggle_bitmask);
				sendConfirmation(TOS_NODE_ID);
			}
			else {
				//not the message destination. must redirect
				printf("ID: %u | Redirecting payload for %u\n", TOS_NODE_ID, msg->dst);
				printfflush();
				sendPayload(msg->action, msg->dst, TOS_NODE_ID);
			}
			return bufPtr;
		}
		else {
			//printf("ERROR!\n");
			//printfflush();
			return bufPtr;
		}
	}
}
