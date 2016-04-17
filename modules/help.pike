inherit command;
constant require_allcmds = 1;

string process(object channel, object person, string param)
{
	//TODO: Replace !currency with the currency name, if there is one.
	//And suppress it if there isn't. And preferably, let commands
	//identify themselves, somehow. Maybe.
	array(string) cmds = ("!"+indices(G->G->commands)[*]) + indices(G->G->echocommands);
	return "@$$: Available commands are: " + sort(cmds) * " ";
}

