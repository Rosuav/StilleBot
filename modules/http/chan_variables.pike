inherit http_websocket;

void add_command(mapping info, string cmdname, string desc, int overwrite)
{
	foreach (info->commands || ({ }), mapping c) if (c->name == cmdname) {
		if (overwrite) c->action = desc;
		return;
	}
	info->commands += ({([
		"name": cmdname,
		"action": desc,
	])});
}

void check_for_variables(string cmdname, echoable_message response, mapping variabledata)
{
	if (stringp(response)) {
		foreach (variabledata; string var; mapping info) {
			if (has_value(response, var)) add_command(info, cmdname, "View", 0);
		}
		return;
	}
	if (arrayp(response)) check_for_variables(cmdname, response[*], variabledata);
	if (mappingp(response))
	{
		string d = response->dest || "";
		string var = response->target || "";
		if (sscanf(d, "/set %s", string v) && v && v != "") var = v;
		if (var != "") {
			var = "$" + var + "$";
			if (!variabledata[var])
				variabledata[var] = (["curval": ""]);
			//Normally the /set or /add will have a simple string. If it doesn't,
			//people can go look on the main commands page for the details.
			string delta = stringp(response->message) ? response->message : "something";
			add_command(variabledata[var], cmdname,
				response->action == "add" ? "Add " + delta : "Set to " + delta,
				1);
		}
		check_for_variables(cmdname, response->message, variabledata);
	}
}

string fmt_cmd(mapping cmd) {return sprintf("!%s | %s", cmd->name, cmd->action);}

echoable_message build_View(string var, string msg) {
	return msg;
}

echoable_message build_Increment(string var, string msg) {
	return ([
		"access": "mod", "message": ({
			(["dest": "/set", "target": var, "message": "1", "action": "add"]),
			msg,
		}),
	]);
}

echoable_message build_Reset(string var, string msg) {
	return ([
		"access": "mod", "message": ({
			(["dest": "/set", "target": var, "message": "0"]),
			msg,
		}),
	]);
}

constant newcommands = ({
	({"View",
		"!deaths",
		"Streamer has died $deaths$ times",
		"Public command to view the count w/o changing it",
	}),
	({"Increment",
		"!adddeath",
		"Adding another death - now $deaths$!",
		"Mod-only command to increment the count",
	}),
	({"Reset",
		"!cleardeath",
		"Resetting death counter to zero.",
		"Mod-only command to reset the count to zero.",
	}),
});

constant markdown = sprintf(#"# Variables for $$channel$$

$$messages$$

Name | Value | Usage
-----|-------|------
loading... | - | -
{:#variables}

- | - | Add commands for a counter variable by filling in these details. Anything left blank will be omitted.
------|---|---
Variable name: | <input name=newcounter placeholder=\"deaths\"> | Identifying keyword for this counter%{
%[0]s: | <input name=%[0]scmd placeholder=%[1]q> | <input name=%[0]sresp class=widetext placeholder=%[2]q><br>%[3]s%}
{:#newcounter}

$$save_or_login$$

To customize the commands, [use the gear button on the Commands page](commands).

<style>
table {width: 100%%;}
#newcounter tr td {width: max-content;}
#newcounter tr td:nth-of-type(3) {width: 100%%;}
</style>
", newcommands);

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	if (!req->misc->is_mod) return redirect("commands");
	string c = req->misc->channel->name;
	array messages = ({ });
	mapping rawdata = persist_status->path("variables", c);
	//Prune any bad entries. Shouldn't be needed. Good guard against bugs in other places though (goalbars, I'm looking at you)
	foreach (indices(rawdata), string var) if (sizeof(var) < 3 || var[0] != '$' || var[-1] != '$') {
		m_delete(rawdata, var);
		persist_status->save();
	}
	if (req->misc->is_mod && sscanf(req->variables->newcounter || "", "%[a-zA-Z]", string counter) && counter != "")
	{
		//Create some simple commands. This isn't designed for editing, although
		//it will overwrite if given a duplicate name.
		foreach (newcommands, array info)
		{
			string kw = info[0]; mapping attr = info[1]; //Ignore the spare elements in info
			string cmd = req->variables[kw + "cmd"] || "";
			string resp = req->variables[kw + "resp"] || "";
			write("%s: %O %O\n", kw, cmd, resp);
			if (cmd == "" || resp == "") continue;
			sscanf(cmd, "%*[!]%[A-Za-z]", cmd);
			messages += ({sprintf("* Creating %s command !%s", kw, cmd)});
			make_echocommand(cmd + c, this["build_" + kw](counter, resp));
		}
		if (!rawdata["$" + counter + "$"]) {rawdata["$" + counter + "$"] = "0"; persist_status->save();}
	}
	//Convert (["x": "1"]) into (["x": (["curval": "1"])]) to allow us to add metadata
	mapping variabledata = mkmapping(indices(rawdata), (["curval": values(rawdata)[*]]));
	foreach (G->G->echocommands; string cmd; echoable_message response) if (!has_prefix(cmd, "!") && has_suffix(cmd, c))
	{
		//NOTE: This makes a number of assumptions about the response. Commands that
		//don't fit those assumptions won't be displayed here. In general, complicated
		//stuff needs to be seen in the commands list, not here.
		check_for_variables(cmd - c, response, variabledata);
	}
	foreach (sort(indices(variabledata)), string name)
	{
		mapping v = variabledata[name];
		string val = v->curval; //Note that rawdata[name] might be UNDEFINED
		//This method of changing a variable is highly obscure. There's currently no button,
		//so it can only be done by hitting Enter in one of the form fields, which give no
		//indication that such can be done. Will need a proper socket-triggered edit.
		if (string newval = req->request_type == "POST" && req->variables["set_" + name])
		{
			if (newval != v->curval)
			{
				messages += ({sprintf("* Updated %s from %s to %s", name, val, newval)});
				rawdata[name] = val = newval;
				persist_status->save();
			}
			//TODO: Have a way to delete a variable. Give warnings if
			//it has any commands recorded (see check_for_variables).
		}
	}
	return render(req, ([
		"vars": (["ws_group": ""]),
		"messages": messages * "\n",
		"save_or_login": "<input type=submit value=\"Add counter commands\">",
	]) | req->misc->chaninfo);
}

mapping _get_variable(mapping vars, string varname) {
	if (undefinedp(vars[varname])) return 0;
	mapping ret = (["id": varname, "curval": vars[varname]]);
	//TODO: Add usage
	return ret;
}
bool need_mod(string grp) {return 1;}
mapping get_chan_state(object channel, string grp, string|void id) {
	mapping vars = persist_status->path("variables", channel->name);
	if (id) return _get_variable(vars, id);
	array variabledata = _get_variable(vars, sort(indices(vars))[*]);
	return (["items": variabledata]);
}

void websocket_cmd_delete(mapping(string:mixed) conn, mapping(string:mixed) msg) { } //Gonna need this
