inherit http_websocket;
constant markdown = #"# Feature management for channel $$channel$$

## Customizable features

Commands, triggers, specials, and other separately-manageable features of the bot can be
quickly and easily enabled here.

Feature | Description | Manager | Status
--------|-------------|---------|-----------
(loading...) | - | - | -
{: #enableables}

## Channel configuration

Timezone: <input name=timezone size=30> [Set](:#settimezone)

$$save_or_login||> [Export/back up all configuration](:type=submit name=export)
{:tag=form method=post}$$

<style>
:checked + abbr {background-color: #a0f0c0;}
.no-wrap {white-space: nowrap;}
@media (max-width: 750px) {
	label abbr span {display: none;}
}
</style>
";

constant FEATUREDESC = ([]);

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	if (req->misc->is_mod && !req->misc->session->fake && req->request_type == "POST" && req->variables->export) {
		//Standard rule: Everything in this export comes from persist_config and the commands list.
		//(Which ultimately may end up being merged anyway.)
		//Anything in persist_status does not belong here; there may eventually be
		//a separate export of that sort of ephemeral data, eg variables.
		//Config attributes deprecated or for my own use only are not included.
		object channel = req->misc->channel;
		mapping cfg = channel->config;
		mapping ret = ([]);
		foreach ("autoban autocommands dynamic_rewards giveaway monitors quotes timezone vlcblocks" / " ", string key)
			if (cfg[key] && sizeof(cfg[key])) ret[key] = cfg[key];
		mapping commands = ([]), specials = ([]);
		string chan = channel->name[1..];
		foreach (channel->config->commands || ([]); string cmd; echoable_message response) {
			if (mappingp(response) && response->alias_of) continue;
			if (has_prefix(cmd, "!")) specials[cmd] = response;
			else commands[cmd] = response;
		}
		ret->commands = commands;
		if (array t = m_delete(specials, "!trigger"))
			if (arrayp(t)) ret->triggers = t;
		ret->specials = specials;
		mapping resp = jsonify(ret, 5);
		string fn = "stillebot-" + channel->name[1..] + ".json";
		resp->extra_heads = (["Content-disposition": sprintf("attachment; filename=%q", fn)]);
		return resp;
	}
	//Assume that the list of commands for each feature isn't going to change often.
	//If it does, refresh the page to see the change.
	mapping featurecmds = ([]);
	foreach (G->G->commands; string cmd; mixed f) {
		if (has_value(cmd, '#')) continue; //Ignore channel-specific commands
		object|mapping flags = functionp(f) ? function_object(f) : mappingp(f) ? f : ([]);
		if (flags->aliases && has_value(flags->aliases, cmd)) continue; //It's an alias, not the primary
		if (flags->hidden_command) continue;
		featurecmds[flags->featurename || "ungoverned"] += ({cmd});
	}
	return render(req, ([
		"vars": (["ws_group": req->misc->is_mod ? "control" : "view", "featurecmds": featurecmds]),
		"chan": req->misc->channel->name[1..] - "!",
	]) | req->misc->chaninfo);
}

mapping _get_item(string id, mapping feat) {
	if (!FEATUREDESC[id]) return 0;
	return ([
		"id": id, "desc": FEATUREDESC[id],
		"state": feat[id] ? "active" : "inactive",
	]);
}

bool need_mod(string grp) {return grp == "control";}
mapping get_chan_state(object channel, string grp, string|void id) {
	mapping feat = channel->path("features");
	if (id) return _get_item(id, feat);
	mapping enableables = ([]);
	foreach (G->G->enableable_modules; string name; object mod) {
		foreach (mod->ENABLEABLE_FEATURES; string kwd; mapping info) {
			enableables[kwd] = info | (["module": name, "manageable": mod->can_manage_feature(channel, kwd)]);
		}
	}
	//Any builtin with suggestions is equally enableable.
	object mod = G->G->enableable_modules->chan_commands; //Note that the command module handles enabling/disabling suggested commands
	foreach (G->G->builtins; string name; object blt)
		foreach (blt->command_suggestions || ([]); string cmd; mapping resp) {
			enableables[cmd] = ([
				"module": "chan_commands", "fragment": "#" + (cmd - "!") + "/",
				"manageable": mod->can_manage_feature(channel, cmd),
				"description": resp->_description,
			]);
		}
	array features = sort(indices(FEATUREDESC));
	string timezone = channel->config->timezone;
	if (!timezone || timezone == "") timezone = "UTC";
	return (["items": _get_item(features[*], feat),
		"timezone": timezone,
		"flags": ([]), //Not currently in use, but maybe worth using in the future. Front end support is still all there.
		"enableables": enableables,
	]);
}

@"is_mod": void wscmd_update(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping feat = channel->config->features; if (!feat) feat = channel->config->features = ([]);
	if (!FEATUREDESC[msg->id]) return;
	switch (msg->state) {
		case "active": feat[msg->id] = 1; break;
		case "inactive": m_delete(feat, msg->id); break;
		default: return;
	}
	persist_config->save();
	update_one(conn->group, msg->id);
	update_one("view" + channel->name, msg->id);
}

@"is_mod": void wscmd_enable(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	//In theory we could maintain an id to module mapping, but not worth the hassle.
	foreach (G->G->enableable_modules; string name; object mod) {
		if (mapping info = mod->ENABLEABLE_FEATURES[msg->id]) {
			mod->enable_feature(channel, msg->id, !!msg->state);
			send_updates_all(conn->group); //Can't be bothered doing proper partial updates of a subinfo block
			return;
		}
	}
	//If it wasn't found, it's probably a command suggestion.
	G->G->enableable_modules->chan_commands->enable_feature(channel, msg->id, !!msg->state);
	send_updates_all(conn->group);
}

@"is_mod": void wscmd_settimezone(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (msg->timezone == "" || msg->timezone == "UTC") {
		channel->config->timezone = "";
		persist_config->save();
	}
	else if (has_value(Calendar.TZnames.zonenames(), msg->timezone))
	{
		channel->config->timezone = msg->timezone;
		persist_config->save();
	}
	send_updates_all(conn->group);
	send_updates_all("view" + channel->name);
}
