inherit command;
constant require_moderator = 1;
constant docstring = #"
Give a shout-out to another streamer

Among Twitch streamers, it's common to say \"that's a great person, you should
definitely check him/her out\". Give shout-outs to people who deserve them!

May be abbreviated to `!so streamername` for convenience (has the same effect).
";

void shoutout(mapping info, string channel)
{
	if (!info) {send_message(channel, "No channel found (do you have the Twitch time machine?)"); return;}
	//TODO: Since Creative is now a tag, how should this word things?
	string game = "playing " + (info->game||"(null)"); if (info->game == "Creative") game = "being creative";
	send_message(channel, sprintf(
		"%s was last seen %s, at %s - go check that stream out, maybe drop a follow! The last thing done was: %s",
		info->display_name, game, info->url, info->status || "(null)"
	));
}

string process(object channel, object person, string param)
{
	param = replace(param, ({"@", " "}), "");
	mapping info = G->G->channel_info[lower_case(param)];
	if (!info)
	{
		write("... fetching channel info to give shout-out to %s...\n", param);
		get_channel_info(lower_case(param), shoutout, channel->name);
	}
	else shoutout(info, channel->name);
}

void create(string name)
{
	::create(name);
	G->G->commands["so"] = check_perms;
}
