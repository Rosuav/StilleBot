inherit http_endpoint;
inherit websocket_handler;
/* Hype train status
  - Requires channel:read:hypetrain and possibly user:read:broadcast - test the error messages
  - Show the status of any current hype train. If there is none, show a big ticking countdown.
  - Show stats for the most recent hype train(s)?
  - MAYBE set up a webhook for live updates if (and only if) this page is open, and websocket it?
*/

//Determine how long until the specified time. If ts is null, malformed,
//or in the past, returns 0.
int until(string ts, int now)
{
	object tm = Calendar.ISO.parse("%Y-%M-%DT%h:%m:%s%z", ts || "");
	return tm && max(tm->unix_time() - now, 0);
}
mapping cached = 0; int cache_time = 0;
string token;

Concurrent.Future get_hype_state(int channel)
{
	return twitch_api_request("https://api.twitch.tv/helix/hypetrain/events?broadcaster_id=" + (string)channel,
			(["Authorization": "Bearer " + token]))
		->then(lambda(mapping info) {
			mapping data = (sizeof(info->data) && info->data[0]->event_data) || ([]);
			int now = time();
			int cooldown = until(data->cooldown_end_time, now);
			int expires = until(data->expires_at, now);
			//TODO: Show hype conductor stats
			return ([
				"cooldown": cooldown, "expires": expires,
				"level": (int)data->level, "goal": (int)data->goal, "total": (int)data->total,
			]);
		});
}

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	string channel = req->variables["for"];
	if (!channel) return render_template("hypetrain.md", (["state": "{}"]));
	if (!token)
	{
		if (mapping resp = ensure_login(req, "channel:read:hype_train")) return resp;
		//Weirdly, this seems to work even if the broadcaster_id isn't the one you logged
		//in as, but you need to have the appropriate scope. So once we see a token that
		//works, save it, until it doesn't. (TODO: actually discard that token once it's
		//no longer valid.)
		token = req->misc->session->token;
	}
	return get_user_id(channel)
		->then(lambda(int uid) {
			return render_template("hypetrain.md", (["channel": Standards.JSON.encode(channel), "channelid": (string)uid]));
		}, lambda(mixed err) {werror("GOT ERROR\n%O\n", err);}); //TODO: If auth error, clear the token
}

void websocket_msg(mapping(string:mixed) conn, mapping(string:mixed) msg)
{
	if (!msg)
	{
		if (sizeof(websocket_groups[conn->group]) == 1) ; //TODO: Last one - dispose of the webhook (after a short delay?)
		return;
	}
	if (sizeof(websocket_groups[conn->group]) == 1) ; //TODO: First one - establish a webhook
	write("HYPETRAIN: Got a msg %s from client in group %s\n", msg->cmd, conn->group);
	if (msg->cmd == "refresh" || msg->cmd == "init")
	{
		get_hype_state((int)conn->group)->then(lambda(mapping state) {
			//conn->sock will have definitely been a thing when we were called,
			//but by the time we get the hype state, it might have been dc'd.
			state->cmd = "update";
			if (conn->sock) conn->sock->send_text(Standards.JSON.encode(state));
		});
	}
}
/*
Hype train data: [1592560805] ([
  "broadcaster_id": "96065689",
  "cooldown_end_time": "2020-06-19T11:59:58Z",
  "expires_at": "2020-06-19T09:59:58Z",
  "goal": 1600,
  "id": "86cda003-7be9-44b9-ac9e-1d7df2d148f5",
  "last_contribution": ([
      "total": 300,
      "type": "BITS",
      "user": "139300055"
    ]),
  "level": 1,
  "started_at": "2020-06-19T09:54:58Z",
  "top_contributions": ({
        ([
          "total": 300,
          "type": "BITS",
          "user": "139300055"
        ]),
        ([
          "total": 500,
          "type": "SUBS",
          "user": "139300055"
        ])
    }),
  "total": 1100
])
*/
protected void create(string name) {::create(name);}
