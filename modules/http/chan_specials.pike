inherit http_endpoint;

string respstr(mapping|string resp) {return stringp(resp) ? resp : resp->message;}

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req, object channel, mapping(string:mixed) session)
{
	array commands = ({ });
	string template = "<tr><td colspan=4><pre>%s</pre></td></tr>"; //Change this for mods (who may edit)
	foreach (function_object(G->G->commands->addcmd)->SPECIALS; string spec; [string desc, string originator, string params])
	{
		mixed response = G->G->echocommands[spec + channel->name];
		commands += ({sprintf("<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>", spec, desc, originator, params)});
		if (arrayp(response)) commands += sprintf(template, respstr(response[*])[*]);
		else if (stringp(response)) commands += ({sprintf(template, respstr(response))});
		else commands += ({"<tr><td colspan=4>Not active</td></tr>"});
	}
	return render_template("chan_specials.html", ([
		"channel": channel->name[1..], "commands": commands * "\n",
	]));
}
