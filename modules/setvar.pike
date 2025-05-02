/* Dynamically manipulate variables, allowing for substitution in the name

CAUTION: This can result in nonsensical names, or names that are hard to manipulate.
It is recommended that dynamic variables be grouped eg "foo:{thing}" to keep the
display in /c/variables tidy.

NOTE: When this is used, static lookups of the same name within that command tree
are not affected, and will thus return the previous value of the variable. For
example, setvar("foo", "set", "bar") will return {value} == "bar", but using $foo$
in the same subtree will reveal what $foo$ would have been if not for the setvar.
*/
inherit builtin_command;
constant builtin_name = "Variables";
constant builtin_description = "Manipulate variables with dynamic names";
constant builtin_param = ({"Variable name", "/Action/get/set/add/spend", "New value"});
constant vars_provided = ([
	"{value}": "Value of that variable (after any change)",
]);

__async__ mapping message_params(object channel, mapping person, array param, mapping cfg) {
	if (sizeof(param) < 2 || sizeof(param) > 3) error("Invalid usage, check docs\n"); //meh
	if (sizeof(param) == 2) param += ({""}); //Normally 2 for get/delete, 3 for set
	[string varname, string action, string value] = param;
	varname -= "$";
	if (action == "get") return ([
		"{value}": channel->expand_variables("$" + varname + "$", ([]), person, cfg->users),
	]);
	return ([
		"{value}": channel->set_variable(varname, value, action, cfg->users) || "", //spend will return null if the spend fails
	]);
}
