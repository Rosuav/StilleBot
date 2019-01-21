inherit http_endpoint;

string respstr(mapping|string resp) {return Parser.encode_html_entities(stringp(resp) ? resp : resp->message);}

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	array commands = ({ });
	foreach (function_object(G->G->commands->addcmd)->SPECIALS; string spec; [string desc, string originator, string params])
	{
		mixed response = G->G->echocommands[spec + req->misc->channel->name];
		commands += ({sprintf("<tr><td>!%s</td><td>%s</td><td>%s</td><td>%s</td></tr>", spec, desc, originator, params)});
		if (req->misc->is_mod) commands += sprintf(
			"<tr><td colspan=4>Response: <input name=%s value=\"%s\" size=100></td></tr>",
			spec[1..],
			respstr(Array.arrayify(response||"")[*])[*]);
		else if (!response) commands += ({"<tr><td colspan=4>Not active</td></tr>"});
		else commands += sprintf("<tr><td colspan=4>Response: <pre>%s</pre></td></tr>", respstr(Array.arrayify(response)[*])[*]);
	}
	mapping replacements = ([
		"channel": req->misc->channel_name, "commands": commands * "\n",
	]);
	//Double-parse the same way Markdown files are, but without actually using Markdown
	return render_template("markdown.html", replacements | (["content": render_template("chan_specials.html", replacements)->data]));
}
