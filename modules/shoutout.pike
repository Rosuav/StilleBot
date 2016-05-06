inherit command;
constant require_allcmds = 1;
constant require_moderator = 1;

void shoutout(mapping info, string channel)
{
	string game = "playing " + (info->game||"(null)"); if (info->game == "Creative") game = "being creative";
	send_message(channel, sprintf("%s was last seen %s, at %s - go check that stream out, maybe drop a follow! The last thing done was: %s",
		info->display_name, game, info->url, info->status || "(null)"
	));
}

string process(object channel, object person, string param)
{
	mapping info = G->G->channel_info[lower_case(param)];
	if (!info)
	{
		write("... fetching channel info to give shout-out to %s...\n", param);
		get_channel_info(lower_case(param), shoutout, channel->name);
	}
	else shoutout(info, channel->name);
}
