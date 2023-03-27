inherit http_endpoint;

/*
Streamer trading cards
DeviCat - Canadian, Cat-Lover, Coffee, Kawaii
JessicaMaiArtist - Canadian, Singer
BeHappyDamnIt - Canadian, Bees
SuspiciousTumble - Canadian, Sewing, Props, JunkTheCat
AuroraLee1013 - Canadian, Cross-Stitch, Lego

* Landing page does not list all cards, but lists categories with a minimum of 5 (tweakable if nec) streamers
* Streamers can have any (reasonable) number of categories, including unusual ones.
* When looking at a collection (canonically: "Canadian"), you see all cards in that category:
  - Rounded-corners rectangle with a background to make it look like a card
  - Top section is the streamer's avatar/PFP
  - Underneath, "Streamer — " + display_name
  - Rarity indicator??
  - Rules box lists categories, one per line
    - Flavor text??
  - Fancy it up with boxes and stuff
  - If logged-in user is not following this streamer, opacity 80%, saturation 0
* Anyone you're not following, offer to link to the channel
* Have a raid finder mode to show who's live from that collection (link to it from the trading cards page)
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
			mapping strm = persist_status->path("tradingcards", "all_streamers")[raw->id] || ([]);
			mapping info = ([
				"id": raw->id,
				"card_name": strm->card_name || raw->display_name,
				"type": strm->type || raw->display_name,
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
			mapping streamers = persist_status->path("tradingcards", "all_streamers");
			streamers[raw->id] = ([
				"card_name": info->card_name || raw->display_name,
				"type": info->type || raw->display_name,
				"link": "https://twitch.tv/" + raw->login,
				"image": raw->profile_image_url,
				"flavor_text": info->flavor_text || raw->description || "",
				"tags": arrayp(info->tags) ? info->tags : ({ }),
			]);
			ensure_collections();
			persist_status->save();
		}
	}
	return render_template(menu_markdown, ([
		"vars": (["collection": 0]),
	]));
}

protected void create(string name)
{
	::create(name);
	G->G->http_endpoints["/tradingcards/%[^/]"] = show_collection;
	ensure_collections();
}
