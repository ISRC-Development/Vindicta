#include "common.hpp"

#define pr private

// Duration of this action
CLASS("ActionGarrisonClearArea", "ActionGarrisonBehaviour")

	VARIABLE("pos");
	VARIABLE("radius");
	VARIABLE("lastCombatDateNumber");
	VARIABLE("durationMinutes");
	VARIABLE("regroupPos");
	VARIABLE("sweepDone");
	VARIABLE("overwatchGroups");
	VARIABLE("sweepGroups");

	METHOD("new") {
		params [P_THISOBJECT, P_OOP_OBJECT("_AI"), P_ARRAY("_parameters")];

		pr _pos = CALLSM2("Action", "getParameterValue", _parameters, TAG_POS);
		T_SETV("pos", _pos);

		pr _radius = CALLSM3("Action", "getParameterValue", _parameters, TAG_CLEAR_RADIUS, 100);
		T_SETV("radius", _radius);

		pr _durationSeconds = CALLSM3("Action", "getParameterValue", _parameters, TAG_DURATION_SECONDS, 30*60);
		pr _durationMinutes = ceil (_durationSeconds / 60); // Convert from seconds to minutes
		T_SETV("durationMinutes", _durationMinutes);

		T_SETV("lastCombatDateNumber", dateToNumber date);
		T_SETV("sweepDone", false);
		T_SETV("regroupPos", []);
		T_SETV("overwatchGroups", []);
		T_SETV("sweepGroups", []);

	} ENDMETHOD;

	// logic to run when the goal is activated
	/* protected virtual */ METHOD("activate") {
		params [P_THISOBJECT, P_BOOL("_instant")];

		OOP_INFO_0("ACTIVATE");

		//pr _pos = T_GETV("pos");
		pr _AI = T_GETV("AI");
		pr _pos = T_GETV("pos");
		pr _radius = T_GETV("radius");

		pr _gar = GETV(_AI, "agent");

		// Find regroup position in the open, a safeish distance from the target
		pr _regroupPos = T_GETV("regroupPos");
		if(_regroupPos isEqualTo []) then {
			_regroupPos append ([_pos, _radius, _radius + 300, 20, 0, 0.3, 0, [], [_pos, _pos]] call BIS_fnc_findSafePos);
		};

		// Split to one group per vehicle
		// CALLM0(_gar, "splitVehicleGroups");

		// Rebalance groups, ensure all the vehicle groups have drivers, balance the infantry groups
		// We do this explictly and not as an action precondition because we will be unbalancing the groups
		// when we assign inf protection squads to vehicle groups
		// TODO: add group protect action so we can use separate inf groups
		CALLM0(_gar, "rebalanceGroups");

		// Determine group size and type
		pr _groups = CALLM0(_gar, "getGroups") apply {
			[
				CALLM0(_x, "getType") in [GROUP_TYPE_VEH_NON_STATIC],
				_x
			]
		};
		// Inf groups sorted in strength from strongest to weakest (we will assign stronger ones on sweep)
		pr _infGroups = _groups select {
			!(_x#0)
		} apply {
			private _grp = _x#1;
			[
				count CALLM0(_grp, "getUnits"),
				_grp
			]
		};
		_infGroups sort DESCENDING;
		// Inf groups big enough to be useful
		pr _mainInfGroups = _infGroups select {
			(_x#0) > 5
		} apply {
			_x#1
		};
		_infGroups = _infGroups apply {
			_x#1
		};

		// Vehicle groups sorted by strength from weakest to strongest (we will assign weaker ones on sweep)
		pr _vehGroups = _groups select {
			_x#0
		} apply {
			private _grp = _x#1;
			private _vics = CALLM0(_grp, "getVehicleUnits");
			private _totalEff = 0;
			{
				private _eff = CALLM0(_x, "getEfficiency");
				_totalEff = _totalEff + _eff#T_EFF_aSoft + _eff#T_EFF_aMedium * 4 + _eff#T_EFF_aArmor * 8;
			} forEach _vics;
			[
				_totalEff,
				_grp
			]
		} select {
			// Only want combat capable vehicle groups for duties
			_x#0 > 0
		};
		_vehGroups sort ASCENDING;
		_vehGroups = _vehGroups apply {
			_x#1
		};

		// We want to assign groups to appropriate tasks:
		//	inf/veh group to sweep
		//	inf/veh group to overwatch
		//	veh groups to overwatch
		//	inf groups to cover vehicles
		//	inf groups to sweep
		_fn_takeOne = {
			params["_prefer", "_fallback", "_target", "_validChoices"];

			private _arr = [
				_prefer arrayIntersect _validChoices,
				_fallback arrayIntersect _validChoices
			] select (count (_prefer arrayIntersect _validChoices) == 0);

			if(count _arr > 0) then {
				private _one = _arr#0;
				_target pushBack _one;
				_prefer deleteAt (_prefer find _one);
				_fallback deleteAt (_fallback find _one);
				_one
			} else {
				NULL_OBJECT
			};
		};

		pr _vehGroupsForInfAssignment = +_vehGroups;
		pr _vehGroupsOrig = +_vehGroups;

		pr _sweep = [];
		pr _overwatch = [];

		// // inf/veh group to sweep
		[_infGroups, _vehGroups, _sweep, _mainInfGroups + _vehGroups] call _fn_takeOne;
		// // inf/veh group to overwatch
		//[_vehGroups, _infGroups, _overwatch] call _fn_takeOne;

		// veh groups to overwatch
		_overwatch append _vehGroups;

		// inf groups to cover vehicles
		private _remainingInf = [];
		{
			_remainingInf append CALLM0(_x, "getInfantryUnits");
		} forEach _infGroups;
		
		// Can't do it like this as follow groups can't apply instant behavior reliably.
		// They might be executed instantly before the group they are following is teleported.
		// private _support = [];
		// while {count _remainingInf > 0 && count _vehGroupsForInfAssignment > 0} do {
		// 	private _vehGroup = _vehGroupsForInfAssignment deleteAt 0;

		// 	// Create a group, add it to the garrison
		// 	private _supportGroup = NEW("Group", [_side ARG GROUP_TYPE_IDLE]);
		// 	CALLM0(_supportGroup, "spawnAtLocation");
		// 	CALLM1(_gar, "addGroup", _supportGroup);

		// 	private _unitsToAdd = _remainingInf select [0, MINIMUM(4, count _remainingInf)];
		// 	_remainingInf = _remainingInf - _unitsToAdd;

		// 	CALLM1(_supportGroup, "addUnits", _unitsToAdd);

		// 	pr _groupAI = CALLM0(_supportGroup, "getAI");
		// 	pr _args = ["GoalGroupOverwatchArea", 0, [[TAG_TARGET, CALLM0(_vehGroup, "getGroupHandle")]] + _commonTags, _AI];
		// 	CALLM2(_groupAI, "postMethodAsync", "addExternalGoal", _args);
		// 	_support pushBack [_supportGroup, _vehGroup];
		// };

		while {count _remainingInf > 0 && count _vehGroupsForInfAssignment > 0} do {
			private _vehGroup = _vehGroupsForInfAssignment deleteAt 0;
			private _count = 0;
			while {_count < 4 && count _remainingInf > 0} do
			{
				private _inf = _remainingInf deleteAt 0;
				CALLM1(_vehGroup, "addUnit", _inf);
			};
		};
		_infGroups = _infGroups select { !CALLM0(_x, "isEmpty") };

		// inf groups to sweep
		_sweep append _infGroups;

		// Clean up
		CALLM0(_gar, "deleteEmptyGroups");

		if(count _overwatch > 0) then {
			private _commonTags = [
				[TAG_POS, _pos],
				[TAG_CLEAR_RADIUS, _radius],
				[TAG_OVERWATCH_ELEVATION, 20],
				[TAG_BEHAVIOUR, "STEALTH"],
				[TAG_COMBAT_MODE, "RED"],
				[TAG_INSTANT, _instant],
				[TAG_OVERWATCH_DISTANCE_MIN, CLAMP(_radius, 250, 500)],
				[TAG_OVERWATCH_DISTANCE_MAX, CLAMP(_radius, 250, 500) + 250]
			];
			private _dDir = 360 / count _overwatch;
			private _dir = random 360;
			{// foreach _overwatch
				pr _groupAI = CALLM0(_x, "getAI");
				pr _args = ["GoalGroupOverwatchArea", 0, [[TAG_OVERWATCH_DIRECTION, _dir]] + _commonTags, _AI];
				CALLM2(_groupAI, "postMethodAsync", "addExternalGoal", _args);
				_dir = _dir + _dDir;
			} forEach _overwatch;
		};

		{// foreach _sweep
			pr _groupAI = CALLM0(_x, "getAI");
			pr _args = [
				"GoalGroupClearArea",
				0,
				[
					[TAG_POS, _pos],
					[TAG_CLEAR_RADIUS, _radius],
					[TAG_BEHAVIOUR, "AWARE"],
					[TAG_COMBAT_MODE, "RED"],
					[TAG_SPEED_MODE, "LIMITED"],
					[TAG_INSTANT, _instant]
				],
				_AI
			];
			CALLM2(_groupAI, "postMethodAsync", "addExternalGoal", _args);
		} forEach _sweep;

		T_SETV("sweepGroups", _sweep);
		T_SETV("overwatchGroups", _overwatch);

		// Set last combat date
		T_SETV("lastCombatDateNumber", dateToNumber date);

		// Set state
		T_SETV("state", ACTION_STATE_ACTIVE);

		// Return ACTIVE state
		ACTION_STATE_ACTIVE

	} ENDMETHOD;

	// logic to run each update-step
	/* public virtual */ METHOD("process") {
		params [P_THISOBJECT];

		pr _gar = T_GETV("gar");

		// Succeed after timeout if not spawned.
		if (!CALLM0(_gar, "isSpawned")) exitWith {

			pr _state = T_GETV("state");

			if (_state == ACTION_STATE_INACTIVE) then {
				// Set last combat date
				T_SETV("lastCombatDateNumber", dateToNumber date);
				_state = ACTION_STATE_ACTIVE;
			};

			pr _lastCombatDateNumber = T_GETV("lastCombatDateNumber");
			pr _dateNumberThreshold = dateToNumber [date#0,1,1,0, T_GETV("durationMinutes")];
			if (( (dateToNumber date) - _lastCombatDateNumber) > _dateNumberThreshold ) then {
				T_SETV("state", ACTION_STATE_COMPLETED);
				_state = ACTION_STATE_COMPLETED;
			} else {
				pr _timeLeft = numberToDate [date#0, _lastCombatDateNumber + _dateNumberThreshold - (dateToNumber date)];
				OOP_INFO_1("Clearing area, time left: %1", _timeLeft);
				_state = ACTION_STATE_ACTIVE;
			};

			T_SETV("state", _state);
			_state
		};

		pr _state = T_CALLM0("activateIfInactive");
		if (_state == ACTION_STATE_ACTIVE) then {
			pr _AI = T_GETV("AI");
			
			// Check if we know about enemies
			pr _ws = GETV(_AI, "worldState");
			pr _awareOfEnemy = [_ws, WSP_GAR_AWARE_OF_ENEMY] call ws_getPropertyValue;
			
			if (_awareOfEnemy) then {
				T_SETV("lastCombatDateNumber", dateToNumber date); // Reset the timer
				T_SETV("sweepDone", false);
				pr _sweepGroups = T_GETV("sweepGroups");

				// Top priority goal. 
				T_CALLM1("attackEnemyBuildings", _sweepGroups); // Attack buildings occupied by enemies
			} else {
				pr _lastCombatDateNumber = T_GETV("lastCombatDateNumber");
				pr _dateNumberThreshold = dateToNumber [date#0,1,1,0, T_GETV("durationMinutes")];
				if (( (dateToNumber date) - _lastCombatDateNumber) > _dateNumberThreshold ) then {
					pr _sweepDone = T_GETV("sweepDone");
					pr _regroupPos = T_GETV("regroupPos");
					// Regroup
					pr _groups = CALLM0(_gar, "getGroups");
					if(_sweepDone) then {
						switch true do {
							// Fail if any group has failed
							case (CALLSM3("AI_GOAP", "anyAgentFailedExternalGoal", _groups, "GoalGroupMove", _AI)): {
								_state = ACTION_STATE_FAILED
							};
							// Succeed if all groups have completed the goal
							case (CALLSM3("AI_GOAP", "allAgentsCompletedExternalGoalRequired", _groups, "GoalGroupMove", _AI)): {
								_state = ACTION_STATE_COMPLETED
							};
						};
						// pr _maxDist = 0;
						// {
						// 	_maxDist = _maxDist max (_regroupPos distance2D CALLM0(_x, "getPos"));
						// } forEach _groups;
						// if(_maxDist < 100) then {
						// 	_state = ACTION_STATE_COMPLETED;
						// };
						// if()
					} else {
						T_CALLM0("clearGroupGoals");
						{
							pr _group = _x;
							pr _groupAI = CALLM0(_x, "getAI");
							// Add new goal to move to rally point
							pr _args = ["GoalGroupMove",  0, [
								[TAG_POS, _regroupPos],
								[TAG_BEHAVIOUR, "AWARE"],
								[TAG_COMBAT_MODE, "RED"],
								[TAG_SPEED_MODE, "NORMAL"],
								[TAG_MOVE_RADIUS, 100]
							], _AI];
							CALLM2(_groupAI, "postMethodAsync", "addExternalGoal", _args);
						} forEach _groups;

						T_SETV("sweepDone", true);
					};
				} else {
					pr _timeLeft = numberToDate [date#0, _lastCombatDateNumber + _dateNumberThreshold - (dateToNumber date)];
					OOP_INFO_1("Clearing area, time left: %1", _timeLeft);
				};
			};
		};

		// Return the current state
		T_SETV("state", _state);
		_state
	} ENDMETHOD;

	// // logic to run when the action is satisfied
	// /* protected virtual */ METHOD("terminate") {
	// 	params [P_THISOBJECT];

	// 	// Bail if not spawned
	// 	pr _gar = T_GETV("gar");
	// 	if (!CALLM0(_gar, "isSpawned")) exitWith {};

	// 	// Remove all assigned goals
	// 	T_CALLM0("clearGroupGoals");
	// } ENDMETHOD;
	
	// /* protected virtual */ METHOD("onGarrisonSpawned") {
	// 	params [P_THISOBJECT];

	// 	// Reset action state so that it reactivates
	// 	T_SETV("state", ACTION_STATE_INACTIVE);
	// } ENDMETHOD;

	// METHOD("_assignSweepGoals") {
	// 	params [P_THISOBJECT];

	// 	pr _AI = T_GETV("AI");
	// 	pr _pos = T_GETV("pos");
	// 	pr _radius = T_GETV("radius");

	// 	private _sweepGroups = T_GETV("sweepGroups");

	// 	{// foreach _sweep
	// 		pr _groupAI = CALLM0(_x, "getAI");
	// 		pr _args = [
	// 			"GoalGroupClearArea",
	// 			0,
	// 			[
	// 				[TAG_POS, _pos],
	// 				[TAG_CLEAR_RADIUS, _radius],
	// 				[TAG_BEHAVIOUR, "COMBAT"],
	// 				[TAG_COMBAT_MODE, "RED"]
	// 			],
	// 			_AI
	// 		];
	// 		CALLM2(_groupAI, "postMethodAsync", "addExternalGoal", _args);
	// 	} forEach _sweepGroups;
	// } ENDMETHOD;
	
	
	// procedural preconditions
	// POS world state property comes from action parameters
	/*
	// Don't have these preconditions any more, they are supplied by goal instead
	STATIC_METHOD("getPreconditions") {
		params [P_THISCLASS, P_ARRAY("_goalParameters"), P_ARRAY("_actionParameters")];
		
		pr _pos = CALLSM2("Action", "getParameterValue", _actionParameters, TAG_POS);
		pr _ws = [WSP_GAR_COUNT] call ws_new;
		[_ws, WSP_GAR_POSITION, _pos] call ws_setPropertyValue;
		
		_ws			
	} ENDMETHOD;
	*/
	
ENDCLASS;