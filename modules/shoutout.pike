inherit builtin_command;

constant game_desc = ([
	Val.null: "doing something uncategorized",
	"Art": "creating %s",
	"Food & Drink": "creating %s",
	"Just Chatting": "%s",
	"Makers & Crafting": "streaming craft", //Don't really like this description, as it doesn't include the actual category
	"Music & Performing Arts": "creating %s",
	"Software and Game Development": "magicking some %s",
	//Not a fan of the "streaming" cop-out
	"ASMR": "streaming %s",
	"Beauty & Body Art": "creating %s",
	"Talk Shows & Podcasts": "streaming %s",
	"Travel & Outdoors": "streaming %s",
	"Special Events": "streaming %s",
	"Sports & Fitness": "streaming %s",
	//All others come up as "playing %s"
]);

constant builtin_description = "Fetch information about another channel and what it has recently streamed";
constant builtin_name = "Shoutout";
constant builtin_param = "Channel name";
constant vars_provided = ([
	"{url}": "Channel URL, or blank if the user wasn't found",
	"{login}": "Twitch login of the user (usually the same as the parameter but lowercased)",
	"{name}": "Display name of the user",
	"{category}": "Current or last-seen category (game)",
	"{catdesc}": "Category in a human-readable form, eg 'playing X' or 'creating Art'",
	"{title}": "Current or last-seen stream title",
]);
constant command_suggestions = (["!shoutout": ([
	"_description": "Shout out another streamer, providing a link and some info about them (alias !so)",
	"builtin": "shoutout", "builtin_param": ({"%s"}),
	"aliases": "so",
	"access": "mod",
	"message": ([
		"conditional": "string",
		"expr1": "{url}",
		"message": "No channel found (do you have the Twitch time machine?)",
		"otherwise": ({
			"{name} was last seen {catdesc}, at {url} - go check that stream out, maybe drop a follow! The last thing done was: {title}",
			"/shoutout {login}", //Tie in with the twitch_apis handling to do the on-platform shoutout
		}),
	]),
])]);

__async__ mapping message_params(object channel, mapping person, array params)
{
	mapping info = ([]);
	catch {info = await(get_channel_info(replace(params[0], ({"@", " "}), ""))) || ([]);}; //If error, leave it an empty mapping
	return ([
		"{login}": info->broadcaster_login || params[0],
		"{name}": info->broadcaster_name || "That person",
		"{url}": info->url || "",
		"{catdesc}": replace(game_desc[info->game] || "playing %s", "%s", info->game || "(null)"),
		"{category}": info->game || "(null)",
		"{title}": info->title || "(null)",
	]);
}
