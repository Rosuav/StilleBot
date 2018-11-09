inherit command;
constant hidden_command = 1;

string|mapping|array(string|mapping) process(object channel, object person, string param)
{
	//Respond by whisper:
	//return (["message": "Hello $$ in a whisper", "dest": "/w " + person->nick]);
	//Send someone else a whisper:
	//return (["message": "Hello from $$!", "dest": "/w " + param]);
	//Respond with multiple messages:
	//return ({"Hello, world!", "And hello $$ too."});
	//Respond normally in chat:
	return "Hello, $$!";
}
