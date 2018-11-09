inherit command;
constant hidden_command = 1;

echoable_message process(object channel, object person, string param)
{
	//Respond by whisper:
	//return (["message": "Hello $$ in a whisper", "dest": "/w $$"]);
	//Send someone else a whisper, but if whispered to the bot, will whisper back to sender:
	//return (["message": "Hello from $$!", "dest": "/w " + param]);
	//Respond with multiple messages:
	//return ({"Hello, world!", "And hello $$ too."});
	//Respond normally in chat:
	return "Hello, $$!";
}
