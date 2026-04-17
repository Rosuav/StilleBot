inherit http_endpoint;

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

void partial_clips(string url, mapping query, mapping options, array data) {
	werror("Clips for %O, got %O so far...\n", query->broadcaster_id, sizeof(data));
}

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	string chan = req->variables["for"];
	if (!chan) return render_template(menu, ([]));
	werror("Clips for %O\n", chan);
	mapping info = await(get_user_info(chan, "login"));
	array clips = await(get_helix_paginated("https://api.twitch.tv/helix/clips", (["broadcaster_id": (string)info->id]), ([]), (["partial_results": partial_clips])));
	array gameids = indices(mkmapping(clips->game_id, clips->game_id)); //Distinct game IDs
	array games = await(get_helix_paginated("https://api.twitch.tv/helix/games", (["id": gameids])));
	werror("Done, got %O clips\n", sizeof(clips));
	return render_template(markdown, ([
		"vars": (["clips": clips, "games": mkmapping(games->id, games)]),
		"chan": info->display_name,
		"css": "tiledstreams.css",
		"js": "clips.js", //No websocket, just get the JS directly
	]));
}
