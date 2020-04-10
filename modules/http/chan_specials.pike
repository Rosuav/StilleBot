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
						G->G->echocommands[cmdname] = text;
						updates += ({sprintf("<li>%s %sated.</li>", spec, response ? "upd" : "cre")});
					}
					else
					{
						m_delete(G->G->echocommands, cmdname);
						updates += ({sprintf("<li>%s deleted.</li>", spec)});
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
	string messages = "";
	if (sizeof(updates))
	{
		messages = "<ul>" + updates * "\n" + "</ul>";
		make_echocommand(0, 0); //Trigger a save without adding a command
	}
	mapping replacements = ([
		"channel": req->misc->channel_name, "commands": commands * "\n",
		"title": "Special responses for " + req->misc->channel_name,
		"backlink": "<small><a href=\"./\">StilleBot - " + req->misc->channel_name + "</a></small>",
		"messages": messages,
		"save_or_login": req->misc->login_link || "<input type=submit value=\"Save all\">",
	]);
	//Double-parse the same way Markdown files are, but without actually using Markdown
	return render_template("markdown.html", replacements | (["content": render_template("chan_specials.html", replacements)->data]));
}
