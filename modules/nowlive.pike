inherit builtin_command;
constant featurename = "info";
constant require_moderator = 1;
constant docstring = #"
Check if a stream is currently live

This takes a moment, but should be reliable, unlike waiting for notifications
(which can be delayed by even a few minutes).
";

constant command_description = "Check if a stream is live";
constant builtin_description = "Query a stream to see if it is live";
constant builtin_name = "Now-Live";
constant builtin_param = "Channel name";
constant default_response = ([
	"conditional": "string",
	"expr1": "{channellive}",
	"expr2": "notfound",
	"message": "Channel not found - can't be live!",
	"otherwise": ([
		"conditional": "string",
		"expr1": "{channellive}",
		"expr2": "offline",
		"message": "Channel is offline.",
		"otherwise": "Channel is currently online, uptime {channellive}",
	]),
]);
constant vars_provided = ([
	"{channellive}": "Either 'offline' or a human-readable-ish time",
]);

continue mapping|Concurrent.Future message_params(object channel, mapping person, string param)
{
	string live = "notfound";
	catch {live = yield(channel_still_broadcasting(replace(param, ({"@", " "}), "")));};
	return (["{channellive}": live]);
}
