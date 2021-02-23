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
			(["broadcaster_id": cfg->uid, "first": "99"]),
			(["Authorization": "Bearer " + cfg->token]))
			->then(lambda(array info) {
				if (raw) return info;
				int points = -cfg->unpaidpoints;
				foreach (info, mapping sub)
					if (sub->user_id != sub->broadcaster_id) //Ignore self
						points += tiers[sub->tier] || 10000; //Hack: Big noisy thing if the tier is broken
				return points;
			});
}

void subpoints_updated(string nonce, array|void data) {send_updates_all(nonce);}

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	if (string nonce = req->variables->view)
	{
		mapping cfg = persist_status->path("subpoints", nonce);
		if (!cfg->token) return 0; //shouldn't happen if you got your nonce right
		cfg->pinged = time();
		string style = "h1,.cfg {display: none;}main {background-color: inherit;}";
		if (cfg->font && cfg->font != "")
			style = sprintf("@import url(\"https://fonts.googleapis.com/css2?family=%s&display=swap\");"
					"#points {font-family: '%s', sans-serif;}"
					"%s", Protocols.HTTP.uri_encode(cfg->font), cfg->font, style);
		if ((int)cfg->fontsize) style += "#points {font-size: " + (int)cfg->fontsize + "px;}";
		return get_sub_points(cfg)
			->then(lambda(int points) {
				return render_template("subpoints.md", ([
					"vars": (["ws_type": "subpoints", "ws_group": nonce]),
					"nonce": nonce, "viewnonce": nonce, "channelname": cfg->channelname || "",
					"unpaidpoints": "", "goal": "", "usecomfy": "", "font": "", "size": "",
					"comfy": cfg->usecomfy ? "<script src=\"https://cdn.jsdelivr.net/npm/comfy.js/dist/comfy.min.js\"></script>" : "",
					"style": style,
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
	cfg->channelname = req->misc->session->user->login;
	cfg->pinged = time();
	if (req->request_type == "POST")
	{
		write("UPDATING\n");
		cfg->unpaidpoints = (int)req->variables->unpaidpoints;
		cfg->goal = (int)req->variables->goal;
		cfg->usecomfy = !!req->variables->usecomfy;
		cfg->font = req->variables->font;
		cfg->fontsize = req->variables->fontsize;
		send_updates_all(nonce);
	}
	cfg->uid = (string)req->misc->session->user->id;
	cfg->token = req->misc->session->token;
	persist_status->save();
	return get_sub_points(cfg, 1)
		->then(lambda(array info) {
			mapping(string:int) tiercount = ([]), gifts = ([]);
			//Stdio.File("subpoints_" + cfg->channelname, "wct")->write("%O\n", info);
			array(string) tierlist = ({ });
			mapping(string|int:mapping) usersubs = ([]);
			foreach (info, mapping sub)
			{
				if (sub->user_id == sub->broadcaster_id) continue; //Ignore self
				if (usersubs[sub->user_id])
				{
					//Don't know how this would happen, but maybe a pagination failure???
					tierlist += ({sprintf("Duplicate! <pre>%O\n%O\n</pre><br>\n", usersubs[sub->user_id], sub)});
				}
				usersubs[sub->user_id] = sub;
				tiercount[sub->tier]++; if (sub->is_gift) gifts[sub->tier]++;
				if (!tiers[sub->tier]) tierlist += ({sprintf("Unknown sub tier %O<br>\n", sub->tier)});
				//Try to figure out if we get any extra info
				mapping unknowns = sub - (<
					"broadcaster_id", "broadcaster_name", "broadcaster_login",
					"gifter_id", "gifter_name", "gifter_login", "is_gift",
					"plan_name", "tier", "user_id", "user_name", "user_login",
				>);
				if (sizeof(unknowns)) tierlist += ({sprintf("Unknown additional info on %s's sub:%{ %O%}<br>\n", sub->user_name, indices(unknowns))});
			}
			int tot, pts, totgifts, totgiftpts;
			foreach (tiercount; string tier; int count)
			{
				tot += count; pts += tiers[tier] * count;
				totgifts += gifts[tier]; totgiftpts += tiers[tier] * gifts[tier];
				string gift = gifts[tier] ? sprintf(", of which %d (%d) are gifts", tiers[tier] * gifts[tier], gifts[tier]) : "";
				tierlist += ({sprintf("Tier %c: %d (%d)%s<br>\n", tier[0], tiers[tier] * count, count, gift)});
			}
			return render_template("subpoints.md", ([
				"nonce": nonce, "viewnonce": "", "channelname": "",
				"unpaidpoints": (string)cfg->unpaidpoints,
				"goal": (string)cfg->goal,
				"font": cfg->font || "", "size": cfg->fontsize || "16",
				"usecomfy": cfg->usecomfy ? " checked" : "",
				"style": "",
				"comfy": "",
				"points": sort(tierlist) * ""
					+ sprintf("Total: %d subs, %d points", tot, pts)
					+ (totgifts ? sprintf(", of which %d (%d) are gifts", totgiftpts, totgifts) : ""),
			]));
		});
}

mapping|Concurrent.Future get_state(string|int group) {
	mapping cfg = persist_status->path("subpoints", group);
	cfg->pinged = time();
	if (G->G->webhook_active["subpoints=" + group] < 300)
	{
		write("Webhooking sub points %O %O %O\n", group, cfg->uid, cfg->channelname);
		create_webhook(
			"subpoints=" + group,
			"https://api.twitch.tv/helix/subscriptions/events?broadcaster_id=" + cfg->uid + "&first=1",
			1800,
			cfg->token,
		);
	}
	return get_sub_points(cfg)->then(lambda(int points) {return (["points": points, "goal": cfg->goal]);});
}

protected void create(string name)
{
	::create(name);
	G->G->webhook_endpoints->subpoints = subpoints_updated;
}
