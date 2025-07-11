#charset utf-8
inherit http_websocket;

void add_command(mapping info, string type, string name, string desc, int overwrite)
{
	foreach (info->usage || ({ }), mapping c) if (c->name == name) {
		if (overwrite) c->action = desc;
		return;
	}
	info->usage += ({([
		"type": type,
		"name": name,
		"action": desc,
	])});
}

//NOTE: This makes a number of assumptions about the response. Commands that
//don't fit those assumptions won't be displayed here. In general, complicated
//stuff needs to be seen in the commands list, not here.
//TODO: Also notice per-user variables with specific user lookups eg "$target*varname$"
void check_for_variables(string type, string name, echoable_message response, string varname, mapping info)
{
	if (stringp(response)) {
		if (has_value(response, varname)) add_command(info, type, name, "View", 0);
		return;
	}
	if (arrayp(response)) check_for_variables(type, name, response[*], varname, info);
	if (mappingp(response))
	{
		string d = response->dest || "";
		string var = response->target || "";
		if (sscanf(d, "/set %s", string v) && v && v != "") var = v; //Compat with old way of combining dest and target
		if (var == varname - "$") {
			//Normally the /set or /add will have a simple string. If it doesn't,
			//people can go look on the main commands page for the details.
			string delta = stringp(response->message) ? response->message : "something";
			add_command(info, type, name,
				(response->action || response->destcfg) == "add" ? "Add " + delta : "Set to " + delta,
				1);
		}
		check_for_variables(type, name, response->message, varname, info);
	}
}

echoable_message build_View(string var, string msg) {
	return msg;
}

echoable_message build_Increment(string var, string msg) {
	return ([
		"access": "mod", "message": ({
			(["dest": "/set", "target": var, "message": "1", "destcfg": "add"]),
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

Name | Value | Actions | Usage
-----|-------|---------|-------
loading... | - | - | -
{:#variables}

&nbsp; <!-- bit of a gap here, semantically as well as visually -->

> - | - | Add commands for a counter variable by filling in these details. Anything left blank will be omitted.
> ------|---|---
> Variable name: | <input name=newcounter placeholder=\"deaths\"> | Identifying keyword for this counter%{
> %[0]s: | <input name=%[0]scmd placeholder=%[1]q> | <input name=%[0]sresp class=widetext placeholder=%[2]q><br>%[3]s%}
> {:#newcounter}
>
> <input type=submit value=\"Add counter commands\">
{:tag=form method=post}

To customize the commands, [use the gear button on the Commands page](commands).

<style>
table {width: 100%%;}
#newcounter tr td {width: max-content;}
#newcounter tr td:nth-of-type(3) {width: 100%%;}
ul {margin: 0;}
td {vertical-align: top;}
#uservars.clean button[type=submit] {display: none;}
#uservars th {cursor: pointer;}
#uservars th.sortasc::after {content: \" ▲\";}
#uservars th.sortdesc::after {content: \" ▼\";}
</style>

> ### Grouped variables
>
> The variable <code id=basevarname></code> contains the following:
>
> ID | Name | Value
> ---|------|----------
> loading... |
>
> [Save](:type=submit) [Cancel](:#close_or_cancel .dialog_close)
{: tag=formdialog #groupedvars}

", newcommands);

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	if (!req->misc->is_mod) return redirect("commands");
	string c = req->misc->channel->name;
	array messages = ({ });
	mapping rawdata = G->G->DB->load_cached_config(req->misc->channel->userid, "variables");
	int changed = 0;
	//Prune any bad entries. Shouldn't be needed. Good guard against bugs in other places though (goalbars, I'm looking at you)
	foreach (indices(rawdata), string var) if (sizeof(var) < 3 || var[0] != '$' || var[-1] != '$') {
		if (var == "*" && mappingp(rawdata[var])) continue; //But per-user variables are fine (and currently unvalidated).
		m_delete(rawdata, var);
		changed = 1;
	}
	if (req->misc->is_mod && !req->misc->session->fake && sscanf(req->variables->newcounter || "!", "%[a-zA-Z]", string counter) && counter != "")
	{
		//Create some simple commands. This isn't designed for editing, although
		//it will overwrite if given a duplicate name. TODO: Replace the CGI form
		//here with something done in JS on the front end. Stick it in a dialog,
		//too - the inputs don't need to be hanging around all the time.
		foreach (newcommands, array info)
		{
			string kw = info[0]; mapping attr = info[1]; //Ignore the spare elements in info
			string cmd = req->variables[kw + "cmd"] || "";
			string resp = req->variables[kw + "resp"] || "";
			write("%s: %O %O\n", kw, cmd, resp);
			if (cmd == "" || resp == "") continue;
			sscanf(cmd, "%*[!]%[A-Za-z]", cmd);
			messages += ({sprintf("* Creating %s command !%s", kw, cmd)});
			G->G->cmdmgr->update_command(req->misc->channel, "", cmd, this["build_" + kw](counter, resp));
		}
		if (!rawdata["$" + counter + "$"]) {rawdata["$" + counter + "$"] = "0"; changed = 1;}
	}
	if (changed) G->G->DB->save_config(req->misc->channel->userid, "variables", rawdata);
	//Convert (["x": "1"]) into (["x": (["curval": "1"])]) to allow us to add metadata
	mapping variabledata = mkmapping(indices(rawdata), (["curval": values(rawdata)[*]]));
	return render(req, ([
		"vars": (["ws_group": ""]),
		"messages": messages * "\n",
	]) | req->misc->chaninfo);
}

mapping _get_variable(mapping vars, object channel, string varname, int|void per_user) {
	int(1bit) is_group = has_suffix(varname, ":*");
	if (!per_user && !is_group && undefinedp(vars[varname])) return 0; //Note that per-user variables will never be push-deleted
	string c = channel->name;
	if (per_user) varname = "$*" + varname[1..];
	mapping ret = (["id": varname - "$", "curval": vars[varname], "usage": ({ }), "per_user": per_user]);
	if (is_group) return ret | (["is_group": 1]);
	foreach (channel->commands; string cmd; echoable_message response)
		if (!mappingp(response) || !response->alias_of)
			check_for_variables(cmd == "!trigger" ? "trigger" : cmd[0] == '!' ? "special" : "command",
				"!" + cmd, response, varname, ret);
	foreach (G->G->DB->load_cached_config(channel->userid, "monitors"); string nonce; mapping info)
		check_for_variables(info->type == "goalbar" ? "goalbar" : "monitor", nonce, info->text, varname, ret);
	return ret;
}
bool need_mod(string grp) {return 1;}
mapping get_chan_state(object channel, string grp, string|void id) {
	mapping vars = G->G->DB->load_cached_config(channel->userid, "variables");
	if (id) return _get_variable(vars, channel, "$" + id + "$");
	//Collect all variable names, collapsing "base:suffix" var names to just "base:*"
	multiset(string) varnames = (<>);
	foreach (vars; string name;) {
		if (name == "*") continue; //Ignore the collection of user vars
		if (sscanf(name, "%s:%*s", string base)) varnames[base + ":*"] = 1;
		else varnames[name] = 1;
	}
	array variabledata = _get_variable(vars, channel, sort(indices(varnames))[*]);
	if (mapping uservars = vars["*"]) {
		//Note: This is potentially slow. Would it be worth caching somewhere? Most likely,
		//per-user variables will all have broadly the same shape.
		multiset all_per_user = (<>);
		foreach (uservars; string uid; mapping v) all_per_user |= (multiset)indices(v);
		//Okay. Now we know what all possible variable names are, let's get some info.
		foreach (all_per_user; string varname;)
			variabledata += ({_get_variable(vars, channel, varname, 1)});
	}
	return (["items": variabledata]);
}

mapping|zero websocket_cmd_delete(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (conn->session->fake) return (["cmd": "demo"]);
	[object channel, string grp] = split_channel(conn->group);
	mapping vars = G->G->DB->load_cached_config(channel->userid, "variables");
	if (m_delete(vars, "$" + msg->id + "$")) update_one(conn->group, msg->id);
}

mapping|zero websocket_cmd_update(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (conn->session->fake) return (["cmd": "demo"]);
	[object channel, string grp] = split_channel(conn->group);
	mapping vars = G->G->DB->load_cached_config(channel->userid, "variables");
	if (mappingp(msg->per_user)) {
		string var = "*" + replace(msg->id, "*|${}" / 1, "");
		//TODO: Filter to existing variables according to the all_per_user set
		//Currently just filters by validity.
		foreach (msg->per_user; string uid; string value)
			channel->set_variable(var, value, "set", (["": uid]));
		return 0;
	}
	if (mappingp(msg->group)) {
		string pfx = replace(msg->id, "*|$:{}" / 1, "") + ":";
		foreach (msg->group; string suffix; string value) {
			string var = pfx + replace(suffix, "*|$:{}" / 1, "");
			if (!undefinedp(vars["$" + var + "$"])) channel->set_variable(var, value, "set");
		}
		return 0;
	}
	if (undefinedp(vars["$" + msg->id + "$"])) return 0; //Only update existing vars this way.
	channel->set_variable(msg->id, msg->value || "", "set");
}

@"demo_ok": __async__ void wscmd_getgroupvars(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping vars = G->G->DB->load_cached_config(channel->userid, "variables");
	string pfx = "$" + (msg->id - "*" - ":") + ":";
	//Scan for every variable that starts with this prefix. They're all independent,
	//but for the front end display, they are collapsed together.
	array ret = ({ });
	foreach (sort(indices(vars)), string name) if (has_prefix(name, pfx)) ret += ({([
		"suffix": name - pfx - "$",
		"value": vars[name],
	])});
	conn->sock->send_text(Standards.JSON.encode((["cmd": "groupvars", "prefix": pfx - "$", "vars": ret]), 4));
}

__async__ void wscmd_getuservars(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping vars = G->G->DB->load_cached_config(channel->userid, "variables")["*"];
	if (!mappingp(vars)) return;
	string var = "$" + (msg->id - "*") + "$";
	//Scan this for every user that has this variable
	mapping uservars = ([]);
	foreach (vars; string uid; mapping v) if (v[var]) uservars[uid] = v[var];
	//Note that it would be kinda nice to show display names here, but that
	//would potentially incur a Twitch API call for every user, which could
	//get rather costly. So we just show the most recently sighted login.
	//The array of names may contain duplicates, but the most recent will be
	//the last, so mkmapping will happily override the earlier ones.
	array names = await(G->G->DB->query_ro("select * from stillebot.user_login_sightings where twitchid = any(:ids) order by twitchid, sighted",
		(["ids": indices(uservars)])));
	mapping uid_to_name = mkmapping(names->twitchid, names->login);
	array ret = ({ });
	foreach (uservars; string uid; string value) ret += ({([
		"uid": uid,
		"username": uid_to_name[(int)uid] || sprintf("(user %d)", (int)uid),
		"value": value,
	])});
	if (sizeof(ret)) sort(ret->username, ret);
	conn->sock->send_text(Standards.JSON.encode((["cmd": "uservars", "varname": var, "users": ret]), 4));
}
