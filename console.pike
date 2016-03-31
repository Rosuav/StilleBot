void execcommand(string line)
{
	if (sscanf(line, "/join %s", string chan))
	{
		if (persist["channels"][chan]) {write("%%% Already joined.\n"); return;}
		write("%%% Joining #"+chan+"\n");
		G->G->irc->join_channel("#"+chan);
		persist["channels"][chan] = ([]);
		persist->save();
	}
	else if (sscanf(line, "/part %s", string chan))
	{
		write("%%% Parting #"+chan+"\n");
		G->G->irc->part_channel("#"+chan);
		if (m_delete(persist["channels"], chan)) persist->save();
	}
	else if (line == "/update")
	{
		werror("%%% Reloading all...\n");
		G->bootstrap_all();
		werror("%%% Reload completed.\n");
	}
	else if (sscanf(line, "/update %s", string file))
	{
		werror("%%% Updating "+file+"\n");
		G->bootstrap(file);
	}
}

void create()
{
	G->execcommand = execcommand;
}
