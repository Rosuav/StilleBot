//Ironically, this file needs to be renamed. But that would be a breaking change, so I won't.
inherit builtin_command;
constant builtin_name = "User info";
constant builtin_description = "Get info about a chatter";
constant builtin_param = "User name to look up or blank for general stats";
constant vars_provided = ([
	"{following}": "Blank if user is not following, otherwise a description of how long",
	"{prevname}": "Most recent previous name, or blank if none seen",
	"{curname}": "Current user name (usually same as the param)",
	"{allnames}": "Space-separated list of all sighted names",
]);
constant command_suggestions = (["!follower": ([
	"_description": "Check whether someone is following the channel",
	"conditional": "catch",
	"message": ([
		"builtin": "renamed", "builtin_param": ({"%s"}),
		"message": ([
			"conditional": "string", "expr1": "{following}", "expr2": "",
			"message": "@{username}: {curname} is not following.",
			"otherwise": "@{username}: {curname} has been following {followage}.",
		]),
	]),
	"otherwise": "@$$: {error}",
]), "!followage": ([
	"_description": "Check how long you've been following the channel",
	"conditional": "catch",
	"message": ([
		"builtin": "renamed", "builtin_param": ({"{username}"}),
		"message": ([
			"conditional": "string", "expr1": "{following}", "expr2": "",
			"message": "@{username}: You're not following.",
			"otherwise": "@{username}: You've been following {followage}.",
		]),
	]),
	"otherwise": "@$$: {error}",
])]);

continue Concurrent.Future|mapping message_params(object channel, mapping person, array param) {
	if (!sizeof(param)) param = ({""});
	string user = param[0] - "@";
	if (user == "") {
		mapping stats = yield((mixed)twitch_api_request("https://api.twitch.tv/helix/channels/followers?broadcaster_id=" + channel->userid));
		return ([
			"{following}": (string)stats->total,
		]);
	}
	int uid; catch {uid = yield(get_user_id(user));};
	if (!uid) error("Can't find that person.\n");
	mapping u2n = G->G->uid_to_name[(string)uid] || ([]);
	array names = indices(u2n);
	sort(values(u2n), names);
	names -= ({"jtv", "tmi"}); //Some junk data in the files implies falsely that some people renamed to "jtv" or "tmi"
	string|zero foll = yield((mixed)check_following(uid, channel->userid)); //FIXME: What if no perms?
	string|zero follage;
	if (foll) {
		follage = "";
		int since = time() - time_from_iso(foll)->unix_time();
		if (since >= 86400) {
			int days = since / 86400; since %= 86400;
			if (days > 365) {follage += (days / 365) + " year(s), "; days %= 365;}
			if (days > 7) {follage += (days / 7) + " week(s), "; days %= 7;}
			if (days) follage += days + " day(s), ";
		}
		follage += sprintf("%02d:%02d:%02d", since / 3600, (since / 60) % 60, since % 60);
	}
	return ([
		"{following}": foll ? "since " + replace(foll, ({"T", "Z"}), "") : "",
		"{followage}": follage ? "for " + follage : "",
		"{prevname}": sizeof(names) >= 2 ? names[-2] : "",
		"{curname}": sizeof(names) ? names[-1] : user,
		"{allnames}": names * " ",
	]);
}
