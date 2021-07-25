inherit command;
constant featurename = "debug";
constant hidden_command = 1;

void validate_keys(mapping data, string path) {
	foreach (data; mixed key; mixed data) {
		if (!stringp(key)) werror("** Bad key: %s[%O] %<t**\n", path, key);
		if (mappingp(data)) validate_keys(data, sprintf("%s[%O]", path, key));
	}
}

echoable_message process(object channel, object person, string param)
{
	if (param == "validate" && person->uid == 49497888) {
		validate_keys(persist_status->data, "persist_status");
		validate_keys(persist_config->data, "persist_config");
	}
	//Respond by whisper:
	//return (["message": "Hello $$ in a whisper", "dest": "/w", "target": "$$"]);
	//Send someone else a whisper, even if !hello was whispered to the bot:
	//return (["message": "Hello from $$!", "dest": "/w", "target": param]);
	//Respond with multiple messages:
	//return ({"Hello, world!", "And hello $$ too."});
	//Respond normally in chat:
	return "Hello, $$!";
}
