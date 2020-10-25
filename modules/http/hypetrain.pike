inherit http_endpoint;
inherit websocket_handler;
/* Hype Train. Game plan.
1) [DONE] Do everything client-side with a single coherent JSON status object. Continue to tick unmanaged.
2) [DONE] Have a button to request a new JSON status object from the server.
3) [DONE] Have a websocket and send JSON status periodically or when the time expires.
   - No initial state. Just establish the websocket and have THAT provide the state. Faster IPL than doing it twice.
4) [DONE] Manage the web hook
5) Add optional audio to start and/or end
6) Have a landing page for configs. Use local storage??
7) [DONE] Show the emotes you could get at this and the next level
*/

/*

{"goal":2500,"cooldown":1603457704,"cmd":"update","total":1501,"conductors":[{"type":"BITS","display_name":"Overstarched","user":"170557232","total":400},{"type":"SUBS","display_name":"stephenangelico","user":"121823116","total":2500}],"lastcontrib":{"type":"BITS","display_name":"Overstarched","user":"170557232","total":100},"expires":1603454104,"level":2}


Person_in_the_MIRROR: Hey there. Checked out the Express Train version on my phone. It's definitely nice & clear to see. I wonder, if it wouldn't be too difficult, whether you could add the option of tapping somewhere & typing the channel name to switch it to another channel since URLs are often hard to access & input on phones.
Person_in_the_MIRROR: Could it be something like a space under the block where one could input the new channel name & program would redirect the person to url site with the channel that was input?

*/

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

constant emotes = #"HypeChimp HypeGhost HypeChest HypeFrog HypeCherry HypePeace
HypeSideeye HypeBrain HypeZap HypeShip HypeSign HypeBug
HypeYikes HypeRacer HypeCar HypeFirst HypeTrophy HypeBanana
HypeBlock HypeDaze HypeBounce HypeJewel HypeBlob HypeTeamwork
HypeLove HypePunk HypeKO HypePunch HypeFire HypePizza";

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	string channel = req->variables["for"];
	if (!token)
	{
		if (mapping resp = ensure_login(req, "channel:read:hype_train")) return resp;
		//Weirdly, this seems to work even if the broadcaster_id isn't the one you logged
		//in as, but you need to have the appropriate scope. So once we see a token that
		//works, save it, until it doesn't. (TODO: actually discard that token once it's
		//no longer valid.)
		token = req->misc->session->token;
	}
	mapping emotemd = G->G->emote_code_to_markdown || ([]);
	string avail_emotes = "";
	foreach (emotes / "\n", string level)
	{
		avail_emotes += "\n*";
		foreach (level / " ", string emote)
		{
			string md = emotemd[emote];
			if (!md) {avail_emotes += " " + emote; continue;}
			avail_emotes += sprintf(" %s*%s*", emotemd[emote], replace(emotemd[emote], "/1.0", "/3.0"));
		}
	}
	return (channel ? get_user_id(channel) : Concurrent.resolve(0))
		->then(lambda(int uid) {
			return render_template(req->variables->mobile ? "hypetrain_mobile.html" : "hypetrain.md", ([
				"channelid": (string)uid,
				"channelname": channel || "<no channel>",
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
			}
		});
	}
	if (msg->cmd == "reporterror")
	{
		//The client ran into a problem
		write("GOT HYPE TRAIN ERROR: %O\n", msg);
	}
}

protected void create(string name)
{
	::create(name);
	G->G->webhook_endpoints->hypetrain = hypetrain_progression;
}
