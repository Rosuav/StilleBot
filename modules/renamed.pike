inherit builtin_command;
constant builtin_description = "Locate previous names for a user";
constant builtin_name = "User Renames";
constant builtin_param = ({"User name to look up"});
constant vars_provided = ([
	"{prevname}": "Most recent previous name, or blank if none seen",
	"{curname}": "Current user name (usually same as the param)",
	"{allnames}": "Space-separated list of all sighted names",
	"{error}": "Failure message, if any (prevname will be blank)",
]);

mapping message_params(object channel, mapping person, string param) {
	param -= "@";
	string uid = G->G->name_to_uid[lower_case(param)];
	if (!uid) return (["{prevname}": "", "{error}": "Can't find an ID for that person."]);
	mapping u2n = G->G->uid_to_name[uid] || ([]);
	array names = indices(u2n);
	sort(values(u2n), names);
	names -= ({"jtv", "tmi"}); //Some junk data in the files implies falsely that some people renamed to "jtv" or "tmi"
	if (sizeof(names) < 2) return (["{prevname}": "", "{curname}": param]);
	return ([
		"{prevname}": sizeof(names) >= 2 ? names[-2] : "",
		"{curname}": names[-1],
		"{allnames}": names * " ",
		"{error}": "",
	]);
}
