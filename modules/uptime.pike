inherit builtin_command;
constant docstring = #"
Show channel uptime.

It's possible that this information will be a little delayed, showing
that the channel is offline if it's just started, and/or still showing
the uptime just after it goes offline.
";

constant command_description = "Show how long the channel has been online";
constant builtin_description = "Get the channel uptime";
constant builtin_name = "Uptime";
constant default_response = ([
	"conditional": "string", "expr1": "{uptime}", "expr2": "0",
	"message": "Channel is currently offline.",
	"otherwise": "@$$: Channel {channel} has been online for {uptime_english}",
]);
constant vars_provided = ([
	"{uptime}": "Number of seconds the channel has been online, or 0 if offline",
	"{uptime_english}": "Time the channel has been online in English words",
	"{uptime_hms}": "Time the channel has been online in hh:mm:ss format",
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
