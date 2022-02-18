//Special place for anything that can't be done with normal Twitch APIs
//As of 20220216, this is a place for any remaining Kraken calls.

continue Concurrent.Future user_followed_categories(string userid) {
	werror("Warning: Using Kraken API to fetch followed games for %O\n", userid);
	mapping info = yield(twitch_api_request("https://api.twitch.tv/kraken/users/" + userid + "/follows/games"));
	return (array(string))info->follows->game->_id;
}

Concurrent.Future get_video_info(string name) {
	//20210716: Requires Kraken functionality not available in Helix, incl list of resolutions.
	werror("Warning: Using Kraken API to fetch video info for %O\n", name);
	return twitch_api_request("https://api.twitch.tv/kraken/channels/{{USER}}/videos?broadcast_type=archive&limit=1", ([]), (["username": name]))
		->then(lambda(mapping info) {return info->videos[0];});
}

Concurrent.Future get_user_emotes(string name) {
	werror("Warning: Using Kraken API to fetch emotes for %O\n", name);
	return twitch_api_request("https://api.twitch.tv/kraken/users/{{USER}}/emotes",
		0, (["username": name, "authtype": "OAuth"]));
}

protected void create(string name) {
	if (!G->G->external_api_lookups) G->G->external_api_lookups = ([]);
	foreach (indices(this), string f) if (f != "create" && f[0] != '_') G->G->external_api_lookups[f] = this[f];
}
