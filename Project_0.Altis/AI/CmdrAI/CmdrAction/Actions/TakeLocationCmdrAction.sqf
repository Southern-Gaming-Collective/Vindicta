#include "..\..\common.hpp"

CLASS("TakeLocationCmdrAction", "TakeOrJoinCmdrAction")
	VARIABLE("tgtLocId");

	METHOD("new") {
		params [P_THISOBJECT, P_NUMBER("_srcGarrId"), P_NUMBER("_tgtLocId")];

		T_SETV("tgtLocId", _tgtLocId);

		// Target can be modified during the action, if the initial target dies, so we want it to save/restore.
		T_SET_AST_VAR("targetVar", [TARGET_TYPE_LOCATION ARG _tgtLocId]);

#ifdef DEBUG_CMDRAI
		T_SETV("debugColor", "ColorBlue");
		T_SETV("debugSymbol", "mil_flag")
#endif
	} ENDMETHOD;

	/* protected override */ METHOD("updateIntel") {
		params [P_THISOBJECT, P_OOP_OBJECT("_world")];
		ASSERT_OBJECT_CLASS(_world, "WorldModel");
		ASSERT_MSG(CALLM(_world, "isReal", []), "Can only updateIntel from real world, this shouldn't be possible as updateIntel should ONLY be called by CmdrAction");

		T_PRVAR(intel);
		private _intelNotCreated = IS_NULL_OBJECT(_intel);
		if(_intelNotCreated) then
		{
			// Create new intel object and fill in the constant values
			_intel = NEW("IntelCommanderActionAttack", []);

			T_PRVAR(srcGarrId);
			T_PRVAR(tgtLocId);
			private _srcGarr = CALLM(_world, "getGarrison", [_srcGarrId]);
			ASSERT_OBJECT(_srcGarr);
			private _tgtLoc = CALLM(_world, "getLocation", [_tgtLocId]);
			ASSERT_OBJECT(_tgtLoc);

			CALLM(_intel, "create", []);

			SETV(_intel, "type", "Take Location");
			SETV(_intel, "side", GETV(_srcGarr, "side"));
			SETV(_intel, "srcGarrison", GETV(_srcGarr, "actual"));
			SETV(_intel, "posSrc", GETV(_srcGarr, "pos"));
			SETV(_intel, "tgtLocation", GETV(_tgtLoc, "actual"));
			SETV(_intel, "location", GETV(_tgtLoc, "actual"));
			SETV(_intel, "posTgt", GETV(_tgtLoc, "pos"));

			T_CALLM("updateIntelFromDetachment", [_world ARG _intel]);

			// If we just created this intel then register it now 
			private _intelClone = CALL_STATIC_METHOD("AICommander", "registerIntelCommanderAction", [_intel]);
			T_SETV("intel", _intelClone);

			// Send the intel to some places that should "know" about it
			T_CALLM("addIntelAt", [_world ARG GETV(_srcGarr, "pos")]);
			T_CALLM("addIntelAt", [_world ARG GETV(_tgtLoc, "pos")]);
		} else {
			T_CALLM("updateIntelFromDetachment", [_world ARG _intel]);
			CALLM(_intel, "updateInDb", []);
		};
	} ENDMETHOD;

	/* override */ METHOD("updateScore") {
		params [P_THISOBJECT, P_STRING("_worldNow"), P_STRING("_worldFuture")];
		ASSERT_OBJECT_CLASS(_worldNow, "WorldModel");
		ASSERT_OBJECT_CLASS(_worldFuture, "WorldModel");

		T_PRVAR(srcGarrId);
		T_PRVAR(tgtLocId);

		private _srcGarr = CALLM(_worldNow, "getGarrison", [_srcGarrId]);
		ASSERT_OBJECT(_srcGarr);
		if(CALLM(_srcGarr, "isDead", [])) exitWith {
			T_CALLM("setScore", [ZERO_SCORE]);
		};

		private _tgtLoc = CALLM(_worldFuture, "getLocation", [_tgtLocId]);
		ASSERT_OBJECT(_tgtLoc);
		private _side = GETV(_srcGarr, "side");
		private _toGarr = CALLM(_tgtLoc, "getGarrison", [_side]);
		if(!IS_NULL_OBJECT(_toGarr)) exitWith {
			// We never take a location we already have a garrison at, this should be reinforcement instead 
			// (however we can get here if multiple potential actions are generated targetting the same location
			// in the same planning cycle, and one gets accepted)
			T_CALLM("setScore", [ZERO_SCORE]);
		};

		// switch  do {
		// 	case LOCATION_TYPE_ROADBLOCK: { "mil_triangle" };
		// 	case LOCATION_TYPE_BASE: { "mil_circle" };
		// 	case LOCATION_TYPE_OUTPOST: { "mil_box" };
		// 	default { "mil_dot" };
		// }
		// Resource is how much src is *over* composition, scaled by distance (further is lower)
		// i.e. How much units/vehicles src can spare.
		private _detachEff = T_CALLM("getDetachmentEff", [_worldNow ARG _worldFuture]);
		// Save the calculation for use if we decide to perform the action 
		// We DON'T want to try and recalculate the detachment against the real world state when the action actually runs because
		// it won't be correctly taking into account our knowledge about other actions (as represented in the sim world models)
		T_SET_AST_VAR("detachmentEffVar", _detachEff);

		//CALLM1(_worldNow, "getOverDesiredEff", _srcGarr);
		private _detachEffStrength = EFF_SUB_SUM(EFF_DEF_SUB(_detachEff));

		private _srcGarrPos = GETV(_srcGarr, "pos");
		private _tgtLocPos = GETV(_tgtLoc, "pos");

		private _distCoeff = CALLSM("CmdrAction", "calcDistanceFalloff", [_srcGarrPos ARG _tgtLocPos]);
		private _dist = _srcGarrPos distance _tgtLocPos;
		private _transportationScore = if(_dist < 2000) then {
			T_SET_AST_VAR("splitFlagsVar", [FAIL_UNDER_EFF ARG OCCUPYING_FORCE_HINT]);
			1
		} else {
			// We will force transport on top of scoring if we need to.
			T_SET_AST_VAR("splitFlagsVar", [ASSIGN_TRANSPORT ARG FAIL_UNDER_EFF ARG CHEAT_TRANSPORT ARG OCCUPYING_FORCE_HINT]);
			CALLM(_srcGarr, "transportationScore", [_detachEff])
		};

		private _strategy = CALL_STATIC_METHOD("AICommander", "getCmdrStrategy", [_side]);

		private _scoreResource = _detachEffStrength * _distCoeff * _transportationScore;
		private _scorePriority = CALLM(_strategy, "getLocationDesirability", [_worldNow ARG _tgtLoc ARG _side]);

		// Work out time to start based on how much force we mustering and distance we are travelling.
		// https://www.desmos.com/calculator/mawpkr88r3 * https://www.desmos.com/calculator/0vb92pzcz8
#ifndef RELEASE_BUILD
		private _delay = random 2;
#else
		private _delay = 50 * log (0.1 * _detachEffStrength + 1) * (1 + 2 * log (0.0003 * _dist + 1)) * 0.1 + 2 + random 18;
#endif

		// Shouldn't need to cap it, the functions above should always return something reasonable, if they don't then fix them!
		// _delay = 0 max (120 min _delay);
		private _startDate = DATE_NOW;

		_startDate set [4, _startDate#4 + _delay];

		T_SET_AST_VAR("startDateVar", _startDate);

		// OOP_DEBUG_MSG("[w %1 a %2] %3 take %4 Score %5, _detachEff = %6, _detachEffStrength = %7, _distCoeff = %8, _transportationScore = %9",
		// 	[_worldNow ARG _thisObject ARG LABEL(_srcGarr) ARG LABEL(_tgtLoc) ARG [_scorePriority ARG _scoreResource] 
		// 	ARG _detachEff ARG _detachEffStrength ARG _distCoeff ARG _transportationScore]);
		private _baseScore = MAKE_SCORE_VEC(_scorePriority, _scoreResource, 1, 1);
		private _score = CALLM(_strategy, "getTakeLocationScore", [_thisObject ARG _baseScore ARG _worldNow ARG _worldFuture ARG _srcGarr ARG _tgtLoc ARG _detachEff]);
		T_CALLM("setScore", [_score]);

		#ifdef OOP_INFO
		private _str = format ["{""cmdrai"": {""side"": ""%1"", ""action_name"": ""TakeOutpost"", ""src_garrison"": ""%2"", ""tgt_location"": ""%3"", ""score_priority"": %4, ""score_resource"": %5, ""score_strategy"": %6, ""score_completeness"": %7}}", 
			_side, LABEL(_srcGarr), LABEL(_tgtLoc), _score#0, _score#1, _score#2, _score#3];
		OOP_INFO_MSG(_str, []);
		#endif
	} ENDMETHOD;

	// Get composition of reinforcements we should send from src to tgt. 
	// This is the min of what src has spare and what tgt wants.
	// TODO: factor out logic for working out detachments for various situations
	/* private */ METHOD("getDetachmentEff") {
		params [P_THISOBJECT, P_STRING("_worldNow"), P_STRING("_worldFuture")];
		ASSERT_OBJECT_CLASS(_worldNow, "WorldModel");
		ASSERT_OBJECT_CLASS(_worldFuture, "WorldModel");

		T_PRVAR(srcGarrId);
		T_PRVAR(tgtLocId);

		private _srcGarr = CALLM(_worldNow, "getGarrison", [_srcGarrId]);
		ASSERT_OBJECT(_srcGarr);
		private _tgtLoc = CALLM(_worldFuture, "getLocation", [_tgtLocId]);
		ASSERT_OBJECT(_tgtLoc);

		// How much resources src can spare.
		private _srcOverEff = EFF_MAX_SCALAR(CALLM(_worldNow, "getOverDesiredEff", [_srcGarr]), 0);

		// How much resources tgt needs
		private _tgtRequiredEff = CALLM(_worldNow, "getDesiredEff", [GETV(_tgtLoc, "pos")]);
		// EFF_MAX_SCALAR(EFF_MUL_SCALAR(CALLM(_worldFuture, "getOverDesiredEff", [_tgtLoc]), -1), 0);

		// Min of those values
		// TODO: make this a "nice" composition. We don't want to send a bunch of guys to walk or whatever.
		private _effAvailable = EFF_MAX_SCALAR(EFF_FLOOR(EFF_MIN(_srcOverEff, _tgtRequiredEff)), 0);

		//OOP_DEBUG_MSG("[w %1 a %2] %3 take %4 getDetachmentEff: _tgtRequiredEff = %5, _srcOverEff = %6, _effAvailable = %7", [_worldNow ARG _thisObject ARG _srcGarr ARG _tgtLoc ARG _tgtRequiredEff ARG _srcOverEff ARG _effAvailable]);

		// Only send a reasonable amount at a time
		// TODO: min compositions should be different for detachments and garrisons holding outposts.
		if(!EFF_GTE(_effAvailable, EFF_MIN_EFF)) exitWith { EFF_ZERO };

		//if(_effAvailable#0 < MIN_COMP#0 or _effAvailable#1 < MIN_COMP#1) exitWith { [0,0] };
		_effAvailable
	} ENDMETHOD;
ENDCLASS;

#ifdef _SQF_VM

#define SRC_POS [0, 0, 0]
#define TARGET_POS [1, 2, 3]

["TakeLocationCmdrAction", {
	private _realworld = NEW("WorldModel", [WORLD_TYPE_REAL]);
	private _world = CALLM(_realworld, "simCopy", [WORLD_TYPE_SIM_NOW]);
	private _garrison = NEW("GarrisonModel", [_world]);
	private _srcEff = [100,100,100,100,100,100,100,100];
	SETV(_garrison, "efficiency", _srcEff);
	SETV(_garrison, "pos", SRC_POS);
	SETV(_garrison, "side", WEST);

	private _targetLocation = NEW("LocationModel", [_world]);
	SETV(_targetLocation, "pos", TARGET_POS);

	private _thisObject = NEW("TakeLocationCmdrAction", [GETV(_garrison, "id") ARG GETV(_targetLocation, "id")]);
	
	private _future = CALLM(_world, "simCopy", [WORLD_TYPE_SIM_FUTURE]);
	CALLM(_thisObject, "updateScore", [_world ARG _future]);

	private _nowSimState = CALLM(_thisObject, "applyToSim", [_world]);
	private _futureSimState = CALLM(_thisObject, "applyToSim", [_future]);
	["Now sim state correct", _nowSimState == CMDR_ACTION_STATE_READY_TO_MOVE] call test_Assert;
	["Future sim state correct", _futureSimState == CMDR_ACTION_STATE_END] call test_Assert;
	
	private _futureLocation = CALLM(_future, "getLocation", [GETV(_targetLocation, "id")]);
	private _futureGarrison = CALLM(_futureLocation, "getGarrison", [WEST]);
	["Location is occupied in future", !IS_NULL_OBJECT(_futureGarrison)] call test_Assert;
	// ["Initial state is correct", GETV(_obj, "state") == CMDR_ACTION_STATE_START] call test_Assert;
}] call test_AddTest;

#endif