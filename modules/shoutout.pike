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

constant default_response = ([
	"conditional": "string",
	"expr1": "{url}",
	"message": "No channel found (do you have the Twitch time machine?)",
	"otherwise": "{name} was last seen {catdesc}, at {url} - go check that stream out, maybe drop a follow! The last thing done was: {title}"
]);

continue Concurrent.Future _shoutout(object channel, mapping person, string param)
{
	mapping info = ([]);
	catch {info = yield(get_channel_info(replace(param, ({"@", " "}), "")));}; //If error, leave it an empty mapping
	channel->send(person, m_delete(person, "outputfmt") || default_response, ([
		"{name}": info->display_name || "That person",
		"{url}": info->url || "",
		"{catdesc}": replace(game_desc[info->game] || "playing %s", "%s", info->game || "(null)"),
		"{category}": info->game || "(null)",
		"{title}": info->status,
	]));
}

string process(object channel, mapping person, string param) {handle_async(_shoutout(channel, person, param)) { };}

protected void create(string name)
{
	::create(name);
	G->G->commands["so"] = check_perms;
}
