inherit builtin_command;
constant builtin_description = "Query a stream to see if it is live";
constant builtin_name = "Now-Live";
constant builtin_param = "Channel name";
constant vars_provided = ([
	"{channellive}": "Either 'offline' or a human-readable-ish time",
]);

continue mapping|Concurrent.Future message_params(object channel, mapping person, string param)
{
	string live = "notfound";
	catch {live = yield(channel_still_broadcasting(replace(param, ({"@", " "}), "")));};
	return (["{channellive}": live]);
}
