inherit command;
constant require_allcmds = 1;

string process(object channel, object person, string param)
{
	array(string) cmds = ("!"+indices(G->G->commands)[*]) + indices(G->G->echocommands);
	//Hack: !currency is invoked as !chocolates when the currency name
	//is "chocolates", and shouldn't be invoked at all if there's no
	//channel currency here.
	cmds -= ({"!currency"});
	string cur = channel->config->currency;
	if (cur && cur != "") cmds += ({"!"+cur});
	return "@$$: Available commands are: " + sort(cmds) * " ";
}

