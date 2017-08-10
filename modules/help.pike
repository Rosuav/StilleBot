inherit command;

string process(object channel, object person, string param)
{
	multiset(string) cmds = (<>);
	foreach (({G->G->commands, G->G->echocommands}), mapping commands)
		foreach (commands; string cmd;)
			if (!has_value(cmd, '#') || has_suffix(cmd, channel->name))
				cmds[cmd - channel->name] = 1;
	//Hack: !currency is invoked as !chocolates when the currency name
	//is "chocolates", and shouldn't be invoked at all if there's no
	//channel currency here.
	cmds["currency"] = 0;
	string cur = channel->config->currency;
	if (cur && cur != "") cmds[cur] = 1;
	return "@$$: Available commands are: " + ("!"+sort(indices(cmds))[*]) * " ";
}
