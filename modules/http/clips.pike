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
	mapping cache = clips_cache[broadcaster_id];
	//Uniquify clips - sometimes we get the same one twice even within a query, and when the
	//time range needs to be fractured, we will definitely see many of the same clips again
	cache->clips_by_id |= mkmapping(clips->id, clips);
	clips = values(cache->clips_by_id);
	sort(clips->id, clips); //Sort by slug (id) for complete consistency
	sort(-clips->view_count[*], clips); //Sort by view count to be similar to Twitch's usual view
	cache->clips = clips;
	array gameids = indices(mkmapping(clips->game_id, clips->game_id)); //Distinct game IDs
	array needed = gameids - indices(games_cache);
	if (sizeof(needed)) {
		werror("Need gameids %{%O %}\n", needed);
		//Prevent looping reloads of broken game IDs (probably categories that no longer exist, eg "Creative")
		foreach (needed, string gameid) games_cache[gameid] = (["name": "Game #" + gameid]);
		array games = await(get_helix_paginated("https://api.twitch.tv/helix/games", (["id": gameids])));
		foreach (games, mapping g) games_cache[g->id] = g;
	}
	cache->games = mkmapping(gameids, games_cache[gameids[*]]);
	send_updates_all(broadcaster_id);
	//Once we're done loading, kick all the sockets so they don't suddenly refresh when someone else loads this page
	if (!cache->loading) kick_socket_group(broadcaster_id);
}

void partial_clips(string url, mapping query, mapping options, array clips) {push_clips(query->broadcaster_id, clips);}

//Doubly recursive until the number of clips is low enough to be confident we have them all
__async__ void list_clips_for_range(string broadcaster_id, int starttime, int endtime) {
	if (endtime - starttime < 604800) return; //If you get so many clips that it needs a one-week query, you probably want a more specific tool than this one.
	array clips = await(get_helix_paginated("https://api.twitch.tv/helix/clips", ([
		"broadcaster_id": broadcaster_id,
		"started_at": strftime("%Y-%m-%dT%H:%M:%SZ", gmtime(starttime)),
		"ended_at": strftime("%Y-%m-%dT%H:%M:%SZ", gmtime(endtime)),
	]), ([]), (["partial_results": partial_clips])));
	werror("Got %d clips from %s to %s\n", sizeof(clips), strftime("%Y-%m-%dT%H:%M:%SZ", gmtime(starttime)), strftime("%Y-%m-%dT%H:%M:%SZ", gmtime(endtime)));
	if (sizeof(clips) > 900) {
		//Twitch has a limit of "approximately 1,000" clips returned. In my testing, it usually
		//exceeds this number rather than undersupplying, but to be safe, if you get above 900,
		//assume we might have lost some. Split the time range in half, and query both halves.
		//Note that this is far from efficient, as we cannot know how the distribution of clips
		//will go - we have no information on the timestamps of the clips we don't see - but it
		//is likely that, even in very busy channels, this will fall below the thousand-clip
		//threshold fairly quickly. Unfortunately "fairly quickly" might mean four seconds of
		//loading, followed by two queries of about the same again, etc.
		//We pick a split point simply as the chronological half way mark, then fetch the recent
		//clips before the older ones (since they're more likely to be interesting), with a bit
		//of overlap to try to ensure that we don't lose any clips in the gap.
		int midpoint = (endtime + starttime) / 2;
		await(list_clips_for_range(broadcaster_id, midpoint - 3600, endtime));
		await(list_clips_for_range(broadcaster_id, starttime, midpoint + 3600));
	}
}

__async__ void load_clips(string broadcaster_id) {
	werror("Clips for %O\n", broadcaster_id);
	clips_cache[broadcaster_id] = (["ts": time(), "clips": ({ }), "clips_by_id": ([]), "loading": 1]);
	int starttime = 1451606400; //Clips became a thing in 2016 (about May-ish?), so there won't be any clips before that.
	int endtime = time() + 604800; //Add a week in case of rounding errors or weird offsetting
	System.Timer tm = System.Timer();
	await(list_clips_for_range(broadcaster_id, starttime, endtime));
	clips_cache[broadcaster_id]->loading = 0;
	push_clips(broadcaster_id, ({ }));
	werror("Loaded %d total clips in %.3fs\n", sizeof(clips_cache[broadcaster_id]->clips), tm->peek());
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
mapping get_state(string group) {return clips_cache[group] - (<"clips_by_id">);}
