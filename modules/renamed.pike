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
			"conditional": "string", "expr1": "{following}",
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
			"conditional": "string", "expr1": "{following}",
			"message": "@{username}: You're not following.",
			"otherwise": "@{username}: You've been following {followage}.",
		]),
	]),
	"otherwise": "@$$: {error}",
])]);

__async__ mapping message_params(object channel, mapping person, array param) {
	if (!sizeof(param)) param = ({""});
	string user = param[0] - "@";
	if (user == "") {
		mapping stats = await(twitch_api_request("https://api.twitch.tv/helix/channels/followers?broadcaster_id=" + channel->userid));
		return ([
			"{following}": (string)stats->total,
		]);
	}
	int uid; catch {uid = await(get_user_id(user));};
	if (!uid) error("Can't find that person.\n");
	array names = await(G->G->DB->query_ro("select login from stillebot.user_login_sightings where twitchid = :id order by sighted",
		(["id": uid])))->login;
	string|zero foll = await(check_following(uid, channel->userid)); //FIXME: What if no perms?
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

//Command-line interface
__async__ void lookup(array(string) names) {
	int show_times = has_value(names, "--times"); names -= ({"--times"});
	foreach (names, string name) {
		int uid = await(get_user_id(name));
		if (!uid) {write(name + ": Not found\n"); continue;}
		array times = await(G->G->DB->query_ro("select login, sighted from stillebot.user_login_sightings where twitchid = :id order by sighted",
			(["id": uid])));
		if (show_times) foreach (times, mapping t) write("[%s] %s\n", t->sighted, t->login);
		else write(name + ": " + times->login * ", " + "\n");
	}
}
