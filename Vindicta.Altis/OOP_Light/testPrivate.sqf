#include "OOP_Light.h"

CLASS("ClassA", "")

	VARIABLE_ATTR("var", [ATTR_PRIVATE]);

	METHOD(new)
		params [P_THISOBJECT];

		T_SETV("var", 123);
	ENDMETHOD;

	METHOD(delete)

	ENDMETHOD;

ENDCLASS;

CLASS("ClassB", "")

	VARIABLE_ATTR("var", [ATTR_PRIVATE]);

	METHOD(new)
		params [P_THISOBJECT];

		T_SETV("var", 123);
	ENDMETHOD;

	METHOD(delete)

	ENDMETHOD;

	METHOD(illegalAccess)
		params [P_THISOBJECT, "_anotherObject"];

		SETV(_anotherObject, "var", 654);
	ENDMETHOD;

ENDCLASS;

