inherit builtin_command;

constant builtin_description = "Look up a user's variables";
constant builtin_name = "User Vars";
constant builtin_param = ({"Keyword (optional)", "User name/ID"});

//TODO: A thing kinda like this for a leaderboard.
//Instaed of "set this keyword to this user's ID", it will be "set this keyword to the
//UID of the highest ranked person", and possibly "set kwd1, kwd2, kwd3" etc.
__async__ mapping message_params(object channel, mapping person, array param, mapping cfg) {
	mapping info = ([]);
	catch {
		//If it looks like a number, assume you meant a user ID, otherwise a user name.
		//Note that looking up an ID will not skip the API call; this ensures that, even
		//if it looks like an ID, we check that it's an actual user.
		info = await(get_user_info(param[1], (int)param[1] ? "id" : "login"));
	};
	//If something went wrong, the ID will be zero, which can be probed for using $kwd*$.
	//Note particularly that this will *BLOCK* access to any previously-assigned user
	//with that keyword, preventing accidental access to the wrong variables.
	return (["cfg": (["users": cfg->users | ([param[0]: (string)info->id])])]);
}
