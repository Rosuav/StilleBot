inherit http_endpoint;
inherit websocket_handler;

inherit command;
constant hidden_command = 1;
constant require_allcmds = 0;
constant active_channels = ({"devicat", "rosuav"}); //TODO: Choose where to activate this, even when not in allcmds

//Parse a timestamp into a valid Unix time. If ts is null, malformed,
//or in the past, returns 0.
int until(string ts, int now)
{
	object tm = Calendar.ISO.parse("%Y-%M-%DT%h:%m:%s%z", ts || "");
	return tm && tm->unix_time() > now && tm->unix_time();
}
mapping cached = 0; int cache_time = 0;
string token;

Concurrent.Future parse_hype_status(mapping data)
{
	int now = time();
	int cooldown = until(data->cooldown_end_time, now);
	int expires = until(data->expires_at, now);
	int checktime = expires || cooldown;
	if (checktime && checktime != G->G->hypetrain_checktime[data->broadcaster_id]) {
		//Schedule a check about when the hype train or cooldown will end.
		//If something changes before then (eg it goes to a new level),
		//we'll schedule a duplicate call_out, but otherwise, rechecking
		//repeatedly won't create a spew of call_outs that spam the API.
		G->G->hypetrain_checktime[data->broadcaster_id] = checktime;
		write("Scheduling a check of %s hype train at %d [%ds from now]\n",
			data->broadcaster_id, checktime, checktime - now + 1);
		call_out(probe_hype_train, checktime - now + 1, (int)data->broadcaster_id);
	}
	mapping state = ([
		"cooldown": cooldown, "expires": expires,
		"level": (int)data->level, "goal": (int)data->goal, "total": (int)data->total,
	]);
	return get_user_info(data->last_contribution->?user)->then(lambda(mapping lastcontrib) {
		//Show last contribution (with user name)
		state->lastcontrib = data->last_contribution || ([]);
		if (lastcontrib) state->lastcontrib->display_name = lastcontrib->display_name;
		array users = data->top_contributions->?user || ({ });
		return Concurrent.all(get_user_info(users[*]));
	})->then(lambda(array conductors) {
		//Show hype conductor stats (with user name)
		state->conductors = data->top_contributions || ({ });
		mapping cond = mkmapping(conductors->id, conductors);
		foreach (state->conductors, mapping c)
		{
			if (cond[c->user]) c->display_name = cond[c->user]->display_name;
		}
		return state;
	});
}

void hypetrain_progression(string chan, array data)
{
	int channel = (int)chan;
	parse_hype_status(data[0]->event_data)->then(lambda(mapping state) {send_updates_all(channel, state);});
}

Concurrent.Future get_state(int channel)
{
	if (G->G->webhook_active["hypetrain=" + channel] < 300)
	{
		write("Creating webhook for hype train %O\n", channel);
		create_webhook(
			"hypetrain=" + channel,
			"https://api.twitch.tv/helix/hypetrain/events?broadcaster_id=" + channel + "&first=1",
			1800,
			token,
		);
		/* Not working. See poll.pike for more info.
		create_eventsubhook(
			"hypetrainend=" + conn->group,
			"channel.hype_train.end", "1",
			(["broadcaster_user_id": (string)conn->group]),
			token,
		);
		*/
	}
	return twitch_api_request("https://api.twitch.tv/helix/hypetrain/events?broadcaster_id=" + (string)channel,
			(["Authorization": "Bearer " + token]))
		->then(lambda(mapping info) {
			mapping data = (sizeof(info->data) && info->data[0]->event_data) || ([]);
			return parse_hype_status(data);
		});
}

void probe_hype_train(int channel)
{
	write("Clock-pinging %d clients for hype train %d\n", sizeof(websocket_groups[channel]), channel);
	send_updates_all(channel);
}

constant emotes = #"HypeFighter HypeShield HypeKick HypeSwipe HypeRIP HypeGG
HypeRanger HypeMiss HypeHit HypeHeart HypeTarget HypeWink
HypeRogue HypeWut HypeGems HypeCoin HypeSneak HypeCash
HypeBard HypeTune HypeRun HypeZzz HypeRock HypeJuggle
HypeMage HypeWho HypeLol HypePotion HypeBook HypeSmoke";

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	string channel = req->variables["for"];
	if (!token || req->variables->reauth)
	{
		if (mapping resp = ensure_login(req, "channel:read:hype_train")) return resp;
		//Weirdly, this seems to work even if the broadcaster_id isn't the one you logged
		//in as, but you need to have the appropriate scope. So once we see a token that
		//works, save it, until it doesn't. (TODO: actually discard that token once it's
		//no longer valid.)
		token = req->misc->session->token;
	}
	mapping emotemd = G->G->emote_code_to_markdown || ([]);
	mapping emoteids = function_object(G->G->http_endpoints->checklist)->emoteids; //Hack!
	string avail_emotes = "";
	foreach (emotes / "\n", string level)
	{
		avail_emotes += "\n*";
		foreach (level / " ", string emote)
		{
			string md = emotemd[emote] || sprintf("![%s](https://static-cdn.jtvnw.net/emoticons/v1/%d/1.0)", emote, emoteids[emote]);
			if (!md) {avail_emotes += " " + emote; continue;}
			avail_emotes += sprintf(" %s*%s*", md, replace(md, "/1.0", "/3.0"));
		}
	}
	return (channel ? get_user_id(channel) : Concurrent.resolve(0))
		->then(lambda(int uid) {
			return render_template(req->variables->mobile ? "hypetrain_mobile.html" : "hypetrain.md", ([
				"vars": (["ws_type": uid && "hypetrain", "ws_group": uid]),
				"loading": uid ? "Loading hype status..." : "(no channel selected)",
				"channelname": channel || "(no channel)",
				"emotes": avail_emotes,
				"backlink": !req->variables->mobile && sprintf("<a href=\"hypetrain?for=%s&mobile\">Switch to mobile view</a>", channel || ""),
			]));
		}); //TODO: If auth error, clear the token
}

echoable_message process(object channel, object person, string param)
{
	get_user_id(channel->name[1..])->then(lambda(int id) {return get_state(id);})->then(lambda(mapping state) {
		if (state->expires) {
			//Active hype train!
			if (state->total >= state->goal)
				send_message(channel->name, "MrDestructoid Hype Train status: HypeUnicorn1 HypeUnicorn2 HypeUnicorn3 HypeUnicorn4 HypeUnicorn5 HypeUnicorn6 LEVEL FIVE COMPLETE!");
			else send_message(channel->name, sprintf(
				"/me MrDestructoid Hype Train status: devicatParty HYPE! Level %d requires %d more bits or %d subs!",
				state->level, state->goal - state->total, (state->goal - state->total + 499) / 500));
		} else if (state->cooldown) {
			int tm = state->cooldown - time();
			send_message(channel->name, sprintf(
				"/me MrDestructoid Hype Train status: devicatCozy The hype train is on cooldown for %02d:%02d. kittenzSleep",
				tm / 60, tm % 60));
		} else send_message(channel->name, "/me MrDestructoid Hype Train status: NomNom Cookies are done! NomNom");
	});
}

protected void create(string name)
{
	::create(name);
	if (G->G->webhook_endpoints->hypetrain)
		token = function_object(G->G->webhook_endpoints->hypetrain)->token;
	G->G->webhook_endpoints->hypetrain = hypetrain_progression;
	if (!G->G->hypetrain_checktime) G->G->hypetrain_checktime = ([]);
	G->G->commands["trainstatus"] = check_perms;
}
