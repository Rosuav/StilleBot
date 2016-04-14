inherit command;
constant require_allcmds = 1;
constant require_mod = 1;

string process(object channel, object person, string param)
{
	mapping info = G->G->channel_info[lower_case(param)];
	if (!info) return sprintf("Check out %s at https://twitch.tv/%s and maybe drop a follow!", param, lower_case(param));
	string game = "playing " + info->game; if (info->game == "Creative") game = "being creative";
	return sprintf("%s was last seen %s, at %s - go check that stream out, maybe drop a follow! The last thing done was: %s",
		info->display_name, game, info->url, info->status
	);
}
