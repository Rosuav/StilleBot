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
constant builtin_param = ({"Variable name", "/Action/get/set/add/spend/clear/leaders", "New value"});
//Experimenting with a branching parameter set
constant MOCKUP_builtin_param = ({
	"Variable name",
	"/Action", //Having an enum with no options triggers this behaviour
	([ //The next array entry will have the options, mapped to their additional args.
		"get": ({ }), //This one needs no more args
		({"set", "add", "spend"}): ({"New value"}), //One more arg for any of these values
		"clear": ({ }), //Can have this separately, or combine it with get, whichever makes more sense logically
		"leaders": ({"Top N"}), //This one gets a different arg, which would display a different label in the front end
	]),
	//If any more args were listed here, they would happen after the additionals given above.
});
constant vars_provided = ([
	"{value}": "Value of that variable (after any change)",
]);

__async__ mapping message_params(object channel, mapping person, array param, mapping cfg) {
	if (sizeof(param) < 2 || sizeof(param) > 3) error("Invalid usage, check docs\n"); //meh
	if (sizeof(param) == 2) param += ({""}); //Normally 2 for get/delete, 3 for set
	[string varname, string action, string value] = param;
	varname -= "$";
	switch (action) {
		case "get": return ([
			"{value}": channel->expand_variables("$" + varname + "$", ([]), person, cfg->users),
		]);
		case "set": case "spend": return ([
			"{value}": channel->set_variable(varname, value, action, cfg->users) || "", //spend will return null if the spend fails
		]);
		case "clear": {
			mapping vars = G->G->DB->load_cached_config(channel->userid, "variables");
			if (has_value(varname, '*')) {
				//Clear this var from all users
				mapping uservars = vars["*"] || ([]);
				varname = "$" + (varname - "*") + "$"; //In the mapping, the varname doesn't have its adornment.
				foreach (indices(uservars), string uid) { //Iterate over a copy so we can remove an entire uservar block if needed
					mapping v = uservars[uid];
					m_delete(v, varname);
					if (!sizeof(v)) m_delete(uservars, uid);
				}
				if (!sizeof(uservars)) m_delete(vars, "*");
			} else if (varname[-1] == ':') {
				//Clear an entire group of vars
				varname = "$" + varname;
				foreach (indices(vars), string v)
					if (has_prefix(v, varname)) m_delete(vars, v);
			} else {
				//Remove a variable. Normally equivalent to setting it to "", but will remove it from /c/variables
				m_delete(vars, "$" + varname + "$");
			}
			G->G->DB->save_config(channel->userid, "variables", vars);
			//NOTE: Like truncating an SQL table, clearing a variable does not push out notifications.
			//This should not be used when the variable in question is part of a monitor or dynamic
			//points reward etc. The only notification we send is to /c/variables itself.
			G->G->websocket_types->chan_variables->send_updates_all("#" + channel->userid);
			return (["{value}": ""]); //Nothing useful to report.
		}
		case "leaders": {
			//Hack: The provided value is the number of top people to return
			mapping vars = G->G->DB->load_cached_config(channel->userid, "variables")["*"] || ([]);
			array values = ({ }), users = ({ });
			varname = "$" + replace(varname, "$", "") + "$";
			foreach (vars; string uid; mapping v) if (v[varname]) {
				users += ({uid});
				values += ({-(int)v[varname]}); //Descending sort
			}
			sort(values, users);
			mapping ret = (["{value}": (string)sizeof(users)]); //The base return value won't have anything much, just the (total) count of users
			int limit = (int)value;
			if (limit) users = users[..limit-1];
			foreach (users; int i; string uid) {
				ret["{value" + (i+1) + "}"] = vars[uid][varname];
				ret["{uid" + (i+1) + "}"] = uid;
				ret["{username" + (i+1) + "}"] = await(get_user_info(uid))->?display_name || uid;
			}
			return ret;
		}
		default: error("Invalid action %O, check docs\n", action);
	}
}
