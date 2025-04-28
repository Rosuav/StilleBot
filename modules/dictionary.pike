/* Temporary hack: A dedicated builtin for managing dictionary variables

(Yes, I know that that means it'll be permanent.)

Eventually the goal is to have this functionality more directly available, but for now,
you can manipulate dictionary variables with this.

CAUTION: This module is provisional and its API may change without guarantee of
backward compatibility. Eventually it may simply be removed in favour of core support.
*/
inherit builtin_command;
constant builtin_name = "Dictionary";
constant builtin_description = "Manipulate dict variables";
constant builtin_param = ({"Variable", "/Action/get/set/delete", "Key", "New value"});
constant vars_provided = ([
	"{prevvalue}": "Previous value at that key (same as current value for action Get)",
]);

__async__ mapping message_params(object channel, mapping person, array param) {
	if (sizeof(param) < 3 || sizeof(param) > 4) error("Invalid usage, check docs\n"); //meh
	if (sizeof(param) == 3) param += ({""}); //Normally 3 for get/delete, 4 for set
	[string varname, string action, string key, string value] = param;
	varname = "$" + (varname - "$") + "$";
	//Note that there are (currently) no per-user or ephemeral dictionary variables.
	mapping basevars = G->G->DB->load_cached_config(channel->userid, "variables");
	mapping var = basevars[varname];
	if (!mappingp(var)) basevars[varname] = var = ([]);
	string prevvalue = var[key];
	switch (action) {
		case "get": break;
		case "set": var[key] = value; break;
		case "delete": m_delete(var, key); break;
	}
	G->G->DB->save_config(channel->userid, "variables", basevars);
	G->G->websocket_types->chan_variables->update_one(channel->name, varname);
	//Not currently pushing out variable_changed notifications - see connection.pike set_variable
	return ([
		"{prevvalue}": prevvalue,
	]);
}
