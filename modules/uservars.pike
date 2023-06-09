inherit builtin_command;

constant builtin_description = "Look up a user's variables";
constant builtin_name = "User Vars";
constant builtin_param = ({"Keyword (optional)", "User name/ID"});

continue mapping|Concurrent.Future message_params(object channel, mapping person, array|string param, mapping cfg) {
	if (stringp(param)) {
		if (sscanf(param, "%s %s", string kwd, string user) && user) param = ({kwd, user});
		else param = ({"", param});
	}
	catch {
		//If it looks like a number, assume you meant a user ID, otherwise a user name.
		//Note that looking up an ID will not skip the API call; this ensures that, even
		//if it looks like an ID, we check that it's an actual user.
		mapping info = yield(get_user_info(param[1], (int)param[1] ? "id" : "login"));
		return (["cfg": (["users": cfg->users | ([param[0]: (string)info->id])])]);
	};
}
