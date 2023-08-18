//Ironically, this file needs to be renamed. But that would be a breaking change, so I won't.
inherit builtin_command;
constant builtin_name = "User info";
constant builtin_description = "Get info about a chatter";
constant builtin_param = ({"User name to look up"});
constant vars_provided = ([
	"{following}": "Blank if user is not following, otherwise a description of how long",
	"{prevname}": "Most recent previous name, or blank if none seen",
	"{curname}": "Current user name (usually same as the param)",
	"{allnames}": "Space-separated list of all sighted names",
	"{error}": "Failure message, if any (prevname will be blank)",
]);
constant command_suggestions = (["!follower": ([
	"_description": "Check whether someone is following the channel",
	"builtin": "renamed", "builtin_param": "%s",
	"message": ([
		"conditional": "string", "expr1": "{error}", "expr2": "",
		"message": ([
			"conditional": "string", "expr1": "{following}", "expr2": "",
			"message": "@{username}: {curname} is not following.",
			"otherwise": "@{username}: {curname} has been following {following}.",
		]),
		"otherwise": "@$$: {error}",
	]),
])]);

continue Concurrent.Future|mapping message_params(object channel, mapping person, string param) {
	param -= "@";
	int uid; catch {uid = yield(get_user_id(param));};
	if (!uid) return (["{prevname}": "", "{error}": "Can't find that person."]);
	mapping u2n = G->G->uid_to_name[(string)uid] || ([]);
	array names = indices(u2n);
	sort(values(u2n), names);
	names -= ({"jtv", "tmi"}); //Some junk data in the files implies falsely that some people renamed to "jtv" or "tmi"
	[string user, string chan, mapping foll] = yield(check_following(lower_case(param), channel->name[1..]));
	return ([
		"{following}": foll->following || "",
		"{prevname}": sizeof(names) >= 2 ? names[-2] : "",
		"{curname}": sizeof(names) ? names[-1] : param,
		"{allnames}": names * " ",
		"{error}": "",
	]);
}
