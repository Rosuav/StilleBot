void create(string n)
{
	foreach (indices(this),string f) if (f!="create" && f[0]!='_') add_constant(f,this[f]);
	//TODO: Have some way to 'declare' these down below, rather than
	//coding them here.
	if (!G->G->commands) G->G->commands=([]);
}

class command
{
	//Override this if the command should be available only in channels with "All Commands" selected
	int process_privileged(object channel, object person, string param) { }
	//Override this if the command should be available in all channels
	int process(object channel, object person, string param)
	{
		if (channel->config->allcmds) process_privileged(channel, person, param);
	}
	void create(string name)
	{
		sscanf(explode_path(name)[-1],"%s.pike",name);
		if (name) G->G->commands[name]=process;
	}
}
