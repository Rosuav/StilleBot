inherit command;
constant featurename = 0;
constant hidden_command = 1;
constant active_channels = ({"devicat", "silentlilac"});
constant require_moderator = 1; //If 0, anyone can tag themselves. Mods can always tag anyone.
int last_used = 0;

string process(object channel, object person, string param)
{
	if (time() < last_used + 60) return 0;
	last_used = time();
	string user = person->user;
	if (param != "" && G->G->user_mod_status[user + channel->name]) user = param - "@";
	//Use our own instead. Depends on us having seen it ourselves.
	string uid = G->G->name_to_uid[lower_case(user)];
	if (!uid) return "@$$: Can't find an ID for that person.";
	mapping u2n = G->G->uid_to_name[uid] || ([]);
	array names = indices(u2n);
	sort(values(u2n), names);
	names -= ({"jtv", "tmi"}); //Some junk data in the files implies falsely that some people renamed to "jtv" or "tmi"
	if (sizeof(names) < 2) return "@$$: No name changes found.";
	write("%O\n", names); //In case we care about other names
	if (channel->name == "#silentlilac") return sprintf("!transfer %s %s", names[-2], names[-1]);
	return sprintf("!renameuser %s %s", names[-2], names[-1]);
}
