inherit command;

int process(object channel, object person, string param)
{
	array(string) cmds = indices(G->G->commands); //TODO: Add the ones from the json file
	sort(cmds);
	send_message(channel->name, sprintf("@%s: Available commands are:%{ %s%}", person->nick, cmds));
}

