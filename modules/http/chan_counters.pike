inherit http_endpoint;

void verify_response(string cmdname, echoable_message response, mapping counterdata, int modonly)
{
	if (stringp(response)) return; //Nothing more to do
	if (arrayp(response)) verify_response(cmdname, response[*], counterdata, modonly);
	if (mappingp(response))
	{
		//NOTE: We probably could check the require_moderator flag here, but it
		//would have the potential to be inaccurate. Setting that on a subcommand
		//has no effect (see connection.pike:handle_command and globals.pike:find_command).
		if (response->counter)
		{
			if (!counterdata[response->counter])
				counterdata[response->counter] = (["count": 0]);
			counterdata[response->counter]->commands += ({([
				"name": cmdname,
				"modonly": modonly,
				"action": response->action || "",
			])});
		}
		verify_response(cmdname, response->message, counterdata, modonly);
	}
}

string fmt_cmd(mapping cmd)
{
	return sprintf("!%s | %s | %s",
		cmd->name,
		([
			0: "View", "": "View",
			"+1": "Increment",
			"=0": "Reset to zero",
			"=%s": "Set to specified value",
		])[cmd->action] || cmd->action,
		cmd->modonly ? "Mods" : "Anyone",
	);
}

constant newcommands = ({
	({"View", ([]),
		"!deaths",
		"Streamer has died %d times",
		"Public command to view the count w/o changing it",
	}),
	({"Increment", (["access": "mod", "action": "+1"]),
		"!adddeath",
		"Adding another death - now %d!",
		"Mod-only command to increment the count",
	}),
	({"Reset", (["access": "mod", "action": "=0"]),
		"!cleardeath",
		"Resetting death counter to zero.",
		"Mod-only command to reset the count to zero.",
	}),
});

constant newcounterform = sprintf(#"- | - | Add a new counter by filling in these details. Anything left blank will be omitted.
------|---|---
Keyword: | <input name=newcounter placeholder=\"deaths\"> | Identifying keyword for this counter%{
%[0]s: | <input name=%[0]scmd placeholder=%[2]q> | <input name=%[0]sresp class=widetext placeholder=%[3]q><br>%[4]s%}
{:#newcounter}
", newcommands);

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	string c = req->misc->channel->name;
	array counters = ({ }), order = ({ }), messages = ({ });
	mapping rawdata = persist_status->path("counters", c);
	//Convert (["x": 1]) into (["x": (["count": 1])]) to allow us to add metadata
	mapping counterdata = mkmapping(indices(rawdata), (["count": values(rawdata)[*]]));
	if (req->misc->is_mod && sscanf(req->variables->newcounter || "", "%[a-zA-Z]", string counter) && counter != "")
	{
		foreach (newcommands, array info)
		{
			string kw = info[0]; mapping attr = info[1]; //Ignore the spare elements in info
			string cmd = req->variables[kw + "cmd"] || "";
			string resp = req->variables[kw + "resp"] || "";
			write("%s: %O %O\n", kw, cmd, resp);
			if (cmd == "" || resp == "") continue;
			sscanf(cmd, "%*[!]%[A-Za-z]", cmd);
			messages += ({sprintf("* Creating %s command !%s", kw, cmd)});
			make_echocommand(cmd + req->misc->channel->name,
				attr | (["message": resp, "counter": counter]),
			);
		}
	}
	foreach (G->G->echocommands; string cmd; echoable_message response) if (!has_prefix(cmd, "!") && has_suffix(cmd, c))
	{
		//NOTE: This makes a number of assumptions about the response, including that it
		//won't try to do multiple actions that all affect counters. If you violate those
		//assumptions, the display will look ugly, and editing mightn't work properly.
		verify_response(cmd - c, response, counterdata,
			mappingp(response) && ((int)response->require_moderator || response->access == "mod")
		);
	}
	foreach (sort(indices(counterdata)), string name)
	{
		mapping c = counterdata[name];
		string count = (string)c->count;
		if (req->misc->is_mod)
		{
			if (string newval = req->request_type == "POST" && req->variables["set_" + name])
			{
				int val = (int)newval;
				if ((string)val != String.trim(newval))
				{
					//Prevent non-integers or other formats or anything
					messages += ({sprintf("* Invalid number format %s for %s", newval, name)});
				}
				else if (val == c->count) ; //No change, be silent
				else if (val)
				{
					messages += ({sprintf("* Updated %s from %d to %d (%+d)", name, c->count, val, val-c->count)});
					rawdata[name] = val; count = (string)val;
					persist_status->save();
				}
				else
				{
					messages += ({sprintf("* Wiped %s (was %d)", name, c->count)});
					m_delete(rawdata, name); count = "0";
					persist_status->save();
				}
			}
			count = sprintf("<input type=number name=set_%s value=%s>", name, count);
		}
		if (c->commands && sizeof(c->commands) == 1) //Special-case the common case of exactly one handler
		{
			counters += ({sprintf("%s | %s | %s", name, count, fmt_cmd(c->commands[0]))});
			continue;
		}
		counters += ({sprintf("%s | %s | - | - | -", name, count)});
		if (c->commands) counters += sort(sprintf("&nbsp; | &nbsp; | %s", fmt_cmd(c->commands[*])[*]));
	}
	if (!sizeof(counters)) counters = ({"(none) |"});
	return render_template("chan_counters.md", ([
		"counters": counters * "\n",
		"messages": messages * "\n",
		"newcounter": req->misc->is_mod ? newcounterform : "",
		"save_or_login": "<input type=submit value=\"Add/update counter(s)\">",
	]) | req->misc->chaninfo);
}
