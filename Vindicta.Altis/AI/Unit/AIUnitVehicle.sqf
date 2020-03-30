#include "common.hpp"

/*
Class: AI.AIUnitVehicle

Author: Sparker 12.11.2018
*/

#define pr private

CLASS("AIUnitVehicle", "AI_GOAP")

	// Array with units which are loaded into cargo space of this unit (through ace cargo system currently).
	// Doesn't list infantry units sitting on cargo infantry seats!! 
	VARIABLE("cargo");

	// Assigned crew variables
	VARIABLE("assignedDriver");
	VARIABLE("assignedCargo"); // Array of [unit, cargo index]
	VARIABLE("assignedTurrets"); // Array of [unit, turret path]

	// Indicates that this AI is new and was created recently
	// This flag aids acceleration of actions that were given to AI when it was just spawned
	VARIABLE("new");

	METHOD("new") {
		params [["_thisObject", "", [""]], ["_agent", "", [""]]];
		
		ASSERT_OBJECT_CLASS(_agent, "Unit");
		
		// Make sure that the needed MessageLoop exists
		ASSERT_GLOBAL_OBJECT(gMessageLoopGroupAI);
		
		// Initialize sensors
		
		//SETV(_thisObject, "worldState", _ws);

		T_SETV("cargo", []);

		// Set "new" flag
		T_SETV("new", true);
	} ENDMETHOD;
	
	METHOD("delete") {
		params [["_thisObject", "", [""]]];
		
		
		// Unassign all units assigned to this vehicle
		pr _units = [];
		pr _driver = GETV(_thisObject, "assignedDriver");
		if (!isNil "_driver") then {
			pr _AI = CALLM0(_driver, "getAI");
			if (! isNil "_AI") then { // Sanity checks
				if (_AI != "") then {
					CALLM0(_AI, "unassignVehicle");
				};
			};			
		};
		
		pr _cargo = GETV(_thisObject, "assignedCargo");
		if (!isNil "_cargo") then {
			{
				pr _AI = CALLM0(_x select 0, "getAI");
				if (! isNil "_AI") then { // Sanity checks
					if (_AI != "") then {
						CALLM0(_AI, "unassignVehicle");
					};
				};
			} forEach _cargo;
		};
		
		pr _turrets = GETV(_thisObject, "assignedTurrets");
		if (!isNil "_turrets") then {
			{
				pr _AI = CALLM0(_x select 0, "getAI");
				if (! isNil "_AI") then { // Sanity checks
					if (_AI != "") then {
						CALLM0(_AI, "unassignVehicle");
					};
				};
			} forEach _turrets;
		};
		
	} ENDMETHOD;

	/*
	Method: addCargoUnit
	*/
	METHOD("addCargoUnit") {
		params [P_THISOBJECT, P_OOP_OBJECT("_cargoUnit")];
		T_GETV("cargo") pushBackUnique _cargoUnit;
	} ENDMETHOD;

	/*
	Method: removeCargoUnit
	*/
	METHOD("removeCargoUnit") {
		params [P_THISOBJECT, P_OOP_OBJECT("_cargoUnit")];
		pr _cargoUnits = T_GETV("cargo");
		_cargoUnits deleteAt (_cargoUnits find _cargoUnit);
	} ENDMETHOD;

	/*
	Method: getCargo
	*/
	/* override */ METHOD("getCargoUnits") {
		params [P_THISOBJECT];
		+T_GETV("cargo")
	} ENDMETHOD;
	
	/*
	Method: unassignUnit
	Unassigns unit from this vehicle, if it was assigned. Only changes variables in this AI object.
	
	Parameters: _unit
	
	_unit - <Unit>
	
	Returns: nil
	*/
	METHOD("unassignUnit") {
		params [["_thisObject", "", [""]], ["_unit", "", [""]]];
		
		ASSERT_OBJECT_CLASS(_unit, "Unit");
		
		OOP_INFO_1("Unassigning unit: %1", _unit);
		
		// Unassign driver
		pr _driver = GETV(_thisObject, "assignedDriver");
		if (!isNil "_driver") then {
			if (_driver == _unit) then {
				OOP_INFO_0("unassigned driver");
				SETV(_thisObject, "assignedDriver", nil);
			};
		};
		
		// Unassign gunner
		/*
		pr _gunner = GETV(_thisObject, "assignedGunner");
		if (!isNil "_gunner") then {
			if (_gunner == _unit) then { SETV(_thisObject, "assignedDriver", nil);};
		};
		*/
		
		// Unassign cargo
		pr _cargo = GETV(_thisObject, "assignedCargo");
		if (!isNil "_cargo") then {
			pr _cargoThisUnit = _cargo select {_x select 0 == _unit};
			{
				_cargo deleteAt (_cargo find _x);
				OOP_INFO_0("unassigned cargo");
			} forEach _cargoThisUnit;
		};
		
		// Unassign turrets
		pr _turrets = GETV(_thisObject, "assignedTurrets");
		if (!isNil "_turrets") then {
			pr _turretsThisUnit = _turrets select {_x select 0 == _unit};
			{
				_turrets deleteAt (_turrets find _x);
				OOP_INFO_0("unassigned turret");
			} forEach _turretsThisUnit;
		};
		
	} ENDMETHOD;
	
	/*
	Method: getAssignedDriver
	Returns the <Unit> assigned as driver or "" if noone is assigned.
	
	Returns: <Unit> or ""
	*/
	METHOD("getAssignedDriver") {
		params [["_thisObject", "", [""]]];
		
		pr _driver = T_GETV("assignedDriver");
		
		if (isNil "_driver") then {
			""
		} else {
			_driver
		};		
	} ENDMETHOD;
	
	/*
	Method: getAssignedTurret
	Returns <Unit> assigned to specified turret path or "" if noone is assigned.
	
	Parameters: _turretPath
	
	_turretPath - array, turret path
	
	Returns: <Unit> or ""
	*/
	METHOD("getAssignedTurret") {
		params [["_thisObject", "", [""]], ["_turretPath", [], [[]]] ];
		pr _assignedTurrets = T_GETV("assignedTurrets");
		
		// Turret array is not initialized, therefore no turrets were assigned
		if (isNil "_assignedTurrets") exitWith {""};
		
		pr _index = _assignedTurrets findIf {(_x select 1) isEqualTo _turretPath};
		if (_index == -1) then {
			""
		} else {
			_assignedTurrets select _index select 0
		};
	} ENDMETHOD;

	/*
	Method: getAssignedTurrets
	Returns Array of <Unit> assigned to all turrets.
	Returns: Array of <Unit>
	*/
	METHOD("getAssignedTurrets") {
		params [["_thisObject", "", [""]]];
		pr _assignedTurrets = T_GETV("assignedTurrets");
		// Turret array is not initialized, therefore no turrets were assigned
		if (isNil "_assignedTurrets") exitWith {[]};
		_assignedTurrets
	} ENDMETHOD;
	/*
	Method: getAssignedCargo
	Returns <Unit> assigned to specified cargo index or "" if noone is assigned.
	
	Parameters: _cargoIndex
	
	_cargoIndex - number
	
	Returns: <Unit> or ""
	*/	
	METHOD("getAssignedCargo") {
		params [["_thisObject", "", [""]], ["_cargoIndex", 0, [0]] ];
		pr _assignedCargo = T_GETV("assignedCargo");
		
		// Cargo array is not initialized, therefore no turrets were assigned
		if (isNil "_assignedCargo") exitWith {""};
		
		pr _index = _assignedCargo findIf {(_x select 1) == _cargoIndex};
		if (_index == -1) then {
			""
		} else {
			_assignedCargo select _index select 0
		};
	} ENDMETHOD;
	
	/*
	Method: getAssignedUnits
	Returns all units assigned to this vehicle
	
	Parameters: _returnDriver, _returnTurrets, _returnCargo

	_returnDriver - Bool, optional, default: true
	_returnTurrets - Bool, optional, default: true
	_returnCargo - Bool, optional, default: true
	
	Returns: Array of <Unit>s
	*/
	METHOD("getAssignedUnits") {
		params [["_thisObject", "", [""]], ["_returnDriver", true], ["_returnTurrets", true], ["_returnCargo", true] ];
		
		pr _ret = [];
		if (_returnDriver) then {
			pr _driver = T_GETV("assignedDriver");
			if (!isNil "_driver") then { _ret pushBack _driver };
		};
		
		if (_returnTurrets) then {
			pr _turrets = T_GETV("assignedTurrets");
			if (!isNil "_turrets") then { _ret append (_turrets apply {_x select 0}) };
		};
		
		if (_returnCargo) then {
			pr _cargo = T_GETV("assignedCargo");
			if (!isNil "_cargo") then { _ret append (_cargo apply {_x select 0}) };
		};
		
		_ret
	} ENDMETHOD;
	
	// ----------------------------------------------------------------------
	// |                    G E T   M E S S A G E   L O O P
	// | The group AI resides in its own thread
	// ----------------------------------------------------------------------
	
	METHOD("getMessageLoop") {
		gMessageLoopGroupAI
	} ENDMETHOD;

ENDCLASS;