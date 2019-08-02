inherit command;
constant require_moderator = 1; //In theory, non-mods could be allowed to check their own status
constant hidden_command = 1; //Made unnecessary by Twitch changes, but kept in case it's wanted eg for mobile

void respond(string user, string chan, mapping info, string requester)
{
	if (!info->following) send_message("#" + chan, sprintf("@%s: %s is not following.", requester, user));
	else send_message("#" + chan, sprintf("@%s: %s has been following %s.", requester, user, (info->following/"T")[0]));
}

string process(object channel, object person, string param)
{
	if (param == "") param = person->user;
	check_following(lower_case(param), channel->name[1..])
		->then(lambda(array args) {respond(@args, person->user);});
}
