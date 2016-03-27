inherit command;

int process(object channel, object person, string param)
{
	send_message("#"+person->nick, "/host "+channel->name[1..]);
}
