inherit http_websocket;
constant markdown = #"# Feature management for channel $$channel$$

## Customizable features

Commands, triggers, specials, and other separately-manageable features of the bot can be
quickly and easily enabled here.

Feature | Description | Manager | Status
--------|-------------|---------|-----------
(loading...) | - | - | -
{: #enableables}

Additional enableable features may be found on various configuration pages - browse the
sidebar for more cool ideas!

## Channel configuration

Timezone: <input name=timezone size=30> [Set](:#settimezone)

$$save_or_login||$$

<div id=featureauth></div>

<style>
:checked + abbr {background-color: #a0f0c0;}
.no-wrap {white-space: nowrap;}
@media (max-width: 750px) {
	label abbr span {display: none;}
}
</style>
";

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	return render(req, ([
		"vars": (["ws_group": req->misc->is_mod ? "control" : "view"]),
		"chan": req->misc->channel->name[1..] - "!",
	]) | req->misc->chaninfo);
}

mapping _get_item(string id, mapping feat) {return 0;}

bool need_mod(string grp) {return grp == "control";}
__async__ mapping get_chan_state(object channel, string grp, string|void id) {
	if (id) return 0; //Single-item updates are no longer applicable
	mapping enableables = ([]);
	foreach (G->G->enableable_modules; string name; object mod) {
		foreach (mod->ENABLEABLE_FEATURES; string kwd; mapping info) {
			if (info->_hidden) continue;
			enableables[kwd] = info | (["module": name, "manageable": mod->can_manage_feature(channel, kwd)]);
		}
	}
	//Any builtin with suggestions is equally enableable.
	object mod = G->G->enableable_modules->chan_commands; //Note that the command module handles enabling/disabling suggested commands
	foreach (G->G->builtins; string name; object blt)
		foreach (blt->command_suggestions || ([]); string cmd; mapping resp) {
			if (resp->_hidden) continue;
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
		channel->botconfig->timezone = "";
		channel->botconfig_save();
	}
	else if (has_value(Calendar.TZnames.zonenames(), msg->timezone))
	{
		channel->botconfig->timezone = msg->timezone;
		channel->botconfig_save();
	}
	send_updates_all(conn->group);
	send_updates_all(channel, "view");
}
