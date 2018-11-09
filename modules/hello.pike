inherit command;
constant hidden_command = 1;

string|array(string) process(object channel, object person, string param)
{
	//Respond by whisper:
	//channel->wrap_message(person, "Hello $$ in a whisper!", "/w " + person->nick);
	//Send someone else a whisper:
	//channel->wrap_message(person, "Hello from $$!", "/w " + param);
	//Respond normally in chat:
	return "Hello, $$!";
}
