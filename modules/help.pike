inherit command;

string process(object channel, object person, string param)
{
	multiset(string) cmds = (<>);
	int is_mod = channel->mods[person->user];
	foreach (({G->G->commands, G->G->echocommands}), mapping commands)
		foreach (commands; string cmd; string|function handler)
		{
			//Note that we support strings and functions in both mappings.
			//Actual command execution isn't currently quite this flexible,
			//assuming that functions are in G->G->commands and strings are
			//in G->G->echocommands. It may be worth making execution more
			//flexible, which might simplify some multi-command modules.
			object|mapping flags =
				//Availability flags come from the providing object, normally.
				functionp(handler) ? function_object(handler) :
				//String commands use these default flags.
				(["all_channels": 0, "require_moderator": 0, "hidden_command": 0]);
			if (flags->hidden_command) continue;
			if (!flags->all_channels && !channel->config->allcmds) continue;
			if (flags->require_moderator && !is_mod) continue;
			if (!has_value(cmd, '#') || has_suffix(cmd, channel->name))
				cmds[cmd - channel->name] = 1;
		}
	//Hack: !currency is invoked as !chocolates when the currency name
	//is "chocolates", and shouldn't be invoked at all if there's no
	//channel currency here.
	cmds["currency"] = 0;
	string cur = channel->config->currency;
	if (cur && cur != "") cmds[cur] = 1;
	return "@$$: Available commands are: " + ("!"+sort(indices(cmds))[*]) * " ";
}
