inherit http_endpoint;

string respstr(mapping|string resp) {return Parser.encode_html_entities(stringp(resp) ? resp : resp->message);}

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req, object channel, mapping(string:mixed) session)
{
	array commands = ({ });
	int is_mod = session && session->user && channel->mods[session->user->login];
	foreach (function_object(G->G->commands->addcmd)->SPECIALS; string spec; [string desc, string originator, string params])
	{
		mixed response = G->G->echocommands[spec + channel->name];
		commands += ({sprintf("<tr><td>!%s</td><td>%s</td><td>%s</td><td>%s</td></tr>", spec, desc, originator, params)});
		if (is_mod) commands += sprintf(
			"<tr><td colspan=4>Response: <input name=%s value=\"%s\" size=100></td></tr>",
			spec[1..],
			respstr(Array.arrayify(response||"")[*])[*]);
		else if (!response) commands += ({"<tr><td colspan=4>Not active</td></tr>"});
		else commands += sprintf("<tr><td colspan=4>Response: <pre>%s</pre></td></tr>", respstr(Array.arrayify(response)[*])[*]);
	}
	return render_template("chan_specials.html", ([
		"channel": G->G->channel_info[channel->name[1..]]?->display_name || channel->name[1..],
		"commands": commands * "\n",
	]));
}
