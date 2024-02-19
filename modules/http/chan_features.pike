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

<div id=featureauth></div>

<style>
:checked + abbr {background-color: #a0f0c0;}
.no-wrap {white-space: nowrap;}
@media (max-width: 750px) {
	label abbr span {display: none;}
}
</style>
";

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	if (req->misc->is_mod && !req->misc->session->fake && req->request_type == "POST" && req->variables->export) {
		//Standard rule: Everything in this export comes from channel->config.
		//Anything in persist_status does not belong here; there may eventually be
		//a separate export of that sort of ephemeral data, eg variables.
		//Config attributes deprecated or for my own use only are not included.
		object channel = req->misc->channel;
		mapping cfg = channel->config;
		mapping ret = ([]);
		foreach ("autoban dynamic_rewards giveaway monitors quotes timezone vlcblocks" / " ", string key)
			if (cfg[key] && sizeof(cfg[key])) ret[key] = cfg[key];
		mapping commands = ([]), specials = ([]);
		string chan = channel->name[1..];
		foreach (channel->commands || ([]); string cmd; echoable_message response) {
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
	return render(req, ([
		"vars": (["ws_group": req->misc->is_mod ? "control" : "view"]),
		"chan": req->misc->channel->name[1..] - "!",
	]) | req->misc->chaninfo);
}

mapping _get_item(string id, mapping feat) {return 0;}

bool need_mod(string grp) {return grp == "control";}
__async__ mapping get_state(string group, string|void id) {
	[object channel, string grp] = split_channel(group); if (!channel) return 0;
	if (id) return 0; //Single-item updates are no longer applicable
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
	string timezone = channel->config->timezone;
	if (!timezone || timezone == "") timezone = "UTC";
	mapping chan_prefs = await(G->G->DB->load_config(channel->userid, "userprefs"));
	return (["items": ({ }),
		"timezone": timezone,
		"flags": ([]), //Not currently in use, but maybe worth using in the future. Front end support is still all there.
		"enableables": enableables,
		"chan_notif_perms": chan_prefs->notif_perms || ([]),
	]);
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
		channel->config_save();
	}
	else if (has_value(Calendar.TZnames.zonenames(), msg->timezone))
	{
		channel->config->timezone = msg->timezone;
		channel->config_save();
	}
	send_updates_all(conn->group);
	send_updates_all(channel, "view");
}
