//Special place for anything that can't be done with normal Twitch APIs
//As of 20220216, this is a place for any remaining Kraken calls.

continue Concurrent.Future user_followed_categories(string userid) {
	werror("Warning: Using Kraken API to fetch followed games for %O\n", userid);
	mapping info = yield(twitch_api_request("https://api.twitch.tv/kraken/users/" + userid + "/follows/games"));
	return (array(string))info->follows->game->_id;
}

void create(string name) {
	if (!G->G->external_api_lookups) G->G->external_api_lookups = ([]);
	foreach (indices(this), string f) if (f != "create" && f[0] != '_') G->G->external_api_lookups[f] = this[f];
}
