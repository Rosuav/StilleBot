inherit http_endpoint;

/*
Streamer trading cards
DeviCat - Canadian, Cat-Lover, Coffee, Kawaii
JessicaMaiArtist - Canadian
BeHappyDamnIt - Canadian
SuspiciousTumble - Canadian
AuroraLee1013 - Canadian

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

<script type=module src=\"$$static||tradingcards.js$$\"></script>
<link rel=\"stylesheet\" href=\"$$static||tradingcards.css$$\">
";

constant menu_markdown = #"# Streamer Trading Cards

How's your collection looking?
";

constant markdown = #"# Streamer Trading Cards

This would be one collection.
";

mapping(string:mixed)|Concurrent.Future show_collection(Protocols.HTTP.Server.Request req, string collection)
{
	if (collection == "add" && req->misc->session->user->?id == (string)G->G->bot_uid) {
		return render_template(add_markdown, ([]));
	}
	mapping coll = persist_status->path("tradingcards", "collections")[collection];
	if (!coll) return redirect("/tradingcards");
	//TODO: Allow admins to edit the collection metadata
	return render_template(markdown, ([]));
}

continue mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	if (req->variables->collection) return show_collection(req, req->variables->collection);
	//Editing functionality requires that you be logged in as the bot.
	if (req->misc->session->user->?id == (string)G->G->bot_uid) {
		if (string username = req->variables->query) {
			username -= "https://twitch.tv/"; //Allow the full URL to be entered if desired
			mapping raw = yield(get_user_info(username, "login"));
			mapping info = ([ //TODO: Add exactly this to the all_streamers collection if added
				"id": raw->id,
				"card_name": raw->display_name,
				"type": raw->display_name,
				"link": "https://twitch.tv/" + raw->login,
				"image": raw->profile_image_url,
				"flavor_text": raw->description || "",
				"tags": ({ }),
			]);
			return jsonify((["details": info, "raw": raw]));
		}
	}
	return render_template(menu_markdown, ([]));
}

protected void create(string name)
{
	::create(name);
	G->G->http_endpoints["/tradingcards/%[^/]"] = show_collection;
	array streamers = persist_status->path("tradingcards")->all_streamers;
	if (!streamers) streamers = persist_status->path("tradingcards")->all_streamers = ({ });
	mapping collections = persist_status->path("tradingcards", "collections");
	mapping tagcount = ([]);
	foreach (streamers, mapping s)
		foreach (s->tags || ({ }), string t)
			tagcount[t] += ({s->id});
	//For every tag with at least 5 streamers, define a collection.
	foreach (tagcount; string t; array strm) {
		if (sizeof(strm) < 5) continue;
		if (!collections[t]) collections[t] = ([
			"label": t, //Can be case-changed
			"desc": "",
			"owner": G->G->bot_uid,
		]);
		collections[t]->streamers = strm;
	}
	persist_status->save();
}
