inherit http_endpoint;

string respstr(mapping|string resp) {return stringp(resp) ? resp : resp->message;}

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	string c = req->misc->channel->name;
	array commands = ({ });
	foreach (G->G->echocommands; string cmd; echoable_message response) if (!has_prefix(cmd, "!") && has_suffix(cmd, c))
	{
		cmd -= c;
		if (arrayp(response)) commands += ({sprintf("* !%s ==>%{ `%s`%}", cmd, respstr(response[*]))});
		else commands += ({sprintf("* !%s ==> `%s`", cmd, respstr(response))});
	}
	sort(commands);
	if (!sizeof(commands)) commands = ({"(none)"});
	return render_template("chan_commands.md", ([
		"channel": req->misc->channel_name, "commands": commands * "\n",
	]));
}
