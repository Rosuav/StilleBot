inherit http_websocket;
constant markdown = #"# Feature management for channel $$channel$$

## Chat commands

Feature | Description | Command details | Status
--------|-------------|-----------------|---------
(loading...) | - | - | -
{: #features}

## Customizable features

Commands, triggers, specials, and other separately-manageable features of the bot can be
quickly and easily enabled here.

Feature | Description | Manager | Status
--------|-------------|---------|-----------
(loading...) | - | - | -
{: #enableables}

$$save_or_login||$$

<style>
:checked + abbr {background-color: #a0f0c0;}
.no-wrap {white-space: nowrap;}
@media (max-width: 750px) {
	label abbr span {display: none;}
}
</style>
";

//TODO: Add shorthands for creating more features:
//- Giveaway triggers?? Maybe?
//- Shoutout command, and link to the main commands page ("others here")
//- Hype train status?

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	//Assume that the list of commands for each feature isn't going to change often.
	//If it does, refresh the page to see the change.
	mapping featurecmds = ([]);
	foreach (G->G->commands; string cmd; command_handler f) {
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

mapping _get_item(string id, int dflt, mapping feat) {
	array FEATUREDESC = function_object(G->G->commands->features)->FEATUREDESC;
	if (!FEATUREDESC[id]) return 0;
	return ([
		"id": id, "desc": FEATUREDESC[id],
		"state": ({"default", "active", "inactive"})[feat[id] || dflt],
	]);
}

bool need_mod(string grp) {return grp == "control";}
mapping get_chan_state(object channel, string grp, string|void id) {
	mapping feat = persist_config->path("channels", channel->name[1..], "features");
	if (id) return _get_item(id, channel->config->allcmds || -1, feat);
	mapping enableables = ([]);
	foreach (G->G->enableable_modules; string name; object mod) {
		foreach (mod->ENABLEABLE_FEATURES; string kwd; mapping info) {
			enableables[kwd] = info | (["module": name, "manageable": mod->can_manage_feature(channel, kwd)]);
		}
	}
	array features = function_object(G->G->commands->features)->FEATURES[1..][*][0]; //List of configurable feature IDs. May need other filtering in the future??
	return (["items": _get_item(features[*], channel->config->allcmds || -1, feat),
		"defaultstate": channel->config->allcmds ? "active": "inactive",
		"enableables": enableables,
	]);
}

@"is_mod": void wscmd_update(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping feat = channel->config->features; if (!feat) feat = channel->config->features = ([]);
	array FEATUREDESC = function_object(G->G->commands->features)->FEATUREDESC;
	if (!FEATUREDESC[msg->id]) return;
	if (msg->id == "allcmds") {
		//The allcmds setting goes into global settings, not features. This is undocumented
		//but still available; for the most part, it's easier to just set features one by one.
		channel->config->allcmds = msg->state == "active";
		persist_config->save();
		send_updates_all(conn->group);
		send_updates_all("view" + channel->name);
	}
	switch (msg->state) {
		case "active": feat[msg->id] = 1; break;
		case "inactive": feat[msg->id] = -1; break;
		case "default": m_delete(feat, msg->id); break; //Undocumented but still available if needed
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
}
