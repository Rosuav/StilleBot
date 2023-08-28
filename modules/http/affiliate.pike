//Path to Affiliate - or - Streamers Working Through the Tutorial
inherit http_endpoint;
constant markdown = #"# Path to Affiliate streamers

[Share these streamers with your friends!](affiliate?guide=$$guide$$)

## Active streamers

* loading...
{:#streamers .tiles}

## Successful Alumni

* loading...
{:#alumni .tiles}

<style>
.tiles {
	display: flex;
	list-style-type: none;
	flex-wrap: wrap;
	gap: 2em;
}
.tiles li {
	display: flex;
	flex-direction: column;
	gap: 0.25em;
}
</style>
";

//Given a saved config mapping, yield the info required for the front end.
continue mapping(string:mixed)|Concurrent.Future populate_config(mapping config) {
	//Gather the full available info about all streamers.
	//get_users_info will automatically cache, so we don't have to worry too much about cost.
	//However, follower counts are not included in that, so we kinda cheat.
	int basis = time() - 1;
	array streamers = yield(get_users_info(indices(config->streamers || ([]))));
	foreach (streamers; int i; mapping info) {
		if (info->_fetch_time >= basis || undefinedp(config->streamers[info->id]->followers)) { //Must have just been fetched
			config->streamers[info->id]->followers = yield(
				twitch_api_request("https://api.twitch.tv/helix/channels/followers?broadcaster_id=" + info->id)
			)->total;
		}
		streamers[i] = info | config->streamers[info->id];
	}
	sort(streamers->added, streamers);
	//Should we cache alumni data for even longer? Not sure.
	array alumni = yield(get_users_info(indices(config->alumni || ([]))));
	foreach (alumni; int i; mapping info)
		alumni[i] = info | config->alumni[info->id];
	sort(alumni->graduated, alumni);
	//Have any of the active streamers just hit affiliate?
	foreach (streamers; int i; mapping info) if (info->broadcaster_type != "") {
		config->alumni[info->id] = m_delete(config->streamers, info->id) | (["graduated": time()]);
		alumni += ({info | (["graduated": time()])});
		streamers[i] = 0;
	}
	return ([
		"streamers": streamers - ({0}),
		"alumni": alumni,
	]);
}

continue mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req) {
	int guide = (int)req->misc->session->user->?id;
	if (req->variables->guide) guide = yield(get_user_id(req->variables->guide));
	else if (mapping resp = ensure_login(req)) return resp;
	mapping config = persist_status->path("affiliate", (string)guide); //The path to the Path to Affiliate data :)
	if (!req->variables->guide) {
		//Editing is available only when logged in and not using the guide= parameter
		//Note that editing is done with JSON bodies and assumes front end control.
		if (string user = req->variables->add) {
			mapping info;
			if (mixed ex = catch {info = yield(get_user_info(user, "login"));})
				return (["error": 404]) | jsonify((["error": describe_error(ex)]));
			if (info->broadcaster_type != "")
				return (["error": 400]) | jsonify((["error": "Already " + info->broadcaster_type + "!"]));
			if (!config->streamers) config->streamers = ([]);
			config->streamers[info->id] = (["added": time()]);
			persist_status->save();
			return jsonify(yield(populate_config(config)));
		}
		if (string id = req->variables->remove) {
			//Should this also remove from alumni??
			if (!m_delete(config->streamers || ([]), id)) return (["error": 404]);
			persist_status->save();
			return jsonify(yield(populate_config(config)));
		}
	}
	mapping cfg = yield(populate_config(config));
	return render_template(markdown, ([
		"vars": ([
			"editable": !req->variables->guide,
			"config": cfg,
		]),
		"js": "affiliate.js",
		"guide": req->variables->guide || req->misc->session->user->login,
	]));
}
