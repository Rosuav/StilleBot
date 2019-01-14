inherit http_endpoint;

string respstr(mapping|string resp) {return stringp(resp) ? resp : resp->message;}

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req, object channel, mapping(string:mixed) session)
{
	array commands = ({ });
	int is_mod = session && session->user && channel->mods[session->user->login];
	foreach (function_object(G->G->commands->addcmd)->SPECIALS; string spec; [string desc, string originator, string params])
	{
		mixed response = G->G->echocommands[spec + channel->name];
		commands += ({sprintf("<tr><td>!%s</td><td>%s</td><td>%s</td><td>%s</td></tr>", spec, desc, originator, params)});
		if (!response) commands += ({"<tr><td colspan=4>Not active</td></tr>"});
		else if (is_mod) commands += sprintf("<tr><td>MOD</td><td colspan=3><pre>%s</pre></td></tr>", respstr(Array.arrayify(response)[*])[*]);
		else commands += sprintf("<tr><td colspan=4><pre>%s</pre></td></tr>", respstr(Array.arrayify(response)[*])[*]);
	}
	return render_template("chan_specials.html", ([
		"channel": channel->name[1..], "commands": commands * "\n",
	]));
}
