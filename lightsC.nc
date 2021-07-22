#include "Timer.h"
#include "lights.h"
#include "printf.h"
#define TREE_DEPTH 3
#define toggle_bitmask 7
#define network_size 10
#define single_iteration 5

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

	am_addr_t routingTable[network_size] = {-1, 2, 2, 2, 5, 5, 5, 8, 8, 8};

	message_t packet;

	bool locked = FALSE;
	bool resettingLights = FALSE;

	uint8_t nextaction = 0;
	uint8_t current_iteration = 0; //at zero turns off all the leds, a single pattern runs for 10 iterations

	//variables used for acking purposes
	am_addr_t last_send;
	uint8_t last_msg_type = -1;

	//reserved for led switching
	am_addr_t current_node;
	uint8_t current_pattern = 0;

	//send a confirmation of light change to the controller; this code will never be executed by the controller
	void sendConfirmation(am_addr_t dst) {
		confirm_msg_t* confirm_msg = (confirm_msg_t*) call Packet.getPayload(&packet, sizeof(confirm_msg_t));
		am_addr_t next_hop;

		if (TOS_NODE_ID == 2 || TOS_NODE_ID == 5 || TOS_NODE_ID == 8) next_hop = 1;
		else if (dst > TOS_NODE_ID) next_hop = TOS_NODE_ID + 1;
		else next_hop = TOS_NODE_ID - 1;

		last_send = next_hop;
		last_msg_type = CONFIRM;

		confirm_msg -> dst = dst;
		call PacketAcknowledgements.requestAck(&packet);
		if (call AMSend.send(next_hop, &packet, sizeof(confirm_msg_t))) {
			locked = TRUE;
		}
	}


	void sendPayload(nx_uint8_t action, nx_uint8_t dst, nx_uint8_t snd, am_addr_t addr) {
		light_msg_t* payload = (light_msg_t*) call Packet.getPayload(&packet, sizeof(light_msg_t));
		last_msg_type = COMMAND;
		last_send = addr;
		payload -> action = action;
		payload -> dst = dst;
		payload -> snd = snd;
		//printf("Sending to %u packet for dst: %u \n", addr, dst);
		//printfflush();
		call PacketAcknowledgements.requestAck(&packet);
		if (call AMSend.send(addr, &packet, sizeof(light_msg_t)) == SUCCESS) {
			locked = TRUE;
		}
	}

	event void Boot.booted() {
		call AMControl.start();
	}

	void toggleNextLed() {
		am_addr_t next_hop = routingTable[current_node - 1];
		if (current_node <= 10) {
			sendPayload(nextaction, current_node, TOS_NODE_ID, next_hop);
			current_node++;
		}
		else resettingLights = FALSE;
	}

	void startLedToggling() {
		nextaction = 1 ^ (1 & nextaction);
		current_node = 2;
		toggleNextLed();
	}

	void crossNextLed() {
		am_addr_t next_hop = routingTable[current_node - 1];
		uint8_t comm = nextaction;
		if (current_node <= 10) {
			if (current_node % 2 == 0) {
				comm = 1 ^ nextaction;
			}
			sendPayload(comm, current_node, TOS_NODE_ID, next_hop);
			current_node++;
		}

	}

	void triangleNextLed() {
		am_addr_t next_hop = routingTable[current_node - 1];
		uint8_t comm;
		if (nextaction == 0) {
			if (current_node == 2 || current_node == 3 || current_node == 4 || current_node == 6) comm = 1;
			else comm = 0;
		}
		else if (nextaction == 1) {
			if (current_node == 2 || current_node == 5 || current_node == 8 || current_node == 6) comm = 1;
			else comm = 0;
		}
		else if (nextaction == 2) {
			if (current_node == 8 || current_node == 9 || current_node == 10 || current_node == 6) comm = 1;
			else comm = 0;
		}
		else if (nextaction == 3) {
			if (current_node == 4 || current_node == 7 || current_node == 10 || current_node == 6) comm = 1;
			else comm = 0;
		}
		if (current_node <= 10) {
			sendPayload(comm, current_node, TOS_NODE_ID, next_hop);
			current_node++;
		}
	}

	void startTriangularSwitch() {
		nextaction = (nextaction + 1) % 4;
		current_node = 2;
		triangleNextLed();
	}

	void startCrossSwitch() {
		nextaction = (1 & nextaction) ^ 1;
		current_node = 2;
		crossNextLed();
	}

	event void AMControl.startDone(error_t err) {
		if (err == SUCCESS) {
			//initializes routing table for controller
			if (TOS_NODE_ID == 1) {
				call MilliTimer.startPeriodic(5000);
				//printf("Started timer on %u \n", TOS_NODE_ID);
				//printfflush();
			}
		}
		else {
			call AMControl.start();
		}
	}
	event void AMControl.stopDone(error_t err) {}

	void nextPattern() {
		printf("Current iteration: %u\n", current_iteration);
		printf("Current pattern: %u\n", current_pattern);
		//printfflush();
		if (current_iteration == 0) {
			printf("Changing pattern\n");
			printfflush();
			current_pattern = (current_pattern + 1) % 3;
			nextaction = 1;
			resettingLights = TRUE;
			startLedToggling();
		}
		else {
			//need to reset lights before change
			if (current_pattern == TOGGLE) {
				startLedToggling();
			}
			else if (current_pattern == TRIANGLE_SWITCH) {
				startTriangularSwitch();
			}
			else if (current_pattern == CROSS_SWITCH) {
				startCrossSwitch();
			}
		}
		current_iteration = (current_iteration + 1) % single_iteration;
	}

	event void MilliTimer.fired() {
		//printf("Timer Fired on %u \n", TOS_NODE_ID);
		//printfflush();
		if (locked) {
			return;
		}
		else {
			nextPattern();
		}
	}

	event void NextSend.fired() {
		toggleNextLed();
	}

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
			if (TOS_NODE_ID == msg -> dst) {
				if (current_pattern == TOGGLE || resettingLights == TRUE) {
					toggleNextLed();
				}
				else if (current_pattern == CROSS_SWITCH) {
					crossNextLed();
				}
				else if (current_pattern == TRIANGLE_SWITCH) {
					triangleNextLed();
				}
			}
			else sendConfirmation(msg -> dst);
			return bufPtr;
		}

		else if (len == sizeof(light_msg_t)) {
			light_msg_t* msg = (light_msg_t*)payload;
			//printf("Received from %u : dst: %u , action: %u \n", msg->snd, msg->dst, msg->action);
			//printfflush();
			if (TOS_NODE_ID == msg->dst) { 	//unicast command message
				//message correctly received. turning on or off leds
				//printf("Changing my leds!\n");
				//printfflush();
				call Leds.set(msg->action * toggle_bitmask);
				sendConfirmation(1);
			}
			else {
				//not the message destination. must redirect
				am_addr_t destination;
				if (TOS_NODE_ID == 4 || TOS_NODE_ID == 7 || TOS_NODE_ID == 10) destination = TOS_NODE_ID - 1;
				else if (msg->dst > TOS_NODE_ID) destination = TOS_NODE_ID + 1;
				else destination = TOS_NODE_ID - 1;
				//printf("Redirecting payload to %u\n", destination);
				//printfflush();
				sendPayload(msg->action, msg->dst, TOS_NODE_ID, destination);
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
