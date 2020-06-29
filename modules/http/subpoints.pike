inherit http_endpoint;
inherit websocket_handler;
/* Sub point counter
1) API call on load to query sub points
   https://api.twitch.tv/helix/subscriptions
   channel:read:subscriptions
2) Webhook and websocket to notify updates
   https://api.twitch.tv/helix/subscriptions/events
   Same scope needed.
*/

constant tiers = (["1000": 1, "2000": 2, "3000": 6]); //Sub points per tier

Concurrent.Future get_sub_points(mapping cfg, int|void raw)
{
	return get_helix_paginated("https://api.twitch.tv/helix/subscriptions",
			(["broadcaster_id": cfg->uid]),
			(["Authorization": "Bearer " + cfg->token]))
			->then(lambda(array info) {
				if (raw) return info;
				int points = -cfg->unpaidpoints;
				foreach (info, mapping sub)
					if (sub->user_id != sub->broadcaster_id) //Ignore self
						points += tiers[sub->tier];
				return points;
			});
}

void subpoints_updated(string nonce, array|void data)
{
	mapping cfg = persist_status->path("subpoints", nonce);
	get_sub_points(cfg)->then(lambda(int points) {
		write("Pinging %d clients for sub points\n", sizeof(websocket_groups[nonce]));
		(websocket_groups[nonce] - ({0}))->send_text(Standards.JSON.encode(([
			"cmd": "update", "points": points, "goal": cfg->goal,
		])));
	});
}

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	if (string nonce = req->variables->view)
	{
		mapping cfg = persist_status->path("subpoints", nonce);
		if (!cfg->token) return 0; //shouldn't happen if you got your nonce right
		return get_sub_points(cfg)
			->then(lambda(int points) {
				return render_template("subpoints.md", ([
					"nonce": nonce, "viewnonce": nonce,
					"unpaidpoints": "", "goal": "",
					"style": "h1,.cfg {display: none;}",
					"points": sprintf("%d / %d", points, cfg->goal || 1234),
				]));
			});
	}
	if (mapping resp = ensure_login(req, "channel:read:subscriptions")) return resp;
	string nonce = req->variables->nonce ||
		req->misc->session->nonce ||
		replace(MIME.encode_base64(random_string(30)), (["/": "1", "+": "0"]));
	req->misc->session->nonce = nonce;
	mapping cfg = persist_status->path("subpoints", nonce);
	if (req->request_type == "POST")
	{
		write("UPDATING\n");
		cfg->unpaidpoints = (int)req->variables->unpaidpoints;
		cfg->goal = (int)req->variables->goal;
		subpoints_updated(nonce);
	}
	cfg->uid = (string)req->misc->session->user->id;
	cfg->token = req->misc->session->token;
	persist_status->save();
	return get_sub_points(cfg, 1)
		->then(lambda(array info) {
			mapping(string:int) tiercount = ([]);
				foreach (info, mapping sub)
					if (sub->user_id != sub->broadcaster_id) //Ignore self
						tiercount[sub->tier]++;
			array(string) tierlist = ({ });
			int tot, pts;
			foreach (tiercount; string tier; int count)
			{
				tot += count; pts += tiers[tier] * count;
				tierlist += ({sprintf("Tier %c: %d (%d)<br>\n", tier[0], tiers[tier] * count, count)});
			}
			return render_template("subpoints.md", ([
				"nonce": nonce, "viewnonce": "",
				"unpaidpoints": (string)cfg->unpaidpoints,
				"goal": (string)cfg->goal,
				"style": "",
				"points": sort(tierlist) * "" + sprintf("Total: %d subs, %d points", tot, pts),
			]));
		});
}

void websocket_msg(mapping(string:mixed) conn, mapping(string:mixed) msg)
{
	if (!msg) return;
	if (msg->cmd == "refresh" || msg->cmd == "init")
	{
		mapping cfg = persist_status->path("subpoints", conn->group);
		get_sub_points(cfg)->then(lambda(int points) {
			//conn->sock will have definitely been a thing when we were called,
			//but by the time we get the sub points, it might have been dc'd.
			if (conn->sock) conn->sock->send_text(Standards.JSON.encode(([
				"cmd": "update", "points": points, "goal": cfg->goal,
			])));
			if (G->G->webhook_active["subpoints=" + conn->group] < 300)
			{
				write("Creating webhook for sub points %O\n", conn->group);
				create_webhook(
					"subpoints=" + conn->group,
					"https://api.twitch.tv/helix/subscriptions/events?broadcaster_id=" + conn->group + "&first=1",
					1800,
				);
			}
		});
	}
}


protected void create(string name)
{
	::create(name);
	G->G->webhook_endpoints->subpoints = subpoints_updated;
}
