inherit http_endpoint;

string respstr(mapping|string resp) {return stringp(resp) ? resp : resp->message;}

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	mapping ac = req->misc->channel->config->autocommands;
	array repeats = ({ });
	foreach (ac || ({ }); string msg; int mins)
	{
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
			else if (stringp(cmd)) output = cmd; //Easy - outputs one command.
			else if (mappingp(cmd)) output = cmd->message;
			else if (arrayp(cmd)) output = cmd * " "; //TODO: Handle array of mappings
			else output = "(unknown/variable)";
			//TODO: What if there Markdown special characters in the output??
			//Bigger TODO: Should render_template actually embed tokens for interpolation?
			repeats += ({sprintf("%d mins | %s | %s", mins, msg, output)});
		}
		//Arbitrary echoed text, no associated command
		else repeats += ({sprintf("%d mins |- | %s", mins, msg)});
	}
	if (!sizeof(repeats)) repeats = ({"- | (none) |"});
	return render_template("chan_repeats.md", ([
		"channel": req->misc->channel_name,
		"repeats": repeats * "\n",
		"save_or_login": req->misc->is_mod ?
			"<input type=submit value=\"Save all\">" :
			"<a href=\"/twitchlogin?next=" + req->not_query + "\">Mods, login to make changes</a>",
	]));
}
