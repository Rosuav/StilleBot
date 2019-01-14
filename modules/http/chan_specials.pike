inherit http_endpoint;

string respstr(mapping|string resp) {return stringp(resp) ? resp : resp->message;}

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req, object channel, mapping(string:mixed) session)
{
	array commands = ({ });
	foreach (function_object(G->G->commands->addcmd)->SPECIALS; string spec;)
		if (mixed response = G->G->echocommands[spec + channel->name])
		{
			//TODO: Show what each one actually MEANS.
			if (arrayp(response)) commands += ({sprintf("* !%s ==>%{ `%s`%}", spec, respstr(response[*]))});
			else commands += ({sprintf("* !%s ==> `%s`", spec, respstr(response))});
		}
	if (!sizeof(commands)) commands = ({"(none)"});
	return render_template("chan_specials.md", ([
		"channel": channel->name[1..], "commands": commands * "\n",
	]));
}
