inherit http_websocket;
constant markdown = #"# Feature management for channel $$channel$$

Feature | Controls | Affected commands | Active?
--------|----------|-------------------|---------
(loading...) | - | - | -
{: #features}

$$save_or_login||$$
";

//TODO: Also have some shorthands for creating other features:
//- Autoban buy-follows
//- Giveaway triggers?? Maybe?
//- Transcoding on stream start
//- VLC track reporting
//- VLC !song command (and link to the VLC page, of course)
//- Shoutout command, and link to the main commands page ("others here")
//- Hype train status?
//Note that these will not necessarily report whether they're active; they'll just have a "Create" button.
//Maybe also a "Delete" button for some, where plausible.

//In the web interface, it may be useful to list all commands under each feature.
//If, and only if, you're logged in as the bot, also list everything in allcmds, and
//everything with no featurename but which is a function.

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
	]) | req->misc->chaninfo);
}

mapping _get_item(string id, int allcmds, mapping feat) {
	array FEATUREDESC = function_object(G->G->commands->features)->FEATUREDESC;
	if (!FEATUREDESC[id]) return 0;
	int f = feat[id];
	if (id == "allcmds") f = allcmds || -1; //The allcmds setting comes from global settings, not from features
	return ([
		"id": id, "desc": FEATUREDESC[id],
		"state": ({"default", "active", "inactive"})[f],
	]);
}

bool need_mod(string grp) {return grp == "control";}
mapping get_chan_state(object channel, string grp, string|void id) {
	mapping feat = persist_config->path("channels", channel->name[1..], "features");
	if (id) return _get_item(id, channel->config->allcmds, feat);
	return (["items": _get_item(function_object(G->G->commands->features)->FEATURES[*][0][*], channel->config->allcmds, feat),
		"defaultstate": channel->config->allcmds ? "active": "inactive"]);
}

void websocket_cmd_update(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	sscanf(conn->group, "%s#%s", string grp, string chan);
	if (grp != "control" || !G->G->irc->channels["#" + chan]) return;
	mapping feat = persist_config->path("channels", chan, "features");
	array FEATUREDESC = function_object(G->G->commands->features)->FEATUREDESC;
	if (!FEATUREDESC[msg->id]) return;
	if (msg->id == "allcmds") {
		//The allcmds setting goes into global settings, not features
		persist_config->path("channels", chan)->allcmds = msg->state == "active";
	}
	else switch (msg->state) {
		case "active": feat[msg->id] = 1; break;
		case "inactive": feat[msg->id] = -1; break;
		case "default": m_delete(feat, msg->id); break;
		default: return;
	}
	persist_config->save();
	update_one(conn->group, msg->id);
	update_one("view#" + chan, msg->id);
}
