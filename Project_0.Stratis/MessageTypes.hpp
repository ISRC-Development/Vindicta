// All message types in the mission
// Author: Sparker 05.08.2018

// Location messages
// Messages
#define LOCATION_MESSAGE_PROCESS 10

// Goal messages
// This message is sent to the goal by a timer to make it call its process method
#define GOAL_MESSAGE_PROCESS	20
// Send this message to a goal so that it deletes itself
#define GOAL_MESSAGE_DELETE		21
//  Send it to a goal which was handling an animation, like sitting on a bench or
// by a campfire, when a bot has been interrupted, for example by spotting an enemy
#define GOAL_MESSAGE_ANIMATION_INTERRUPTED 22

// AnimObject messages
// Sent by a unit when he has freed a position with any reason
#define ANIM_OBJECT_MESSAGE_POS_FREE	100