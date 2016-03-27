void execcommand(string line)
{
	if (sscanf(line, "/join %s", string chan))
	{
		write("%%% Joining #"+chan+"\n");
		G->irc->join_channel("#"+chan);
		G->channels += ({"#"+chan});
	}
	else if (sscanf(line, "/part %s", string chan))
	{
		write("%%% Parting #"+chan+"\n");
		G->irc->part_channel("#"+chan);
		G->channels -= ({"#"+chan});
	}
	else if (line == "/update")
	{
		write("%%% Reloading all...\n");
		G->bootstrap_all();
		write("%%% Reload completed.\n");
	}
	else if (sscanf(line, "/update %s", string file))
	{
		write("%%% Updating "+file+"\n");
		G->bootstrap(file);
	}
}

void create()
{
	G->execcommand = execcommand;
}
