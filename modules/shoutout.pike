inherit command;
constant require_moderator = 1;
constant docstring = #"
Give a shout-out to another streamer

Among Twitch streamers, it's common to say \"that's a great person, you should
definitely check him/her out\". Give shout-outs to people who deserve them!

May be abbreviated to `!so streamername` for convenience (has the same effect).
";

constant game_desc = ([
	Val.null: "doing something uncategorized",
	"Art": "creating %s",
	"Food & Drink": "creating %s",
	"Just Chatting": "%s",
	"Makers & Crafting": "streaming craft", //Don't really like this description, as it doesn't include the actual category
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
	string game = replace(game_desc[info->game] || "playing %s", "%s", info->game || "(null)");
	string chron = "was last seen";
	//Note that the Kraken info - which is what we get if the channel isn't polled -
	//doesn't include info about whether the stream is live. That would require a
	//second API call, which would increase the shoutout latency, all for the sake
	//of saying "is now playing" instead of "was last seen playing".
	//If we can get last-known Helix info on call, that will be WAY better.
	if (info->online_type == "live") chron = "is now";
	//TODO: If the channel is currently hosting, override with "was last seen".
	//Is there any way, in either Helix or Kraken, to get that info? For the GUI,
	//we get the info via IRC. Ah, what fun - getting info from IRC, Kraken, Helix,
	//push notifications (which are heavily derived from Helix), and maybe one day
	//the websocket pubsub...
	else if (info->online_type) write("Shouting out channel %s which is online_type %O\n", channel, info->online_type);
	send_message(channel, sprintf(
		"%s %s %s, at %s - go check that stream out, maybe drop a follow! The last thing done was: %s",
		info->display_name, chron, game, info->url, info->status || "(null)"
	));
}

string process(object channel, object person, string param)
{
	param = replace(param, ({"@", " "}), "");
	//Hack: Always fetch the live info
	mapping info = 0;//G->G->channel_info[lower_case(param)];
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
