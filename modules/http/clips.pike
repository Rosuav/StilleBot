inherit http_websocket;

constant menu = #"# Twitch clips browser

<form method=get>
<label>Select channel: <input name=for></label>
<input type=submit value=Go>
</form>
";

constant markdown = #"# Twitch clips for $$chan$$

<div id=display></div>

<style>
fieldset {display: inline;}
</style>
";

//Map a broadcaster_id to (["ts": time(), "clips": ({...})])
@retain: mapping(string:mapping(string:mixed)) clips_cache = ([]);
mapping(string:mapping) games_cache = (["0": (["name": "Unknown"]), "": (["name": "Uncategorized"])]); //Not retained; just reduces query spam during loading

__async__ void push_clips(string broadcaster_id, array clips) {
	werror("Clips for %O, got %O so far...\n", broadcaster_id, sizeof(clips));
	clips = values(mkmapping(clips->id, clips)); //Uniquify clips - sometimes we get the same one twice
	sort(clips->id, clips); //Sort by slug (id) for complete consistency
	sort(-clips->view_count[*], clips); //Sort by view count to be similar to Twitch's usual view
	clips_cache[broadcaster_id]->clips = clips;
	array gameids = indices(mkmapping(clips->game_id, clips->game_id)); //Distinct game IDs
	array needed = gameids - indices(games_cache);
	werror("Need gameids %{%O %}\n", needed);
	if (sizeof(needed)) {
		array games = await(get_helix_paginated("https://api.twitch.tv/helix/games", (["id": gameids])));
		foreach (games, mapping g) games_cache[g->id] = g;
	}
	clips_cache[broadcaster_id]->games = mkmapping(gameids, games_cache[gameids[*]]);
	send_updates_all(broadcaster_id);
	//Once we're done loading, kick all the sockets so they don't suddenly refresh when someone else loads this page
	if (!clips_cache[broadcaster_id]->loading) kick_socket_group(broadcaster_id);
}

void partial_clips(string url, mapping query, mapping options, array clips) {push_clips(query->broadcaster_id, clips);}

__async__ void load_clips(string broadcaster_id) {
	werror("Clips for %O\n", broadcaster_id);
	clips_cache[broadcaster_id] = (["ts": time(), "clips": ({ }), "loading": 1]);
	//NOTE: Clips became a thing in 2016 (about May-ish?), so there won't be any clips before that.
	array clips = await(get_helix_paginated("https://api.twitch.tv/helix/clips",
		(["broadcaster_id": broadcaster_id, /*"started_at": "2016-01-01T00:00:00Z", "ended_at": "2020-01-01T00:00:00Z"*/]),
		([]), (["partial_results": partial_clips])));
	clips_cache[broadcaster_id]->loading = 0;
	//Note that push_clips will be called by partial_clips too, which may result in two
	//concurrent queries loading games. Shouldn't be too much load, and frankly, I can't
	//be bothered trying to get the perfect optimization here.
	push_clips(broadcaster_id, clips);
}

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	string chan = req->variables["for"];
	if (!chan) return render_template(menu, ([]));
	mapping info = await(get_user_info(chan, "login"));
	if (is_active_bot()) load_clips((string)info->id); //Start loading the clips if we're the active bot, to avoid waiting
	return render(req, ([
		"vars": (["ws_group": (string)info->id]),
		"chan": info->display_name,
		"css": "tiledstreams.css",
	]));
}

string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!(int)msg->group) return "Bad ID";
	if (!clips_cache[msg->group]->?loading) load_clips(msg->group);
}
mapping get_state(string group) {return clips_cache[group];}
