inherit http_endpoint;

string respstr(mapping|string resp) {return stringp(resp) ? resp : resp->message;}

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	mapping ac = req->misc->channel->config->autocommands;
	array repeats = ({ }), messages = ({ });
	object user = user_text();
	if (req->misc->is_mod)
	{
		if (req->request_type == "POST" && req->variables->add)
		{
			string mins = req->variables->mins;
			int mins1 = (int)req->variables->mins1, mins2 = (int)req->variables->mins2;
			if (!mins && mins1 && mins2) mins = sprintf("%d-%d", mins1, mins2); //Compat with previous form
			string msg = req->variables->command || "";
			if (mins == "") messages += ({"* Must provide a repetition frequency or scheduled time"});
			else if (msg == "") messages += ({"* Need a command to repeat"});
			else messages += ({"* " + G->G->commands->repeat(req->misc->channel,
				(["user": req->misc->session->user->login]), mins + " " + msg)});
		}
		//NOTE: If this is not at the top, pressing Enter in the form will click the wrong
		//submit button and will delete the first autocommand. Not good.
		repeats += ({"<input name=mins size=10> mins or time"
			" | - | <input name=command size=50> | <input type=submit name=add value=\"Add new\">"});
	}
	foreach (ac || ({ }); string msg; int|array(int) mins)
	{
		if (!arrayp(mins)) mins = ({mins-1, mins+1, 0});
		if (sizeof(mins) == 2) mins += ({0});
		string time = mins[2] ? sprintf("at %d:%d", mins[0], mins[1]) : sprintf("%d-%d mins", mins[0], mins[1]);
		string delete = "";
		if (req->misc->is_mod)
		{
			if (req->request_type == "POST" && req->variables["delete" + msg] == "Delete")
			{
				//TODO: Should it confirm before deleting?
				messages += ({"* " + G->G->commands->repeat(req->misc->channel, (["user": req->misc->session->user->login]), "-1 " + msg)});
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
			repeats += ({sprintf("%s | %s | %s%s", time, user(msg), user(output), delete)});
		}
		//Arbitrary echoed text, no associated command
		else repeats += ({sprintf("%s | - | %s%s", time, user(msg), delete)});
	}
	if (!sizeof(repeats)) repeats = ({"- | - | (none)"});
	return render_template("chan_repeats.md", ([
		"user text": user,
		"channel": req->misc->channel_name,
		"repeats": repeats * "\n",
		"messages": messages * "\n",
		"login": req->misc->login_link || "",
	]));
}
