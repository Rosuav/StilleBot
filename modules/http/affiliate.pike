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

> ### Recommendations!
>
> Hoping to reach affiliate and beyond? Here are a few tips that our Algorithm thinks
> might be helpful to you.
>
> * loading...
> {: #tips}
>
> [Close](:.dialog_close)
{: tag=dialog #recomdlg}
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

continue array(string|array|mapping)|Concurrent.Future generate_recommendations(int id) {
	string login = yield(get_user_info(id))->login;
	array recom = ({ //Start with some standard ones.
		"At the end of each stream, raid someone! Make new friends, be seen by another community, network!",
		"Engage with your viewers, even if it seems like there's nobody there. Lurkers are awesome :)",
	});

	//TIP: Have a schedule
	mapping info = yield(twitch_api_request("https://api.twitch.tv/helix/schedule?broadcaster_id=" + id, 0, (["return_errors": 1])));
	array sched = info->data->?segments || ({ });
	int schedule_good = 0;
	if (!sizeof(sched)) recom += ({"Have a stream schedule so people know when to find you."});
	else {
		//In order to hit the "7 stream days" and "8 total hours" achievements,
		//you need to average about two streams per week, and two hours per week.
		int next_week = time() + 604800;
		int sched_time, total_days, last_day;
		foreach (sched, mapping segment) {
			int start = Calendar.parse("%Y-%M-%DT%h:%m:%s%z", segment->start_time)->unix_time();
			if (start > next_week) break;
			//NOTE: Due to the way Twitch measures, it's possible for a single stream to
			//count as two days (if it goes over UTC rollover). I'm not going to recommend
			//that though, as it's dependent on the exact time you end, which a lot of
			//streamers aren't precise with. So I'm going to simply recommend having two
			//schedule slots per week (or, slots on two separate UTC days).
			//And yes, it's based on UTC, not America/Los_Angeles.
			if (start / 86400 != last_day) {total_days += 1; last_day = start / 86400;}
			int end = Calendar.parse("%Y-%M-%DT%h:%m:%s%z", segment->end_time)->unix_time();
			sched_time += end - start;
		}
		//These recommendations are based on the assumption that you stream a regular weekly
		//schedule. Temporary disriptions to it will cause potentially confusing recoms.
		if (total_days < 2) recom += ({"Stream on at least two separate days each week."});
		else if (sched_time < 7200) recom += ({"Stream for at least two hours each week."}); //Don't bother showing this if you only have one day a week.
		else schedule_good = 1;
	}
	if (!schedule_good) recom += ({({
		"You can ",
		([
			"message": "edit your schedule here",
			"link": "https://dashboard.twitch.tv/u/" + login + "/settings/channel/schedule",
		]),
		" and let all of your viewers know when you'll be live!",
	})});
	//TIP: Avoid chat restrictions
	mapping settings = yield(twitch_api_request("https://api.twitch.tv/helix/chat/settings?broadcaster_id=" + id));
	if (arrayp(settings->data) && sizeof(settings->data)) {
		mapping set = settings->data[0];
		//Note that some settings aren't major turn-offs, so this isn't simply "is anything set".
		int restrictions = 0;
		mapping issues = ([
			"emote_mode": "Emote-only mode restricts your chat; it's usually not necessary, but it's a fun channel toy when used temporarily!",
			"follower_mode": "Follower-only mode can turn people away before you even see whether they'd be interested.",
			"subscriber_mode": "Subscriber-only mode is a severe restriction that requires people to financially support you to chat!", //Almost certainly not going to be seen!
			"unique_chat_mode": "Requiring 'unique chat' is a fun channel toy, but otherwise can turn people away.",
		]);
		foreach (issues; string key; string msg) if (set[key]) {
			restrictions = 1;
			recom += ({msg});
		}
		//If there are any restrictions, add the link at the end.
		if (restrictions) recom += ({
			"Chat restrictions can be ",
			([
				"message": "configured on your Twitch Dashboard",
				"link": "https://dashboard.twitch.tv/u/" + login + "/settings/moderation",
			]),
			". While you're there, it's a great idea to list your chat rules so people know where they stand.",
		});
	}
	return recom;
}

continue mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req) {
	if (int id = (int)req->variables->recommend) {
		//Recommendations are independent of the guide.
		array recoms = yield(generate_recommendations(id));
		return jsonify((["recommendations": recoms]));
	}
	int guide = (int)req->misc->session->user->?id;
	if (req->variables->guide) guide = yield(get_user_id(req->variables->guide));
	else if (mapping resp = ensure_login(req)) return resp;
	mapping config = persist_status->path("affiliate", (string)guide); //The path to the Path to Affiliate data :)
	if (!req->variables->guide) {
		if (!config->streamers) {
			config->streamers = ([]);
			//If you are not yourself affiliated/partnered, include your own box
			//initially. You can remove yourself though (and you won't autorespawn).
			mapping info = yield(get_user_info(guide));
			if (info->broadcaster_type == "") config->streamers[info->id] = (["added": time()]);
			persist_status->save(); //Always save the fact that config->streamers is non-null; no rechecks.
		}
		//Editing is available only when logged in and not using the guide= parameter
		//Note that editing is done with JSON bodies and assumes front end control.
		if (string user = req->variables->add) {
			mapping info;
			if (mixed ex = catch {info = yield(get_user_info(user, "login"));})
				return (["error": 404]) | jsonify((["error": describe_error(ex)]));
			if (info->broadcaster_type != "")
				return (["error": 400]) | jsonify((["error": "Already " + info->broadcaster_type + "!"]));
			config->streamers[info->id] = (["added": time()]);
			persist_status->save();
			return jsonify(yield(populate_config(config)));
		}
		if (string id = req->variables->remove) {
			//Should this also remove from alumni??
			if (!m_delete(config->streamers, id)) return (["error": 404]);
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
