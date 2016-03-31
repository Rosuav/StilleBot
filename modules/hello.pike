inherit command;

void process(object channel, object person, string param)
{
	send_message(channel->name, "Hello, "+person->nick+"!");
}
