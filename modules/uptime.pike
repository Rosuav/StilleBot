inherit builtin_command;
constant builtin_description = "See if the channel is online, and if so, for how long";
constant builtin_name = "Channel uptime";
constant command_suggestions = (["!uptime": ([
	"_description": "Show how long the channel has been online",
	"builtin": "uptime",
	"conditional": "string", "expr1": "{uptime}", "expr2": "0",
	"message": "Channel is currently offline.",
	"otherwise": "@$$: Channel {channel} has been online for {uptime|time_english}",
])]);
constant vars_provided = ([
	"{uptime}": "Number of seconds the channel has been online, or 0 if offline",
	"{uptime_english}": "(deprecated) Equivalent to {uptime|time_english}",
	"{uptime_hms}": "(deprecated) Equivalent to {uptime|time_hms}",
	"{channel}": "Channel name (may later become the display name)",
]);

mapping message_params(object channel, mapping person, string param) {
	int t = channel_uptime(channel->name[1..]);
	return ([
		"{channel}": channel->name[1..], //TODO: Show the display name instead
		"{uptime}": (string)t,
		"{uptime_english}": t ? describe_time(t) : "",
		"{uptime_hms}": t ? describe_time_short(t) : "",
	]);
}
