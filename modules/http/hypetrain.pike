inherit http_endpoint;
inherit websocket_handler;
inherit annotated;
inherit builtin_command;
inherit hook;
@retain: mapping hypetrain_checktime = ([]);

//Parse a timestamp into a valid Unix time. If ts is null, malformed,
//or in the past, returns 0.
int until(string ts, int now)
{
	object tm = time_from_iso(ts || "");
	return tm && tm->unix_time() > now && tm->unix_time();
}
mapping cached = 0; int cache_time = 0;

__async__ mapping parse_hype_status(mapping data)
{
	int now = time();
	int cooldown = until(data->cooldown_end_time || data->cooldown_ends_at, now);
	int expires = until(data->expires_at, now);
	int checktime = expires || cooldown;
	string channelid = data->broadcaster_id || data->broadcaster_user_id;
	if (checktime && checktime != hypetrain_checktime[data->broadcaster_id]) {
		//Schedule a check about when the hype train or cooldown will end.
		//If something changes before then (eg it goes to a new level),
		//we'll schedule a duplicate call_out, but otherwise, rechecking
		//repeatedly won't create a spew of call_outs that spam the API.
		hypetrain_checktime[data->broadcaster_id] = checktime;
		call_out(probe_hype_train, checktime - now + 1, (int)channelid);
	}
	if (expires && !cooldown) {
		//There's a weird issue with the eventsub message: the cooldown is omitted.
		//For simplicity's sake, assume that it'll be 55 minutes after the expiry
		//(which will be true if, and only if, there's a one-hour cooldown).
		cooldown = expires + 55 * 60;
	}
	mapping state = ([
		"cooldown": cooldown, "expires": expires,
		"level": (int)data->level, "goal": (int)data->goal,
		"total": data->progress || (int)data->total, //Different format problems. Sigh.
		"is_golden_kappa_train": data->is_golden_kappa_train,
	]);
	//The API has one format, the eventsub notification has another. Sigh. Synchronize manually.
	foreach (data->top_contributions + ({data->last_contribution}) - ({0}), mapping user) {
		if (user->user_id) user->user = user->user_id;
		if (user->user_name) user->display_name = user->user_name;
		else user->display_name = await(get_user_info(user->user))->display_name;
		user->type = (["bits": "BITS", "subscription": "SUBS"])[user->type] || user->type; //Events say "bits", API says "BITS".
	}
	state->lastcontrib = data->last_contribution || ([]);
	state->conductors = data->top_contributions || ({ });
	return state;
}

@EventNotify("channel.hype_train.begin=1"):
@EventNotify("channel.hype_train.progress=1"):
@EventNotify("channel.hype_train.end=1"):
void hypetrain_progression(object chan, mapping info) {
	//Stdio.append_file("evthook.log", sprintf("EVENT: Hype %s [%O, %d]: %O\n", status, chan, time(), info));
	parse_hype_status(info)->then() {send_updates_all(info->broadcaster_user_login, @__ARGS__);};
}

__async__ mapping get_state(int|string chan)
{
	if (chan == "-") return 0; //FIXME: What causes a state of "-" and is that still a thing?
	if (chan == "!demo") return ([
		"expires": time() + 180, //Three minutes left on the demo hype train, as of when you load the page
		"level": 2, "goal": 1800, "total": 500,
		"conductors": ({([
			"display_name": "Demo User",
			"total": 100,
			"type": "BITS",
			"user": "49497888",
		]), ([
			"display_name": "MustardMine",
			"total": 500,
			"type": "SUBS",
			"user": "279141671",
		])}),
		"lastcontrib": ([
			"display_name": "Demo User",
			"total": 100,
			"type": "BITS",
			"user": "49497888",
		]),
	]);
	mixed ex = catch {
		string uid;
		if (intp(chan)) {//Deprecated, might change everything to be all channel names at some point
			uid = (string)chan;
			chan = await(get_user_info(chan))->login;
		}
		else uid = (string)await(get_user_id(chan));
		mapping info = await(twitch_api_request("https://api.twitch.tv/helix/hypetrain/events?broadcaster_id=" + uid,
				(["Authorization": "Bearer " + token_for_user_id(uid)[0]])));
		//If there's an error fetching events, don't set up hooks
		establish_notifications(uid);
		mapping data = (sizeof(info->data) && info->data[0]->event_data) || ([]);
		return await(parse_hype_status(data));
	};
	if (ex && arrayp(ex) && stringp(ex[0]) && has_value(ex[0], "Error from Twitch") && has_value(ex[0], "401"))
		return (["error": "Authentication problem. It may help to ask the broadcaster to open this page: ", "errorlink": "https://mustardmine.com/hypetrain?for=" + chan]);
	throw(ex);
}

void probe_hype_train(int channel) {
	get_user_info(channel)->then() {send_updates_all(__ARGS__[0]->login);};
}

constant emotes = #"HypeCute HypeYummy HypeKEKW HypeNoods HypeOho
HypeHi HypeChill HypeMyHeart HypeWarm HypeFist
HypeCries HypeGGEyes HypeAwh HypeElf HypeDelight
HypeNotLikeSnow HypePls HypeMelt HypeCocoa HypeConfetti
HypeSanta HypePeek HypeOhDeer HypeUwu HypeLick";
string avail_emotes = "";

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	if (avail_emotes == "") {
		mapping botemotes = await(G->G->DB->load_config(G->G->bot_uid, "bot_emotes"));
		mapping emoteids = function_object(G->G->http_endpoints->checklist)->emoteids; //Hack!
		avail_emotes = "";
		foreach (emotes / "\n", string level)
		{
			avail_emotes += "\n*";
			foreach (level / " ", string emote)
			{
				string id = botemotes[emote] || emoteids[emote];
				if (!id) continue;
				string md = sprintf("![%s](%s)", emote, emote_url(id, 1));
				if (!md) {avail_emotes += " " + emote; continue;}
				avail_emotes += sprintf(" %s*%s*", md, replace(md, "/1.0", "/3.0"));
			}
		}
	}
	string chan = lower_case(req->variables["for"] || "");
	if (chan == "") {
		//If you've just logged in, assume that you want your own hype train stats.
		//Make sure that the page link is viably copy-pastable.
		if (req->misc->session->scopes[?"channel:read:hype_train"])
			return redirect("hypetrain?for=" + req->misc->session->user->login);
		return render_template(req->variables->mobile ? "hypetrain_mobile.html" : "hypetrain.md", ([
			"vars": (["ws_type": "hypetrain", "ws_group": "-"]),
			"loading": "(no channel selected)",
			"channelname": "(no channel)",
			//TODO: When emote IDs are easily available, provide the matrix of emotes
			//and their IDs to the front end, instead of doing it with a Markdown list.
			"emotes": avail_emotes,
			"backlink": !req->variables->mobile && "<a href=\"hypetrain?mobile\">Switch to mobile view</a>",
		]));
	}
	int need_token = 1; catch {need_token = token_for_user_login(chan)[0] == "";};
	string scopes = ensure_bcaster_token(req, "channel:read:hype_train", chan);
	//If we got a fresh token, push updates out, in case they had errors
	if (need_token && !scopes) send_updates_all(chan);

	return render_template(req->variables->mobile ? "hypetrain_mobile.html" : "hypetrain.md", ([
		"vars": (["ws_type": "hypetrain", "ws_group": chan, "need_scopes": scopes || ""]),
		"loading": "Loading hype status...",
		"channelname": chan, "emotes": avail_emotes,
		"backlink": !req->variables->mobile && sprintf("<a href=\"hypetrain?for=%s&mobile\">Switch to mobile view</a>", chan),
	]));
}

constant builtin_description = "Get info about a current or recent hype train in this channel";
constant builtin_name = "Hype Train status";
constant scope_required = "channel:read:hype_train";
constant command_suggestions = (["!hypetrain": ([
	"_description": "Show the status of a hype train in this channel, or the cooldown before the next can start",
	"conditional": "catch",
	"message": ([
		"builtin": "hypetrain",
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
	]),
	"otherwise": "{error}",
])]);
constant vars_provided = ([
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
	"{expires_secs}": "Total number of seconds until the hype train runs out of time",
	"{cooldown}": "Minutes:Seconds until the next hype train can start (only if Cooldown)",
	"{cooldown_secs}": "Total number of seconds until the next hype train",
]);

string fmt_contrib(mapping c) {
	if (c->type == "BITS") return sprintf("%s with %d bits", c->display_name, c->total);
	return sprintf("%s with %d subs", c->display_name, c->total / 500);
}

__async__ mapping message_params(object channel, mapping person, array param, mapping cfg) {
	if (cfg->simulate) return ([]); //TODO: Do the query once and then cache the result so we get correct data, just not spamming API calls
	mapping state = await(get_state(channel->name[1..]));
	if (state->error) error(state->error + " " + state->errorlink + "\n");
	mapping conductors = (["SUBS": "Nobody", "BITS": "Nobody"]);
	string|array allcond = ({ });
	foreach (state->conductors || ({ }), mapping c)
		allcond += ({conductors[c->type] = fmt_contrib(c)});
	allcond = sizeof(allcond) ? allcond * ", and " : "None";
	if (state->expires) {
		int tm = state->expires - time();
		return ([
			"{state}": "active",
			"{level}": (string)state->level,
			"{total}": (string)state->total,
			"{goal}": (string)state->goal,
			"{needbits}": (string)(state->goal - state->total),
			"{needsubs}": (string)((state->goal - state->total + 499) / 500),
			"{expires}": sprintf("%02d:%02d", tm / 60, tm % 60),
			"{expires_secs}": (string)tm,
			"{conductors}": allcond, "{subs_conduct}": conductors->SUBS, "{bits_conduct}": conductors->BITS,
		]);
	} else if (state->cooldown) {
		int tm = state->cooldown - time();
		return ([
			"{state}": "cooldown",
			"{level}": (string)state->level,
			"{total}": (string)state->total,
			"{goal}": (string)state->goal,
			"{cooldown}": sprintf("%02d:%02d", tm / 60, tm % 60),
			"{cooldown_secs}": (string)tm,
			"{conductors}": allcond, "{subs_conduct}": conductors->SUBS, "{bits_conduct}": conductors->BITS,
		]);
	} else return (["{state}": "idle"]);
}

protected void create(string name) {::create(name);}
