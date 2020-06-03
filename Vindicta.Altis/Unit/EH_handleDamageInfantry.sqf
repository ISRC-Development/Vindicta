#define OOP_ERROR
#include "..\common.h"
#include "..\Message\Message.hpp"
#include "..\MessageTypes.hpp"
#include "Unit.hpp"
#include "..\Undercover\UndercoverMonitor.hpp"
FIX_LINE_NUMBERS()
/*
Damage EH for units. Its main job is to send messages to objects.
Fires on the owner of the unit.
*/

#define pr private

params ["_unit", "_selection", "_damage", "_source", "_projectile", "_hitIndex", "_instigator", "_hitPoint"];

// Code to dump values passed to the event handler

_array = ["_unit", "_selection", "_damage", "_source", "_projectile", "_hitIndex", "_instigator", "_hitPoint"];
_str = "";
{
_str = _str + format ["%1: %2, ", _x, _this select _foreachindex];
} forEach _array;
diag_log "Handle Damage:";
diag_log _str;
diag_log "";


if (side _unit != side _source && isPlayer _source && alive _source) then { 
	REMOTE_EXEC_CALL_STATIC_METHOD("UndercoverMonitor", "onUnitCompromised", [_source], _source, false); //classNameStr, methodNameStr, extraParams, targets, JIP
};

// Return nil
// According to wiki, we can stack handlers which return nil after those which don't
// https://community.bistudio.com/wiki/Arma_3:_Event_Handlers#HandleDamage
nil;