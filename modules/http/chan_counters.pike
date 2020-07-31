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

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	string c = req->misc->channel->name;
	array counters = ({ }), order = ({ }), messages = ({ });
	mapping counterdata = persist_status->path("counters", c);
	//Convert (["x": 1]) into (["x": (["count": 1])]) to allow us to add metadata
	counterdata = mkmapping(indices(counterdata), (["count": values(counterdata)[*]]));
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
					messages += ({sprintf("Invalid number format %s for %s", newval, name)});
				}
				else if (val != c->count)
				{
					messages += ({sprintf("Updated %s from %d to %d (%+d)", name, c->count, val, val-c->count)});
					persist_status->path("counters", req->misc->channel->name)[name] = val;
					count = (string)val;
					persist_status->save();
				}
				//Else if it's the same, say nothing.
			}
			count = sprintf("<input type=number name=set_%s value=%s>", name, count);
		}
		if (sizeof(c->commands) == 1) //Special-case the common case of exactly one handler
		{
			mapping cmd = c->commands[0];
			counters += ({sprintf("%s | %s | %s", name, count, fmt_cmd(c))});
			continue;
		}
		counters += ({sprintf("%s | %s | - | - | -", name, count)});
		foreach (c->commands || ({ }), mapping cmd)
		{
			counters += ({sprintf("&nbsp; | &nbsp; | %s", fmt_cmd(cmd))});
		}
	}
	if (!sizeof(counters)) counters = ({"(none) |"});
	//if (changes_made) make_echocommand(0, 0); //Trigger a save
	return render_template("chan_counters.md", ([
		//"user text": user,
		"channel": req->misc->channel_name, "counters": counters * "\n",
		"messages": messages * "\n",
		"save_or_login": req->misc->login_link || "<input type=submit value=\"Update counter(s)\">",
	]));
}
