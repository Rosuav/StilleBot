inherit http_endpoint;

/*
* When looking at a collection (canonically: "Canadian"), you see all cards in that category:
  - Rarity indicator based on the streamer's total follower count?
    - Use whichever streamer has the highest follower count in this category as the definition???
    - Otherwise, have some kind of thresholds that define rarity, but that means picking numbers.
  - If logged-in user is not following this streamer, opacity 80%, saturation 0
* Have a raid finder mode to show who's live from that collection (link to it from the trading cards page)

Make a collection of Australians

Mirror: could there also be something special (like a hologram edition) if you are subscribed to the Streamer (or would that be too difficult)?
*/

/* TODO: Add to the generic markdown renderer, just like for vars, an array/string of scripts and styles
Then add those to the <head> where they belong, not stuck down in the body.
*/
constant add_markdown = #"# Streamer Trading Cards

Add a streamer: <form id=pickstrm><input name=streamer> <button>Add/edit</button></form>

<div id=build_a_card></div>
<button type=button id=save hidden>Save</button>

<script type=module src=\"$$static||tradingcards.js$$\"></script>
<link rel=\"stylesheet\" href=\"$$static||tradingcards.css$$\">
";

constant menu_markdown = #"# Streamer Trading Cards

How's your collection looking?

$$collections$$
";

constant markdown = #"# Streamer Trading Cards

## $$label$$

$$desc$$

<div id=card_collection></div>

<script type=module src=\"$$static||tradingcards.js$$\"></script>
<link rel=\"stylesheet\" href=\"$$static||tradingcards.css$$\">
";

mapping(string:mixed)|Concurrent.Future show_collection(Protocols.HTTP.Server.Request req, string collection)
{
	collection = lower_case(collection);
	if (collection == "add" && req->misc->session->user->?id == (string)G->G->bot_uid) {
		return render_template(add_markdown, ([
			"vars": (["collection": 0]),
		]));
	}
	mapping coll = persist_status->path("tradingcards", "collections")[collection];
	if (!coll) return redirect("/tradingcards");
	//TODO: Allow the owner to edit the collection metadata
	return render_template(markdown, ([
		"label": coll->label,
		"desc": coll->desc,
		"vars": (["collection": map(coll->streamers, persist_status->path("tradingcards", "all_streamers"))]),
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
