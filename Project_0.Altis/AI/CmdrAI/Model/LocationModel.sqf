#include "..\common.hpp"

// Collection of unitCount/vehCount and their orders
CLASS("LocationModel", "ModelBase")
	// Location position
	VARIABLE("pos");
	// Side considered to be owning this location
	VARIABLE("side");
	// Model Id of the garrison currently occupying this location
	VARIABLE("garrisonId");
	// Is this location a spawn?
	VARIABLE("spawn");
	// Is this location determined by the cmdr as a staging outpost?
	// (i.e. Planned attacks will be mounted from here)
	VARIABLE("staging");

	METHOD("new") {
		params [P_THISOBJECT, P_STRING("_world"), P_STRING("_actual")];
		T_SETV("pos", []);
		T_SETV("side", objNull);
		T_SETV("garrisonId", MODEL_HANDLE_INVALID);
		T_SETV("spawn", false);
		T_SETV("staging", false);
		
		// Add self to world
		CALLM(_world, "addLocation", [_thisObject]);
	} ENDMETHOD;

	METHOD("simCopy") {
		params [P_THISOBJECT, P_STRING("_targetWorldModel")];
		private _copy = NEW("LocationModel", [_targetWorldModel]);
		// TODO: copying ID is weird because ID is actually index into array in the world model, so we can't change it.
		#ifdef OOP_ASSERT
		private _idsEqual = T_GETV("id") == GETV(_copy, "id");
		private _msg = format ["%1 id (%2) out of sync with sim copy %3 id (%4)", _thisObject, T_GETV("id"), _copy, GETV(_copy, "id")];
		ASSERT_MSG(_idsEqual, _msg);
		#endif
		SETV(_copy, "id", T_GETV("id"));
		SETV(_copy, "pos", +T_GETV("pos"));
		SETV(_copy, "side", T_GETV("side"));
		SETV(_copy, "garrisonId", T_GETV("garrisonId"));
		SETV(_copy, "spawn", T_GETV("spawn"));
		SETV(_copy, "staging", T_GETV("staging"));
		_copy
	} ENDMETHOD;
	
	METHOD("sync") {
		params [P_THISOBJECT];

		T_PRVAR(actual);
		// If we have an assigned Reak Object then sync from it
		if(_actual isEqualType "") then {
			OOP_DEBUG_1("Updating LocationModel from Location %1", _actual);
			T_SETV("pos", CALLM(_actual, "getPos", []));
			T_SETV("side", CALLM(_actual, "getSide", []));

			private _garrisonActual = CALLM(_actual, "getGarrisonMilitaryMain", []);
			if(!(_garrisonActual isEqualTo "")) then {
				T_PRVAR(world);
				private _garrison = CALLM(_world, "findGarrisonByActual", [_garrisonActual]);
				T_SETV("garrisonId", GETV(_garrison, "id"));
			} else {
				T_SETV("garrisonId", MODEL_HANDLE_INVALID);
			};
		};
	} ENDMETHOD;
	
	METHOD("getGarrison") {
		params [P_THISOBJECT];
		T_PRVAR(garrisonId);
		T_PRVAR(world);
		if(_garrisonId != MODEL_HANDLE_INVALID) exitWith { CALLM(_world, "getGarrison", [_garrisonId]) };
		objNull
	} ENDMETHOD;
		
	METHOD("clearGarrison") {
		params [P_THISOBJECT];
		T_SETV("garrisonId", MODEL_HANDLE_INVALID);
	} ENDMETHOD;

	METHOD("setGarrison") {
		params [P_THISOBJECT, P_STRING("_garr")];
		T_PRVAR(garrisonId);
		ASSERT_MSG(_garrisonId == MODEL_HANDLE_INVALID, "Can't setGarrison if location is already occupied, use clearGarrison first");
		T_SETV("garrisonId", GETV(_garr, "id"));
	} ENDMETHOD;
	
	// METHOD("attachGarrison") {
	// 	params [P_THISOBJECT, P_STRING("_garrison"), P_STRING("_outpost")];

	// 	T_CALLM1("detachGarrison", _garrison);
	// 	// private _oldOutpostId = GETV(_garrison, "outpostId");
	// 	// if(_oldOutpostId != -1) then {
	// 	// 	private _oldOutpost = T_CALLM1("getOutpostById", _oldOutpostId);
	// 	// 	SETV(_oldOutpost, "garrisonId", -1);
	// 	// 	CALLM1(_oldOutpost, "setSide", side_none);
	// 	// };
	// 	private _garrSide = CALLM0(_garrison, "getSide");
	// 	private _currGarrId = GETV(_outpost, "garrisonId");
	// 	// If there is already an attached garrison
	// 	if(_currGarrId != -1) then {
	// 		private _currGarr = T_CALLM1("getGarrisonById", _currGarrId);
	// 		// If it is friendly we will merge, other wise we do nothing (and they will fight until one is dead, at which point we can try again).
	// 		if(CALLM0(_currGarr, "getSide") == _garrSide) then {
	// 			// TODO: this should probably be an action or order instead of direct merge?
	// 			// Or maybe the garrison logic itself and handle regrouping sensibly etc.
	// 			CALLM1(_currGarr, "mergeGarrison", _garrison);
	// 		};
	// 	} else {
	// 		// Can only attach to vacant or friendly outposts
	// 		if (!GETV(_outpost, "spawn") or {CALLM0(_outpost, "getSide") == _garrSide}) then {
	// 			private _outpostId = GETV(_outpost, "id");
	// 			private _garrisonId = GETV(_garrison, "id");
	// 			SETV(_garrison, "outpostId", _outpostId);
	// 			SETV(_outpost, "garrisonId", _garrisonId);
	// 			CALLM1(_outpost, "setSide", _garrSide);
	// 		};
	// 	};
	// } ENDMETHOD;

	// METHOD("detachGarrison") {
	// 	params [P_THISOBJECT, P_STRING("_garrison")];
	// 	private _oldOutpostId = GETV(_garrison, "outpostId");
	// 	if(_oldOutpostId != -1) then {
	// 		SETV(_garrison, "outpostId", -1);
	// 		// Remove the garrison ref from the outpost if it exists and is correct
	// 		private _oldOutpost = T_CALLM1("getOutpostById", _oldOutpostId);
	// 		if(GETV(_oldOutpost, "garrisonId") == GETV(_garrison, "id")) then {
	// 			SETV(_oldOutpost, "garrisonId", -1);
	// 			// Spawns can't change sides ever...
	// 			if (!GETV(_oldOutpost, "spawn")) then {
	// 				CALLM1(_oldOutpost, "setSide", side_none);
	// 			};
	// 		};
	// 	};
	// } ENDMETHOD;
ENDCLASS;


// Unit test
#ifdef _SQF_VM

["LocationModel.new(actual)", {
	private _actual = NEW("Garrison", [WEST]);
	private _world = NEW("WorldModel", [false]);
	private _location = NEW("LocationModel", [_world] + [_actual]);
	private _class = OBJECT_PARENT_CLASS_STR(_location);
	!(isNil "_class")
}] call test_AddTest;

["LocationModel.new(sim)", {
	private _world = NEW("WorldModel", [true]);
	private _location = NEW("LocationModel", [_world]);
	private _class = OBJECT_PARENT_CLASS_STR(_location);
	!(isNil "_class")
}] call test_AddTest;

["LocationModel.delete", {
	private _world = NEW("WorldModel", [true]);
	private _location = NEW("LocationModel", [_world]);
	DELETE(_location);
	private _class = OBJECT_PARENT_CLASS_STR(_location);
	isNil "_class"
}] call test_AddTest;

#endif