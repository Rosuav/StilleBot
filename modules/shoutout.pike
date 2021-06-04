inherit builtin_command;
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

constant command_description = "Shout out another streamer, providing a link and some info about them (alias !so)";
constant builtin_name = "Shoutout";
constant default_response = ([
	"conditional": "string",
	"expr1": "{url}",
	"message": "No channel found (do you have the Twitch time machine?)",
	"otherwise": "{name} was last seen {catdesc}, at {url} - go check that stream out, maybe drop a follow! The last thing done was: {title}"
]);
constant aliases = ({"so"});
constant vars_provided = ([
	"{url}": "Channel URL, or blank if the user wasn't found",
	"{name}": "Display name of the user",
	"{category}": "Current or last-seen category (game)",
	"{catdesc}": "Category in a human-readable form, eg 'playing X' or 'creating Art'",
	"{title}": "Current or last-seen stream title",
]);

continue mapping|Concurrent.Future message_params(object channel, mapping person, string param)
{
	mapping info = ([]);
	catch {info = yield(get_channel_info(replace(param, ({"@", " "}), "")));}; //If error, leave it an empty mapping
	return ([
		"{name}": info->display_name || "That person",
		"{url}": info->url || "",
		"{catdesc}": replace(game_desc[info->game] || "playing %s", "%s", info->game || "(null)"),
		"{category}": info->game || "(null)",
		"{title}": info->status || "(null)",
	]);
}
