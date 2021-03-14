inherit http_endpoint;

string respstr(mapping|string resp) {return Parser.encode_html_entities(stringp(resp) ? resp : resp->message);}

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	array commands = ({ }), updates = ({ });
	foreach (function_object(G->G->commands->addcmd)->SPECIALS, [string spec, [string desc, string originator, string params]])
	{
		string cmdname = spec + req->misc->channel->name;
		mixed response = G->G->echocommands[cmdname];
		commands += ({sprintf("<tr class=gap></tr><tr><td>!%s</td><td>%s</td><td>%s</td><td>%s</td></tr>", spec, desc, originator, params)});
		if (req->misc->is_mod)
		{
			if (string text = req->request_type == "POST" && req->variables[spec[1..]])
			{
				if (text == "") text = UNDEFINED;
				if (text != response)
				{
					if (text)
					{
						make_echocommand(cmdname, text);
						updates += ({sprintf("* %s %sated.", spec, response ? "upd" : "cre")});
					}
					else
					{
						make_echocommand(cmdname, 0);
						updates += ({sprintf("* %s deleted.", spec)});
					}
					response = text;
					
				}
			}
			commands += sprintf(
				"<tr><td colspan=4>Response:<span class=gap></span><input name=%s value=\"%s\" size=100></td></tr>",
				spec[1..],
				respstr(Array.arrayify(response||"")[*])[*]);
		}
		else if (!response) commands += ({"<tr><td colspan=4>Not active</td></tr>"});
		else commands += sprintf("<tr><td colspan=4>Response:<span class=gap></span><code>%s</code></td></tr>", respstr(Array.arrayify(response)[*])[*]);
	}
	return render_template("chan_specials.md", ([
		"commands": commands * "\n",
		"title": "Special responses for " + req->misc->chaninfo->channel,
		"messages": updates * "\n",
		"save_or_login": "<input type=submit value=\"Save all\">",
	]) | req->misc->chaninfo);
}
