inherit http_endpoint;

string respstr(mapping|string resp) {return stringp(resp) ? resp : resp->message;}

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	string c = req->misc->channel->name;
	array commands = ({ }), order = ({ });
	object user = user_text();
	foreach (G->G->echocommands; string cmd; echoable_message response) if (!has_prefix(cmd, "!") && has_suffix(cmd, c))
	{
		cmd -= c;
		if (req->misc->is_mod)
		{
			string usercmd = Parser.encode_html_entities(cmd);
			string inputs = "";
			foreach (Array.arrayify(response); int i; string|mapping resp)
				inputs += sprintf("<br><input name=\"%s!%d\" value=\"%s\" size=200>",
					usercmd, i, Parser.encode_html_entities(respstr(resp)));
			commands += ({sprintf("<code>!%s</code> | %s", usercmd, inputs[4..])});
		}
		else
		{
			if (arrayp(response)) response = user(respstr(response[*])[*]) * "</code><br><code>";
			else response = user(respstr(response));
			commands += ({sprintf("<code>!%s</code> | <code>%s</code>", user(cmd), response)});
		}
		order += ({cmd});
	}
	sort(order, commands);
	if (!sizeof(commands)) commands = ({"(none) |"});
	if (req->misc->is_mod) commands += ({"Add: <input name=newcmd_name size=10 placeholder=\"!hype\"> | <input name=newcmd_resp size=200>"});
	return render_template("chan_commands.md", ([
		"user text": user,
		"channel": req->misc->channel_name, "commands": commands * "\n",
		"save_or_login": req->misc->is_mod ?
			"<input type=submit value=\"Save all\">" :
			"<a href=\"/twitchlogin?next=" + req->not_query + "\">Mods, login to make changes</a>",
	]));
}
