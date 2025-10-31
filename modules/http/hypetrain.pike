inherit http_endpoint;
inherit websocket_handler;
inherit annotated;
inherit builtin_command;
inherit hook;
@retain: mapping hypetrain_checktime = ([]);
@retain: mapping hypetrain_info = ([]);

//Parse a timestamp into a valid Unix time. If ts is null, malformed,
//or in the past, returns 0.
int until(string ts, int now)
{
	object tm = time_from_iso(ts || "");
	return tm && tm->unix_time() > now && tm->unix_time();
}

mapping parse_hype_status(string channelid, mapping data, int|void hack_now) { //Pass a hacked 'now' value when reconstructing previous events
	mapping current = data->current || data; //EventSub messages have nothing BUT the current info, queries also get the all-time high
	mapping retained = hypetrain_info[channelid];
	if (!retained) hypetrain_info[channelid] = retained = ([]);
	if (data->all_time_high) retained->all_time_high = data->all_time_high;
	if (data->shared_all_time_high) retained->shared_all_time_high = data->shared_all_time_high;
	int now = hack_now || time();
	int cooldown = retained->cooldown = (until(current->cooldown_ends_at, now) || retained->cooldown);
	int expires = until(current->expires_at, now);
	int checktime = expires || cooldown;
	if (checktime && checktime != hypetrain_checktime[channelid]) {
		//Schedule a check about when the hype train or cooldown will end.
		//If something changes before then (eg it goes to a new level),
		//we'll schedule a duplicate call_out, but otherwise, rechecking
		//repeatedly won't create a spew of call_outs that spam the API.
		hypetrain_checktime[channelid] = checktime;
		call_out(send_updates_all, checktime - now + 1, current->broadcaster_user_login);
	}
	if (expires && !cooldown) {
		//Cooldowns are not always provided. We retain this info if we possibly can, but
		//otherwise, we have to guess that it's an hour after expiration.
		retained->cooldown = expires + 55 * 60;
	}
	//Grab what info we have, otherwise keep what we previously had.
	foreach (({"level", "goal", "total", "progress"}), string key)
		if (int val = (int)current[key]) retained[key] = val;
	mapping state = retained | ([
		"expires": expires,
	]);
	if (hack_now) state->hack_now = hack_now;
	if (state->cooldown < now) m_delete(state, "cooldown"); //Cooldowns in the past are irrelevant.
	//The API has one format, the eventsub notification has another. Sigh. Synchronize manually.
	foreach (current->top_contributions || ({ }), mapping user) {
		//API says "bits", events say "BITS". This is inverted from how it used to be in v1,
		//and I still don't care about the distinction.
		user->type = (["bits": "BITS", "subscription": "SUBS"])[user->type] || user->type;
	}
	//For shared hype trains, show other participants, including their avatars etc
	foreach (current->shared_train_participants || ({ }), mapping chan) {
		if (chan->broadcaster_user_id == channelid) continue;
		mapping|zero chaninfo = cached_user_info((int)chan->broadcaster_user_id);
		if (chaninfo) chan |= chaninfo;
		state->shared_train_participants += ({chan});
	}
	state->conductors = current->top_contributions || ({ });
	state->type = current->type || "regular";
	return state;
}

@EventNotify("channel.hype_train.begin=2"):
@EventNotify("channel.hype_train.progress=2"):
@EventNotify("channel.hype_train.end=2"):
void hypetrain_progression(object chan, mapping info) {
	if (info->type != "regular" && info->type != "golden_kappa")
		//Log info about any unusual hype trains. Anything we don't understand, log; also, I haven't yet seen
		//a successful Treasure Train, so it would be useful to see that happen. As of 20251031, only three
		//types are officially supported (regular/golden_kappa/treasure), but if more get added, log them too.
		//Fetch up the info that we get when loading the page, and provide both eventsub and API info for me to
		//eventually delve through, some day.
		twitch_api_request("https://api.twitch.tv/helix/hypetrain/status?broadcaster_id=" + chan->userid,
			(["Authorization": chan->userid]))->then() {
				Stdio.append_file("evthook.log", sprintf("EVENT: Hype train [%O, %d]: %O\nFetched: %O\n", chan, time(), info, __ARGS__[0]));
			};

	send_updates_all(info->broadcaster_user_login, parse_hype_status(info->broadcaster_user_id, info));
}

__async__ mapping get_state(int|string chan)
{
	if (chan == "-") return 0; //Shouldn't happen - will be from a page with no for= and not logged in.
	if (chan == "!demo") return ([
		"expires": time() + 180, //Three minutes left on the demo hype train, as of when you load the page
		"level": 2, "goal": 1800, "total": 500,
		"conductors": ({([
			"total": 100,
			"type": "BITS",
			"user": "49497888",
			"user_name": "Demo User",
		]), ([
			"total": 500,
			"type": "SUBS",
			"user": "279141671",
			"user_name": "MustardMine",
		])}),
		"all_time_high": ([
			"achieved_at": "2024-06-03T00:54:34.843901245Z",
			"level": 4,
			"total": 5500
		]),
	]);
	mixed ex = catch {
		int uid;
		if (intp(chan)) {//Deprecated, might change everything to be all channel names at some point
			uid = chan;
			chan = await(get_user_info(uid))->login;
		}
		else uid = await(get_user_id(chan));
		//When reevaluating previous hype status, grab the blob from evthook.log, and include the time_t as a third param.
		//if (some_cond) return parse_hype_status((string)uid, ([... "goal": 1800, ...]), 1758336158);
		mapping info = await(twitch_api_request("https://api.twitch.tv/helix/hypetrain/status?broadcaster_id=" + uid,
				(["Authorization": "Bearer " + token_for_user_id(uid)[0]]))); //Note: using just uid here causes errors to be reported differently, which fails below
		//If there's an error fetching events, don't set up hooks
		establish_notifications(uid);
		mapping data = (sizeof(info->data) && info->data[0]) || ([]);
		return parse_hype_status((string)uid, data);
	};
	if (ex && arrayp(ex) && stringp(ex[0]) && has_value(ex[0], "Error from Twitch") && has_value(ex[0], "401"))
		return (["error": "Authentication problem. It may help to ask the broadcaster to open this page: ", "errorlink": "https://mustardmine.com/hypetrain?for=" + chan]);
	throw(ex);
}

//Confirmed as all unlockable 20250915
constant emotes = #"FrogPonder ChillGirl ButtonMash BatterUp GoodOne MegaConsume SpillTheTea ThatsAServe WhosThisDiva ConfettiHype FrogWow
AGiftForYou KittyHype DangerDance PersonalBest HenloThere GimmeDat RespectfullyNo ThatsIconique HerMind ImSpiraling LuvLuvLUV
MegaMlep RawkOut FallDamage RedCard ApplauseBreak TouchOfSalt NoComment DownBad UghMood ShyGhost MeSweat
KittyLove TurnUp CatScare LateSave NoTheyDidNot BeholdThis TheyAte PlotTwist AnActualQueen LilTrickster HiHand
RaccoonPop GoblinJam YouMissed GriddyGoose CheersToThat StirThePot PackItUp InTheirBag SpitTheTruth PufferPop IAmClap
Bonus emotes for high level hype trains: BleedPurpleHD HeyHeyGuys PogChomp KappaInfinite";
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
				if (!id) {avail_emotes += " " + emote; continue;} //Label text gets kept; so will any emotes missed from the ID lookups
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
			"loading": "(no channel selected)",
			"channelname": "(no channel)",
			"nojs": "", //Remove JS-controlled buttons
			"emotes": "",
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
		//TODO: When emote IDs are easily available, provide the matrix of emotes
		//and their IDs to the front end, instead of doing it with a Markdown list.
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
	if (c->type == "BITS") return sprintf("%s with %d bits", c->user_name, c->total);
	return sprintf("%s with %d subs", c->user_name, c->total / 500);
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
