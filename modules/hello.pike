inherit command;
constant hidden_command = 1;

echoable_message process(object channel, object person, string param)
{
	//Respond by whisper:
	//return (["message": "Hello $$ in a whisper", "dest": "/w $$"]);
	//Send someone else a whisper, even if !hello was whispered to the bot:
	//return (["message": "Hello from $$!", "dest": "/w " + param]);
	//Respond with multiple messages:
	//return ({"Hello, world!", "And hello $$ too."});
	//Respond normally in chat:
	return "Hello, $$!";
}
