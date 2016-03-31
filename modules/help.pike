inherit command;

void process(object channel, object person, string param)
{
	array(string) cmds = indices(G->G->commands) + indices(G->G->echocommands);
	sort(cmds);
	send_message(channel->name, sprintf("@%s: Available commands are:%{ %s%}", person->nick, cmds));
}

