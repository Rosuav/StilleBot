void create(string n)
{
	foreach (indices(this),string f) if (f!="create" && f[0]!='_') add_constant(f,this[f]);
	//TODO: Have some way to 'declare' these down below, rather than
	//coding them here.
	if (!G->G->commands) G->G->commands=([]);
}

class command
{
	constant require_allcmds = 0; //Set to 1 if this command should be available only if allcmds is set for the channel
	constant require_moderator = 0; //Set to 1 if the command is mods-only
	//Override this to do the command's actual functionality, after permission checks.
	void process(object channel, object person, string param) { }

	void check_perms(object channel, object person, string param)
	{
		if (require_allcmds && !channel->config->allcmds) return;
		if (require_moderator && !channel->mods[person->user]) return;
		process(channel, person, param);
	}
	void create(string name)
	{
		sscanf(explode_path(name)[-1],"%s.pike",name);
		if (name) G->G->commands[name]=check_perms;
	}
}

string describe_time(int tm)
{
	string msg = "";
	if (int t = tm/86400) {msg += sprintf(", %d days", t); tm %= 86400;}
	if (int t = tm/3600) {msg += sprintf(", %d hours", t); tm %= 3600;}
	if (int t = tm/60) {msg += sprintf(", %d minutes", t); tm %= 60;}
	if (tm) msg += sprintf(", %d seconds", tm);
	return msg[2..];
}
