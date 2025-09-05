inherit builtin_command;

constant builtin_description = "Look up a user's variables";
constant builtin_name = "User Vars";
constant builtin_param = ({"Keyword (optional)", "User name/ID"});
constant vars_provided = ([
	"{login}": "Twitch login of the user (usually the same as the display name but lowercased)",
	"{name}": "Display name of the user",
	"{avatar}": "User's avatar/profile pic",
	"{uid}": "User's Twitch ID",
]);

__async__ mapping message_params(object channel, mapping person, array param, mapping cfg) {
	mapping info = ([]);
	catch {
		//If it looks like a number, assume you meant a user ID, otherwise a user name.
		//Note that looking up an ID will not skip the API call; this ensures that, even
		//if it looks like an ID, we check that it's an actual user.
		param[1] -= "@";
		info = await(get_user_info(param[1], (int)param[1] ? "id" : "login"));
	};
	//If something went wrong, the ID will be zero, which can be probed for using $kwd*$.
	//Note particularly that this will *BLOCK* access to any previously-assigned user
	//with that keyword, preventing accidental access to the wrong variables.
	return ([
		"cfg": (["users": cfg->users | ([param[0]: (string)info->id])]),
		"{login}": info->login || "",
		"{name}": info->display_name || "",
		"{avatar}": info->profile_image_url || "",
		"{uid}": info->id || "0",
	]);
}
