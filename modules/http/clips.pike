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

__async__ void partial_clips(string url, mapping query, mapping options, array clips) {
	werror("Clips for %O, got %O so far...\n", query->broadcaster_id, sizeof(clips));
	clips_cache[query->broadcaster_id]->clips = clips;
	array gameids = indices(mkmapping(clips->game_id, clips->game_id)); //Distinct game IDs
	array needed = gameids - indices(games_cache);
	werror("Need gameids %{%O %}\n", needed);
	if (sizeof(needed)) {
		array games = await(get_helix_paginated("https://api.twitch.tv/helix/games", (["id": gameids])));
		foreach (games, mapping g) games_cache[g->id] = g;
	}
	clips_cache[query->broadcaster_id]->games = mkmapping(gameids, games_cache[gameids[*]]);
	send_updates_all(query->broadcaster_id);
}

__async__ void load_clips(string broadcaster_id) {
	werror("Clips for %O\n", broadcaster_id);
	clips_cache[broadcaster_id] = (["ts": time(), "clips": ({ }), "loading": 1]);
	array clips = await(get_helix_paginated("https://api.twitch.tv/helix/clips", (["broadcaster_id": broadcaster_id]), ([]), (["partial_results": partial_clips])));
	clips_cache[broadcaster_id]->loading = 0;
	send_updates_all(broadcaster_id, (["loading": 0]));
	//Kick all the sockets so they don't suddenly refresh when someone else loads this page
	kick_socket_group(broadcaster_id);
	werror("Done, got %O clips\n", sizeof(clips));
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
