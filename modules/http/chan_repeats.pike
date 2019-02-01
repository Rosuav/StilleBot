inherit http_endpoint;

string respstr(mapping|string resp) {return stringp(resp) ? resp : resp->message;}

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	mapping ac = req->misc->channel->config->autocommands;
	array repeats = ({ }), messages = ({ });
	object user = user_text();
	foreach (ac || ({ }); string msg; int mins)
	{
		string delete = "";
		if (req->misc->is_mod)
		{
			if (req->request_type == "POST" && req->variables["delete" + msg] == "Delete")
			{
				//TODO: Should it confirm before deleting?
				//As with specials: TODO: Dedup
				m_delete(ac, msg);
				if (mixed id = m_delete(G->G->autocommands, req->misc->channel->name + " " + msg))
					remove_call_out(id);
				persist_config->save();
				messages += ({"* Removed repeated command: " + user(msg)});
				continue;
			}
			//Add a Delete button to the end of each row
			delete = sprintf(" | <input type=submit value=Delete name=\"delete%s\">", Parser.encode_html_entities(msg));
		}
		if (has_prefix(msg, "!"))
		{
			//Common/expected case: the repeat is a command.
			//The most common is that it will be an echo command.
			//If it isn't a channel-specific echo command, don't try
			//to figure out what it would actually output, as it may
			//very well not be side-effect-free.
			string output;
			echoable_message cmd = G->G->echocommands[msg[1..] + req->misc->channel->name];
			if (undefinedp(cmd)) output = "(command not found)";
			else if (stringp(cmd)) output = cmd; //Easy - outputs one message.
			else if (mappingp(cmd)) output = cmd->message;
			else if (arrayp(cmd)) output = cmd * " "; //TODO: Handle array of mappings
			else output = "(unknown/variable)";
			repeats += ({sprintf("%d mins | %s | %s%s", mins, user(msg), user(output), delete)});
		}
		//Arbitrary echoed text, no associated command
		else repeats += ({sprintf("%d mins |- | %s%s", mins, user(msg), delete)});
	}
	if (!sizeof(repeats)) repeats = ({"- | - | (none)"});
	return render_template("chan_repeats.md", ([
		"user text": user,
		"channel": req->misc->channel_name,
		"repeats": repeats * "\n",
		"messages": messages * "\n",
		"save_or_login": req->misc->is_mod ?
			"<input type=submit value=\"Save all\">" :
			"<a href=\"/twitchlogin?next=" + req->not_query + "\">Mods, login to make changes</a>",
	]));
}
