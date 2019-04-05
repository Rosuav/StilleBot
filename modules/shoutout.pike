inherit command;
constant require_moderator = 1;
constant docstring = #"
Give a shout-out to another streamer

Among Twitch streamers, it's common to say \"that's a great person, you should
definitely check him/her out\". Give shout-outs to people who deserve them!

May be abbreviated to `!so streamername` for convenience (has the same effect).
";

constant game_desc = ([
	"Art": "creating %s",
	"Food & Drink": "creating %s",
	"Just Chatting": "%s",
	"Makers & Crafting": "being crafty", //Really don't like this description :|
	"Music & Performing Arts": "creating %s",
	"Science & Technology": "creating %s",
	//All others come up as "playing %s"
	//TODO: Handle the IRL-tagged categories better.
	//"ASMR"
	//"Beauty & Body Art"
	//"Talk Shows & Podcasts"
	//"Travel & Outdoors"
	//"Special Events"
	//"Sports & Fitness"
]);

void shoutout(mapping info, string channel)
{
	if (!info) {send_message(channel, "No channel found (do you have the Twitch time machine?)"); return;}
	string game = replace(game_desc[info->game] || "playing %s", "%s", info->game);
	//TODO: Differentiate between "is now" and "was last seen"
	//If the channel is currently hosting, override with "was last seen".
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
