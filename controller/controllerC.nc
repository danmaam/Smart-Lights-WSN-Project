#include "Timer.h"
#include "lights.h"
#include "printf.h"
#define network_size 10
#define single_iteration 5

module controllerC @safe() {
	uses {
		interface Leds;
		interface Boot;
		interface Receive;
		interface AMSend;
		interface Timer<TMilli> as MilliTimer;
		interface SplitControl as AMControl;
		interface Packet;
		interface PacketAcknowledgements;
	}
}

implementation {

	am_addr_t routingTable[network_size] = {-1, 2, 2, 2, 5, 5, 5, 8, 8, 8}; //routing table for the controller

	message_t packet;

	bool locked = FALSE;
	//used to indicate if lights must be turn off
	bool resettingLights = FALSE;

	uint8_t current_iteration = 0; //at zero turns off all the leds, a single pattern runs for 10 iterations
	//used in multiled patterns such as triangular and cross switch
	uint8_t nextaction = 0;


	//reserved for led switching
	am_addr_t current_node;
	uint8_t current_pattern = 2;

	//code to send command messages from the controller
	void sendPayload(nx_uint8_t action, nx_uint8_t dst, am_addr_t addr) {
		light_msg_t* payload = (light_msg_t*) call Packet.getPayload(&packet, sizeof(light_msg_t));
		payload -> snd = TOS_NODE_ID;
		payload -> action = action;
		payload -> dst = dst;
		printf("CONTROLLER | Sending to %u packet for dst: %u \n", addr, dst);
		printfflush();
		call PacketAcknowledgements.requestAck(&packet);
		if (call AMSend.send(addr, &packet, sizeof(light_msg_t)) == SUCCESS) {
			locked = TRUE;
		}
	}

	event void Boot.booted() {
		call AMControl.start();
	}

	//ALL LIGHTS ON CODE
	void toggleNextLed() {
		am_addr_t next_hop = routingTable[current_node - 1];
		if (current_node <= 10) {
			sendPayload(1, current_node, next_hop);
			current_node++;
		}
		else resettingLights = TRUE;
	}

	void startLedToggling() {
		current_node = 2;
		toggleNextLed();
	}

	//CROSS SWITCH PATTERN CODE
	void crossNextLed() {
		am_addr_t next_hop = routingTable[current_node - 1];
		uint8_t comm = nextaction;
		if (current_node <= 10) {
			if (current_node % 2 == 0) {
				comm = 1 ^ nextaction;
			}
			if (comm != 0) {
				sendPayload(comm, current_node, next_hop);
				current_node++;
			}
			else {
				current_node++;
				crossNextLed();
			}

		}
		else resettingLights = TRUE;

	}

	void startCrossSwitch() {
		nextaction = (1 & nextaction) ^ 1;
		current_node = 2;
		crossNextLed();
	}

	//TRIANGULAR SWITCH CODE
	void triangleNextLed() {
		am_addr_t next_hop = routingTable[current_node - 1];
		uint8_t comm = 0;
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
			if (comm != 0) {
				sendPayload(comm, current_node, next_hop);
				current_node++;
			}
			else {
				current_node++;
				triangleNextLed();
			}

		}
		else resettingLights = TRUE;
	}

	void startTriangularSwitch() {
		nextaction = (nextaction + 1) % 4;
		current_node = 2;
		triangleNextLed();
	}


	//LIGHTS OFF CODE
	void turnOffNextLed() {
		if (current_node <= 10) {
			am_addr_t next_hop = routingTable[current_node - 1];
			sendPayload(0, current_node, next_hop);
			current_node++;
		}
		else resettingLights = FALSE;
	}

	void turnOffAllLights() {
		current_node = 2;
		turnOffNextLed();
	}


	//TINYOS HANDLERS CODE
	event void AMControl.startDone(error_t err) {
		if (err == SUCCESS) {
			if (TOS_NODE_ID == 1) {
				call MilliTimer.startPeriodic(2000);
			}
		}
		else {
			call AMControl.start();
		}
	}
	event void AMControl.stopDone(error_t err) {}

	void nextPattern() {
		if (current_iteration == 0) {
			printf("CONTROLLER | Changing pattern to %u\n", current_pattern);
			printfflush();
			current_pattern = (current_pattern + 1) % 3;
			current_iteration = (current_iteration + 1) % single_iteration;
			nextPattern();
		}
		else {
			if (resettingLights == TRUE) {
				printf("CONTROLLER | Turning all lights off\n");
				printfflush();
				turnOffAllLights();
			}
			else {
				printf("CONTROLLER | ITERATION: %u, PATTERN: %u\n", current_iteration, current_pattern);
				printfflush();
				if (current_pattern == TOGGLE) {
					startLedToggling();
				}
				else if (current_pattern == TRIANGLE_SWITCH) {
					startTriangularSwitch();
				}
				else if (current_pattern == CROSS_SWITCH) {
					startCrossSwitch();
				}
				current_iteration = (current_iteration + 1) % single_iteration;
			}
		}
	}

	event void MilliTimer.fired() {
		//printf("Timer Fired on %u \n", TOS_NODE_ID);
		//printfflush();
		if (locked) {
			return;
		}
		else {
			printf("CONTROLLER | Timer fired. Modifying lights.\n");
			printfflush();
			nextPattern();
		}
	}

	event void AMSend.sendDone(message_t* bufPtr, error_t error) {
		if (&packet == bufPtr && error == SUCCESS) {
			locked = FALSE;
			if (call PacketAcknowledgements.wasAcked(bufPtr)) {
				//printf("Packed acked from %u\n", last_send);
				//printfflush();
			}
			else {
				//printf("Non acked message from %u\n", last_send);
				//printf("Resending to %u\n", last_send);
				//printfflush();

				call PacketAcknowledgements.requestAck(&packet);
				if (call AMSend.send(current_node - 1, &packet, sizeof(light_msg_t)) == SUCCESS) {
					locked = TRUE;
				}
			}
		}
	}

	//message receiver handler
	event message_t* Receive.receive(message_t* bufPtr, void* payload, uint8_t len) {
		if (len == sizeof(confirm_msg_t)) {
			confirm_msg_t *msg = (confirm_msg_t*) payload;
			printf("CONTROLLER | Received confirmation from %u\n", msg -> snd);
			printfflush();
			//continue with the current light pattern
			if (resettingLights) {
				turnOffNextLed();
			}
			else if (current_pattern == TOGGLE) {
				toggleNextLed();
			}
			else if (current_pattern == CROSS_SWITCH) {
				crossNextLed();
			}
			else if (current_pattern == TRIANGLE_SWITCH) {
				triangleNextLed();
			}

			return bufPtr;
		}

		else if (len == sizeof(light_msg_t)) {
			printf("Controller received a command message. Something is wrong...\n");
			printfflush();
			return bufPtr;
		}
		else {
			//printf("ERROR!\n");
			//printfflush();
			return bufPtr;
		}
	}
}
