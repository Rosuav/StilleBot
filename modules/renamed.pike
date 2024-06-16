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
	if (has_value(user, ',')) {
		//If you provide a comma-separated list of IDs or logins, retrieve basic information
		//about all of them.
		//NOTE: Is assumed to be either all IDs or all logins. All-numeric logins are, as always,
		//a bit of a pain. To force them to be interpreted as logins, stick ",mustardmine" at the
		//end, which will prevent interpretation as IDs.
		array(string) logins = String.trim((user / ",")[*]) - ({""});
		if (!sizeof(logins)) error("No users specified.\n");
		array(int) ids = (array(int))logins;
		array users;
		if (has_value(ids, 0))
			//At least one user name failed to parse as int. Use logins.
			users = await(get_users_info(logins, "login"));
		else
			//They all look like IDs.
			users = await(get_users_info(ids, "id"));
		return ([
			"{names}": users->display_name * ", ",
			"{logins}": users->login * ", ",
			"{ids}": users->id * ", ",
		]);
	}
	int uid; catch {uid = await(get_user_id(user));};
	if (!uid) error("Can't find that person.\n");
	array names = await(G->G->DB->query_ro("select login from stillebot.user_login_sightings where twitchid = :id group by login order by min(sighted)",
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
