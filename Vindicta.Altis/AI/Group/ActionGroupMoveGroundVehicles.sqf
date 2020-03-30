#include "common.hpp"

/*
Class: ActionGroup.ActionGroupMoveGroundVehicles
Handles moving of a group with multiple or single ground vehicles.

Tags:
TAG_POS
TAG_MOVE_RADIUS
TAG_MAX_SPEED_KMH
*/

#define pr private

// Needed vehicle separation in meters
#define SEPARATION 18
#define SPEED_MAX 50
#define SPEED_MIN 5

#ifndef RELEASE_BUILD
#define DEBUG_FORMATION
#endif

CLASS("ActionGroupMoveGroundVehicles", "ActionGroup")

	VARIABLE("pos");
	VARIABLE("radius"); // Completion radius
	VARIABLE("speedLimit"); // The current speed limit
	VARIABLE("maxSpeed"); // The maximum speed in this action, can be received as parameter
	VARIABLE("time");
	VARIABLE("route"); // Optional route to use, or just give one waypoint if no route was given
	
	METHOD("new") {
		params [P_THISOBJECT, P_OOP_OBJECT("_AI"), P_ARRAY("_parameters")];
		
		pr _pos = CALLSM2("Action", "getParameterValue", _parameters, TAG_POS);
		T_SETV("pos", _pos);

		pr _radius = CALLSM3("Action", "getParameterValue", _parameters, TAG_MOVE_RADIUS, 20);
		T_SETV("radius", _radius);

		pr _maxSpeedKmh = CALLSM3("Action", "getParameterValue", _parameters, TAG_MAX_SPEED_KMH, SPEED_MAX);
		T_SETV("maxSpeed", _maxSpeedKmh);

		// Route can be optionally passed or not
		pr _route = CALLSM3("Action", "getParameterValue", _parameters, TAG_ROUTE, []);
		T_SETV("route", _route);

		T_SETV("time", time);
		
		T_SETV("speedLimit", SPEED_MIN);
	} ENDMETHOD;
	
	// logic to run when the goal is activated
	METHOD("activate") {
		params [P_THISOBJECT];
		
		pr _hG = T_GETV("hG");
		pr _AI = T_GETV("AI");
		pr _group = GETV(_AI, "agent");
		pr _allVehicleUnits = CALLM0(_group, "getUnits") select {CALLM0(_x, "isVehicle")};
		pr _allVehicles = _allVehicleUnits apply {CALLM0(_x, "getObjectHandle")};
		pr _vehLead = vehicle (leader (CALLM0(_group, "getGroupHandle")));
		
		// Regroup units by distance
		pr _leader = CALLM0(_group, "getLeader");
		if (_leader == "") exitWith {
			OOP_ERROR_1("Group has no leader: %1", _group);
			T_SETV("state", ACTION_STATE_FAILED);
			ACTION_STATE_FAILED
		};
		if (count _allVehicles > 1) then {
			pr _distAndUnits = (CALLM0(_group, "getUnits") - [_leader]) apply {
				pr _hO = CALLM0(_x, "getObjectHandle");
				[_hO distance _vehLead, _x];
			};
			_distAndUnits sort true; // Ascending
			CALLM2(_group, "postMethodAsync", "sort", [_distAndUnits apply {_x select 1}]); // Post message to sort the group
		};
		
		T_CALLM0("clearWaypoints");
		T_CALLM4("applyGroupBehaviour", "COLUMN", "CARELESS", "YELLOW", "NORMAL");

		// Turn on sirens if we have them
		{
			pr _gar = CALLM0(_x, "getGarrison");
			pr _t = CALLM0(_gar, "getTemplate");
			pr _hO = CALLM0(_x, "getObjectHandle");
			[_t, T_API, T_API_fnc_VEH_siren, [_hO, true]] call t_fnc_callAPIOptional;
		} forEach _allVehicleUnits;

		// Give a waypoint to move
		/*
		pr _wp = _hG addWaypoint [_pos, 0];
		_wp setWaypointType "MOVE";
		_wp setWaypointFormation "COLUMN";
		_wp setWaypointBehaviour "SAFE";
		_wp setWaypointCombatMode "GREEN";
		_hG setCurrentWaypoint _wp;
		*/
		{
			private _vehHandle = _x;
			_vehHandle limitSpeed 666666; //Set the speed of all vehicles to unlimited
			_vehHandle setConvoySeparation SEPARATION;
			//_vehHandle forceFollowRoad true;
		} forEach _allVehicles;
		(vehicle (leader _hG)) limitSpeed T_GETV("speedLimit");
		
		// Set time last called
		T_SETV("time", time);

		pr _leader = CALLM0(_group, "getLeader");
		if (_leader != NULL_OBJECT) then {
			if (CALLM0(_leader, "isAlive")) then {
				// Add follow goals for units other than the leader
				{
					pr _unitAI = CALLM0(_x, "getAI");
					if (CALLM0(_unitAI, "getAssignedVehicleRole") == "DRIVER") then {
						CALLM4(_unitAI, "addExternalGoal", "GoalUnitFollowLeaderVehicle", 0, [], _AI);
					};
				} forEach (CALLM0(_group, "getInfantryUnits") - [_leader]);
				
				// Add move goal to leader
				pr _leaderAI = CALLM0(_leader, "getAI");
				pr _parameters = [[TAG_POS, T_GETV("pos")], [TAG_MOVE_RADIUS, T_GETV("radius")], [TAG_ROUTE, T_GETV("route")]];
				CALLM4(_leaderAI, "addExternalGoal", "GoalUnitMoveLeaderVehicle", 0, _parameters, _AI);

				T_SETV("state", ACTION_STATE_ACTIVE);
				ACTION_STATE_ACTIVE
			} else {
				// Fail if leader is not alive
				T_SETV("state", ACTION_STATE_FAILED);
				ACTION_STATE_FAILED
			};
		} else {
			// leader is NULL_OBJECT, wtf
			OOP_ERROR_1("Group has no leader: %1", _group);
			T_SETV("state", ACTION_STATE_FAILED);
			ACTION_STATE_FAILED
		};

	} ENDMETHOD;
	
	// Logic to run each update-step
	METHOD("process") {
		params [P_THISOBJECT];
		
		CALLM0(_thisObject, "failIfNoInfantry");
		
		pr _state = CALLM0(_thisObject, "activateIfInactive");

		if (_state == ACTION_STATE_ACTIVE) then {
			pr _hG = T_GETV("hG"); // Group handle
			pr _pos = T_GETV("pos");
			pr _radius = T_GETV("radius");
			
			pr _dt = time - T_GETV("time") + 0.001;
			T_SETV("time", time);
			
			//Check the separation of the convoy
			private _sCur = CALLM0(_thisObject, "getMaxSeparation"); //The current maximum separation between vehicles
			#ifdef DEBUG_FORMATION
			OOP_DEBUG_MSG(">>> Current separation: %1", [_sCur]);
			#endif
			if(_sCur > 3 * SEPARATION) then
			{
				//We are driving too fast!
				pr _speedLimit = T_GETV("speedLimit");
				if(_speedLimit > SPEED_MIN) then
				{
					_speedLimit = (_speedLimit - _dt*2) max SPEED_MIN;
					T_SETV("speedLimit", _speedLimit);
					(vehicle (leader _hG)) limitSpeed _speedLimit;
					#ifdef DEBUG_FORMATION
					OOP_DEBUG_MSG(">>> Slowing down! New speed: %1", [_speedLimit]);
					#endif
				};
			}
			else
			{
				//We are driving too slow!
				pr _speedLimit = T_GETV("speedLimit");
				if(_speedLimit < T_GETV("maxSpeed")) then
				{
					_speedLimit = (_speedLimit + _dt*4) min T_GETV("maxSpeed");
					T_SETV("speedLimit", _speedLimit);
					(vehicle (leader _hG)) limitSpeed _speedLimit;
					#ifdef DEBUG_FORMATION
					OOP_DEBUG_MSG(">>> Accelerating! New speed: %1", [_speedLimit]);
					#endif
				};
			};

			// Check if enough vehicles have arrived
			// For now just check if leader is there
			pr _radius = T_GETV("radius");
			if (( (vehicle leader _hG) distance _pos ) < _radius) then {
				OOP_INFO_0("Arrived at destination");
				_state = ACTION_STATE_COMPLETED
			};

			pr _group = GETV(T_GETV("AI"), "agent");
			pr _leader = CALLM0(_group, "getLeader");
			if (_leader != NULL_OBJECT) then {
				if (CALLM0(_leader, "isAlive")) then {
					pr _units = CALLM0(_group, "getUnits");
					// If any units failed their goals
					if(CALLSM2("AI_GOAP", "anyAgentFailedExternalGoal", _units, "GoalUnitFollowLeaderVehicle") || 
						CALLSM2("AI_GOAP", "anyAgentFailedExternalGoal", _units, "GoalUnitMoveLeaderVehicle")) then {
						_state = ACTION_STATE_FAILED;
					};
				} else {
					// Fail if leader is not alive
					_state = ACTION_STATE_FAILED;
				};
			} 
		};
		T_SETV("state", _state);
		_state
	} ENDMETHOD;
	
	//Gets the maximum separation between vehicles in convoy
	METHOD("getMaxSeparation") {
		params [P_THISOBJECT];

		pr _group = GETV(T_GETV("AI"), "agent");
		pr _allVehicles = CALLM0(_group, "getVehicleUnits") apply {CALLM0(_x, "getObjectHandle")};
		if(count _allVehicles <= 1) exitWith {
			0
		};

		pr _vehLead = vehicle (leader (CALLM0(_group, "getGroupHandle")));
		
		//diag_log format ["All vehicles: %1", _allVehicles];
		//diag_log format ["Lead vehicle: %1", _vehLead];
		private _vehArraySort = _allVehicles apply {[_x distance _vehLead, _x]};

		//diag_log format ["Unsorted array: %1", _vehArraySort];
		_vehArraySort sort ASCENDING;
		//diag_log format ["Sorted array: %1", _vehArraySort];
		//Get the max separation
		private _dMax = 0;
		private _c = count _allVehicles;
		for "_i" from 0 to (_c - 2) do
		{
			_d = (_vehArraySort select _i select 1) distance (_vehArraySort select (_i + 1) select 1);
			if (_d > _dMax) then {_dMax = _d;};
		};
		_dMax
		
	} ENDMETHOD;
	
	METHOD("handleUnitsRemoved") {
		params [P_THISOBJECT, P_ARRAY("_units")];
		
	} ENDMETHOD;
	
	// logic to run when the action is satisfied
	METHOD("terminate") {
		params [P_THISOBJECT];
		
		// Delete waypoints
		T_CALLM0("clearWaypoints");

		pr _hG = T_GETV("hG");

		// Add a move waypoint at the current position of the leader
		pr _wp = _hG addWaypoint [getPos leader _hG, 0];
		_wp setWaypointType "MOVE";
		_hG setCurrentWaypoint _wp;
		doStop (leader _hG);
		
		pr _AI = T_GETV("AI");
		pr _group = GETV(_AI, "agent");
		// Delete given goals
		pr _groupUnits = CALLM0(_group, "getUnits");
		{
			pr _unitAI = CALLM0(_x, "getAI");
			CALLM2(_unitAI, "deleteExternalGoal", "GoalUnitFollowLeaderVehicle", _AI);
			CALLM2(_unitAI, "deleteExternalGoal", "GoalUnitMoveLeaderVehicle", _AI);
		} forEach _groupUnits;
		
	} ENDMETHOD;

ENDCLASS;