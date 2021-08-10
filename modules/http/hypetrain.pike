inherit http_endpoint;
inherit websocket_handler;

inherit builtin_command;
constant featurename = "info";
constant hidden_command = 1;

//Parse a timestamp into a valid Unix time. If ts is null, malformed,
//or in the past, returns 0.
int until(string ts, int now)
{
	object tm = Calendar.ISO.parse("%Y-%M-%DT%h:%m:%s%z", ts || "");
	if (!tm) tm = Calendar.ISO.parse("%Y-%M-%DT%h:%m:%s.%f%z", ts || "");
	return tm && tm->unix_time() > now && tm->unix_time();
}
mapping cached = 0; int cache_time = 0;

continue mapping|Concurrent.Future parse_hype_status(mapping data)
{
	int now = time();
	int cooldown = until(data->cooldown_end_time || data->cooldown_ends_at, now);
	int expires = until(data->expires_at, now);
	int checktime = expires || cooldown;
	string channelid = data->broadcaster_id || data->broadcaster_user_id;
	if (checktime && checktime != G->G->hypetrain_checktime[data->broadcaster_id]) {
		//Schedule a check about when the hype train or cooldown will end.
		//If something changes before then (eg it goes to a new level),
		//we'll schedule a duplicate call_out, but otherwise, rechecking
		//repeatedly won't create a spew of call_outs that spam the API.
		G->G->hypetrain_checktime[data->broadcaster_id] = checktime;
		write("Scheduling a check of %s hype train at %d [%ds from now]\n",
			channelid, checktime, checktime - now + 1);
		call_out(probe_hype_train, checktime - now + 1, (int)channelid);
	}
	mapping state = ([
		"cooldown": cooldown, "expires": expires,
		"level": (int)data->level, "goal": (int)data->goal, "total": (int)data->total,
	]);
	//The API has one format, the eventsub notification has another. Sigh. Synchronize manually.
	foreach (data->top_contributions + ({data->last_contribution}) - ({0}), mapping user) {
		if (user->user_id) user->user = user->user_id;
		if (user->user_name) user->display_name = user->user_name;
		else user->display_name = yield(get_user_info(data->last_contribution->user))->display_name;
		user->type = (["bits": "BITS", "subscription": "SUBS"])[user->type] || user->type; //Events say "bits", API says "BITS".
	}
	state->lastcontrib = data->last_contribution || ([]);
	state->conductors = data->top_contributions || ({ });
	return state;
}

void hypetrain_progression(string status, string chan, mapping info)
{
	//Stdio.append_file("evthook.log", sprintf("EVENT: Hype %s [%O, %d]: %O\n", status, chan, time(), info));
	handle_async(parse_hype_status(info)) {send_updates_all((int)chan, @__ARGS__);};
}

EventSub hypetrain_begin = EventSub("hypetrain_begin", "channel.hype_train.begin", "1") {hypetrain_progression("begin", @__ARGS__);};
EventSub hypetrain_progress = EventSub("hypetrain_progress", "channel.hype_train.progress", "1") {hypetrain_progression("progress", @__ARGS__);};
EventSub hypetrain_end = EventSub("hypetrain_end", "channel.hype_train.end", "1") {hypetrain_progression("end", @__ARGS__);};

continue mapping|Concurrent.Future get_state(int|string chan)
{
	mixed ex = catch {
		string uid;
		if (intp(chan)) {//Deprecated, might change everything to be all channel names at some point
			uid = (string)chan;
			chan = yield(get_user_info(chan))->login;
		}
		else uid = (string)yield(get_user_id(chan));
		hypetrain_begin(uid, (["broadcaster_user_id": uid]));
		hypetrain_progress(uid, (["broadcaster_user_id": uid]));
		hypetrain_end(uid, (["broadcaster_user_id": uid]));
		mapping info = yield(twitch_api_request("https://api.twitch.tv/helix/hypetrain/events?broadcaster_id=" + uid,
				(["Authorization": "Bearer " + persist_status->path("bcaster_token")[chan]])));
		mapping data = (sizeof(info->data) && info->data[0]->event_data) || ([]);
		return parse_hype_status(data);
	};
	if (ex && arrayp(ex) && stringp(ex[0]) && has_value(ex[0], "Error from Twitch") && has_value(ex[0], "401")) {
		return (["error": "Authentication problem. It may help to ask the broadcaster to open this page: ", "errorlink": "https://sikorsky.rosuav.com/hypetrain?for=" + chan]);
	}
	throw(ex);
}

void probe_hype_train(int channel)
{
	write("Clock-pinging %d clients for hype train %d\n", sizeof(websocket_groups[channel] || ([])), channel);
	send_updates_all(channel);
}

constant emotes = #"HypeHeh HypeDoh HypeYum HypeShame HypeHide HypeWow
HypeTongue HypePurr HypeOoh HypeBeard HypeEyes HypeHay
HypeYesPlease HypeDerp HypeJudge HypeEars HypeCozy HypeYas
HypeWant HypeStahp HypeYawn HypeCreep HypeDisguise HypeAttack
HypeScream HypeSquawk HypeSus HypeHeyFriends HypeMine HypeShy";

string url(int|string id) { //TODO: Dedup with the one in checklist
	if (intp(id)) return sprintf("https://static-cdn.jtvnw.net/emoticons/v1/%d/1.0", id);
	return sprintf("https://static-cdn.jtvnw.net/emoticons/v2/%s/default/light/1.0", id);
}
string avail_emotes = "";

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	string chan = lower_case(req->variables["for"] || "");
	if (chan == "") {
		//If you've just logged in, assume that you want your own hype train stats.
		//Make sure that the page link is viably copy-pastable.
		if (req->misc->session->scopes[?"channel:read:hype_train"])
			return redirect("hypetrain?for=" + req->misc->session->user->login);
		return render_template(req->variables->mobile ? "hypetrain_mobile.html" : "hypetrain.md", ([
			"loading": "(no channel selected)",
			"channelname": "(no channel)",
			"emotes": avail_emotes,
			"backlink": !req->variables->mobile && "<a href=\"hypetrain?mobile\">Switch to mobile view</a>",
		]));
	}
	int need_token = !persist_status->path("bcaster_token")[chan];
	string scopes = ensure_bcaster_token(req, "channel:read:hype_train", chan);
	//If we got a fresh token, push updates out, in case they had errors
	if (need_token && !scopes) send_updates_all(chan);
	if (avail_emotes == "") {
		mapping emotemd = G->G->emote_code_to_markdown || ([]);
		mapping emoteids = function_object(G->G->http_endpoints->checklist)->emoteids; //Hack!
		avail_emotes = "";
		foreach (emotes / "\n", string level)
		{
			avail_emotes += "\n*";
			foreach (level / " ", string emote)
			{
				string md = emotemd[emote] || sprintf("![%s](%s)", emote, url(emoteids[emote]));
				if (!md) {avail_emotes += " " + emote; continue;}
				avail_emotes += sprintf(" %s*%s*", md, replace(md, "/1.0", "/3.0"));
			}
		}
	}
	return render_template(req->variables->mobile ? "hypetrain_mobile.html" : "hypetrain.md", ([
		"vars": (["ws_type": "hypetrain", "ws_group": chan, "need_scopes": scopes || ""]),
		"loading": "Loading hype status...",
		"channelname": chan, "emotes": avail_emotes,
		"backlink": !req->variables->mobile && sprintf("<a href=\"hypetrain?for=%s&mobile\">Switch to mobile view</a>", chan),
	]));
}

constant command_description = "Show the status of a hype train in this channel, or the cooldown before the next can start";
constant builtin_description = "Get hype train status for this channel";
constant builtin_name = "Hype Train";
constant default_response = ([
	"conditional": "string", "expr1": "{error}", "expr2": "",
	"message": ([
		"conditional": "string", "expr1": "{state}", "expr2": "active",
		"message": ([
			"conditional": "number", "expr1": "{needbits} <= 0",
			"message": "/me MrDestructoid Hype Train status: HypeUnicorn1 HypeUnicorn2 HypeUnicorn3 HypeUnicorn4 HypeUnicorn5 HypeUnicorn6 LEVEL FIVE COMPLETE!",
			"otherwise": "/me MrDestructoid Hype Train status: devicatParty HYPE! Level {level} requires {needbits} more bits or {needsubs} subs!"
		]),
		"otherwise": ([
			"conditional": "string", "expr1": "{state}", "expr2": "cooldown",
			"message": "/me MrDestructoid Hype Train status: devicatCozy The hype train is on cooldown for {cooldown}. kittenzSleep",
			"otherwise": "/me MrDestructoid Hype Train status: NomNom Cookies are done! NomNom"
		])
	]),
	"otherwise": "{error}",
]);
constant vars_provided = ([
	"{error}": "Normally blank, but can have an error message",
	"{state}": "A keyword (idle, active, cooldown). If idle, there's no other info; if cooldown, info pertains to the last hype train.",
	"{level}": "The level that we're currently in (1-5)",
	"{total}": "The total number of bits or bits-equivalent contributed towards this level",
	"{goal}": "The number of bits or bits-equivalent to complete this level",
	"{needbits}": "The number of additional bits required to complete this level (== goal minus total)",
	"{needsubs}": "The number of Tier 1 subs that would complete this level",
	"{conductors}": "Either None or a list of the current conductors",
	"{subs_conduct}": "Either Nobody or the name of the current conductor for subs",
	"{bits_conduct}": "Either Nobody or the name of the current conductor for bits",
	"{expires}": "Minutes:Seconds until the hype train runs out of time (only if Active)",
	"{cooldown}": "Minutes:Seconds until the next hype train can start (only if Cooldown)",
]);

string fmt_contrib(mapping c) {
	if (c->type == "BITS") return sprintf("%s with %d bits", c->display_name, c->total);
	return sprintf("%s with %d subs", c->display_name, c->total / 500);
}

continue mapping|Concurrent.Future message_params(object channel, mapping person, string param)
{
	mapping state = yield(get_state(channel->name[1..]));
	if (state->error) return (["{error}": state->error + " " + state->errorlink]);
	mapping conductors = (["SUBS": "Nobody", "BITS": "Nobody"]);
	string|array allcond = ({ });
	foreach (state->conductors || ({ }), mapping c)
		allcond += ({conductors[c->type] = fmt_contrib(c)});
	allcond = sizeof(allcond) ? allcond * ", and " : "None";
	if (state->expires) {
		int tm = state->expires - time();
		return ([
			"{error}": "",
			"{state}": "active",
			"{level}": (string)state->level,
			"{total}": (string)state->total,
			"{goal}": (string)state->goal,
			"{needbits}": (string)(state->goal - state->total),
			"{needsubs}": (string)((state->goal - state->total + 499) / 500),
			"{expires}": sprintf("%02d:%02d", tm / 60, tm % 60),
			"{conductors}": allcond, "{subs_conduct}": conductors->SUBS, "{bits_conduct}": conductors->BITS,
		]);
	} else if (state->cooldown) {
		int tm = state->cooldown - time();
		return ([
			"{error}": "",
			"{state}": "cooldown",
			"{level}": (string)state->level,
			"{total}": (string)state->total,
			"{goal}": (string)state->goal,
			"{cooldown}": sprintf("%02d:%02d", tm / 60, tm % 60), //TODO: H:M:S ?
			"{conductors}": allcond, "{subs_conduct}": conductors->SUBS, "{bits_conduct}": conductors->BITS,
		]);
	} else return (["{error}": "", "{state}": "idle"]);
}

protected void create(string name)
{
	::create(name);
	if (!G->G->hypetrain_checktime) G->G->hypetrain_checktime = ([]);
}
