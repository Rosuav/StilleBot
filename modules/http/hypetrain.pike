inherit http_endpoint;
inherit websocket_handler;

inherit command;
constant hidden_command = 1;
constant require_allcmds = 0;
constant active_channels = ({"devicat", "rosuav"}); //TODO: Choose where to activate this, even when not in allcmds

//TODO: Add a timer to report on expirations so they happen on the WS too

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
	parse_hype_status(data[0]->event_data)->then(lambda(mapping state) {
		state->cmd = "update";
		write("Pinging %d clients for hype train %d\n", sizeof(websocket_groups[channel]), channel);
		(websocket_groups[channel] - ({0}))->send_text(Standards.JSON.encode(state));
	});
}

Concurrent.Future get_hype_state(int channel)
{
	return twitch_api_request("https://api.twitch.tv/helix/hypetrain/events?broadcaster_id=" + (string)channel,
			(["Authorization": "Bearer " + token]))
		->then(lambda(mapping info) {
			mapping data = (sizeof(info->data) && info->data[0]->event_data) || ([]);
			return parse_hype_status(data);
		});
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
				"channelid": (string)uid,
				"channelname": channel || "(no channel)",
				"emotes": avail_emotes,
				"backlink": !req->variables->mobile && sprintf("<a href=\"hypetrain?for=%s&mobile\">Switch to mobile view</a>", channel || ""),
			]));
		}, lambda(mixed err) {werror("GOT ERROR\n%O\n", err);}); //TODO: If auth error, clear the token
}

void websocket_msg(mapping(string:mixed) conn, mapping(string:mixed) msg)
{
	if (!msg)
	{
		if (sizeof(websocket_groups[conn->group]) == 1) ; //TODO: Last one - dispose of the webhook (after a short delay?)
		return;
	}
	write("HYPETRAIN: Got a msg %s from client in group %d\n", msg->cmd, conn->group);
	if (msg->cmd == "refresh" || msg->cmd == "init")
	{
		get_hype_state(conn->group)->then(lambda(mapping state) {
			//conn->sock will have definitely been a thing when we were called,
			//but by the time we get the hype state, it might have been dc'd.
			state->cmd = "update";
			if (conn->sock) conn->sock->send_text(Standards.JSON.encode(state));
			//For debugging, trigger a notification for no reason
			//call_out(conn->sock->send_text, 10, Standards.JSON.encode((["cmd": "hit-it"])));
			if (G->G->webhook_active["hypetrain=" + conn->group] < 300)
			{
				write("Creating webhook for hype train %O\n", conn->group);
				create_webhook(
					"hypetrain=" + conn->group,
					"https://api.twitch.tv/helix/hypetrain/events?broadcaster_id=" + conn->group + "&first=1",
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
		});
	}
	if (msg->cmd == "reporterror")
	{
		//The client ran into a problem
		write("GOT HYPE TRAIN ERROR: %O\n", msg);
	}
}

echoable_message process(object channel, object person, string param)
{
	get_user_id(channel->name[1..])->then(lambda(int id) {return get_hype_state(id);})->then(lambda(mapping state) {
		if (state->expires) {
			//Active hype train!
			if (state->total >= state->goal)
				send_message(channel->name, "HypeUnicorn1 HypeUnicorn2 HypeUnicorn3 HypeUnicorn4 HypeUnicorn5 HypeUnicorn6 LEVEL FIVE COMPLETE!");
			else send_message(channel->name, sprintf(
				"/me devicatParty HYPE! Level %d requires %d more bits or %d subs!",
				state->level, state->goal - state->total, (state->goal - state->total + 499) / 500));
		} else if (state->cooldown) {
			int tm = state->cooldown - time();
			send_message(channel->name, sprintf(
				"/me devicatTime The hype train is on cooldown for %02d:%02d. kittenzSleep",
				tm / 60, tm % 60));
		} else send_message(channel->name, "/me NomNom Cookies are done! NomNom");
	});
}

protected void create(string name)
{
	::create(name);
	if (G->G->webhook_endpoints->hypetrain)
		token = function_object(G->G->webhook_endpoints->hypetrain)->token;
	G->G->webhook_endpoints->hypetrain = hypetrain_progression;
}
