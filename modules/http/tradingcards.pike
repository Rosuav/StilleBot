inherit http_endpoint;

/*
* When looking at a collection (canonically: "Canadian"), you see all cards in that category:
  - Rarity indicator based on the streamer's total follower count?
    - Use whichever streamer has the highest follower count in this category as the definition???
    - Otherwise, have some kind of thresholds that define rarity, but that means picking numbers.

Make a collection of Australians

Mirror: could there also be something special (like a hologram edition) if you are subscribed to the Streamer (or would that be too difficult)?
*/
constant add_markdown = #"# Streamer Trading Cards

Add a streamer: <form id=pickstrm><input name=streamer> <button>Add/edit</button></form>

<div id=build_a_card></div>
<button type=button id=save hidden>Save</button>
";

constant menu_markdown = #"# Streamer Trading Cards

How's your collection looking?

$$collections$$
";

constant markdown = #"# Streamer Trading Cards

## $$label$$

$$desc$$

$$login_link$$

<div id=card_collection></div>

[Who's live right now?](/raidfinder?categories=$$coll_id$$)
";

continue mapping(string:mixed)|Concurrent.Future show_collection(Protocols.HTTP.Server.Request req, string collection)
{
	collection = lower_case(collection);
	if (collection == "add" && req->misc->session->user->?id == (string)G->G->bot_uid) {
		return render_template(add_markdown, ([
			"vars": (["collection": 0]),
			"js": "tradingcards", "css": "tradingcards",
		]));
	}
	mapping coll = persist_status->path("tradingcards", "collections")[collection];
	if (!coll) return redirect("/tradingcards");
	//TODO: Allow the owner to edit the collection metadata
	array streamers = map(coll->streamers, persist_status->path("tradingcards", "all_streamers"));
	string login_link = "";
	if (req->misc->session->scopes[?"user:read:follows"]) foreach (coll->streamers; int i; string bcaster) {
		//As far as I know, there's no way to check follows in bulk. So to reduce the cost,
		//we cache them. Duplicated into chan_raidtrain.pike.
		mapping foll = G_G_("following", bcaster, req->misc->session->user->id);
		if (foll->stale < time(1)) {
			mapping info = yield(twitch_api_request(sprintf(
				"https://api.twitch.tv/helix/channels/followed?user_id=%s&broadcaster_id=%s",
				req->misc->session->user->id, bcaster),
				(["Authorization": "Bearer " + req->misc->session->token])));
			if (sizeof(info->data)) foll->followed_at = info->data[0]->followed_at;
			else foll->followed_at = 0;
			//Cache positive entries for a day, negative for a few minutes.
			foll->stale = time(1) + (foll->followed_at ? 86400 : 180);
		}
		//Record the following status as either a timestamp or "!" for not following.
		//This leaves undefined/absent as "unknown" (eg if not logged in).
		//Don't mutate the streamer info as that's straight from persist
		streamers[i] = streamers[i] | (["following": foll->followed_at || "!"]);
		if (bcaster == req->misc->session->user->id) streamers[i]->following = "forever";
	}
	else login_link = "[Check your collection!](:.twitchlogin data-scopes=user:read:follows)";
	return render_template(markdown, ([
		"coll_id": collection,
		"label": coll->label, "desc": coll->desc,
		"login_link": login_link,
		"vars": (["collection": streamers]),
		"js": "tradingcards", "css": "tradingcards",
	]));
}

void ensure_collections() {
	mapping streamers = persist_status->path("tradingcards", "all_streamers");
	mapping collections = persist_status->path("tradingcards", "collections");
	mapping tagcount = ([]), tagcase = ([]);
	foreach (streamers; string id; mapping s)
		foreach (s->tags || ({ }), string t) {
			tagcount[lower_case(t)] += ({id});
			tagcase[lower_case(t)] = t;
		}
	//For every tag with at least 5 streamers, define a collection.
	foreach (tagcount; string t; array strm) {
		if (sizeof(strm) < 5) continue;
		if (!collections[t]) collections[t] = ([
			"label": tagcase[t],
			"desc": "",
			"owner": G->G->bot_uid,
		]);
		sort((array(int))strm, strm);
		if ((collections[t]->streamers || ({ })) * "," != strm * ",") {
			collections[t]->streamers = strm;
			persist_status->save();
		}
	}
}

continue mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	if (req->variables->collection) return show_collection(req, req->variables->collection);
	//Editing functionality requires that you be logged in as the bot.
	if (req->misc->session->user->?id == (string)G->G->bot_uid) {
		if (string username = req->variables->query) {
			username -= "https://twitch.tv/"; //Allow the full URL to be entered if desired
			mapping raw = yield(get_user_info(username, "login"));
			array col = yield(twitch_api_request("https://api.twitch.tv/helix/chat/color?user_id=" + raw->id))->data->color;
			if (!sizeof(col)) col = ({"#000000"});
			mapping strm = persist_status->path("tradingcards", "all_streamers")[raw->id] || ([]);
			mapping info = ([
				"id": raw->id,
				"card_name": strm->card_name || raw->display_name,
				"type": strm->type || raw->display_name,
				"color": col[0],
				"link": "https://twitch.tv/" + raw->login,
				"image": raw->profile_image_url,
				"flavor_text": strm->flavor_text || raw->description || "",
				"tags": strm->tags || ({ }),
			]);
			return jsonify((["details": info, "raw": raw]));
		}
		if (req->variables->save && req->request_type == "PUT") {
			mixed body = Standards.JSON.decode_utf8(req->body_raw);
			if (!body || !mappingp(body) || !mappingp(body->info)) return (["error": 400]);
			mapping info = body->info;
			mapping raw = yield(get_user_info(info->id));
			array col = yield(twitch_api_request("https://api.twitch.tv/helix/chat/color?user_id=" + raw->id))->data->color;
			if (!sizeof(col)) col = ({"#000000"});
			mapping streamers = persist_status->path("tradingcards", "all_streamers");
			streamers[raw->id] = ([
				"card_name": info->card_name || raw->display_name,
				"type": info->type || raw->display_name,
				"color": col[0],
				"link": "https://twitch.tv/" + raw->login,
				"image": raw->profile_image_url,
				"flavor_text": info->flavor_text || raw->description || "",
				"tags": arrayp(info->tags) ? info->tags : ({ }),
			]);
			ensure_collections();
			persist_status->save();
		}
	}
	array coll = ({ }), order = ({ });
	foreach ((array)persist_status->path("tradingcards", "collections"), [string id, mapping info]) {
		coll += ({sprintf("* [%s (%d)](/tradingcards/%s)", info->label, sizeof(info->streamers), id)});
		order += ({info->label}); //Or should they be sorted by streamer count?
	}
	sort(order, coll);
	return render_template(menu_markdown, ([
		"vars": (["collection": 0]),
		"collections": coll * "\n",
	]));
}

protected void create(string name)
{
	::create(name);
	G->G->http_endpoints["/tradingcards/%[^/]"] = show_collection;
	ensure_collections();
}
