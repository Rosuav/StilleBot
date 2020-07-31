inherit http_endpoint;

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	string c = req->misc->channel->name;
	array counters = ({ }), order = ({ }), messages = ({ });
	foreach (persist_status->path("counters", c); string name; int value)
	{
		counters += ({sprintf("%s | %d | - | - | -", name, value)});
		order += ({name}); //TODO: Have "order" entries to list all commands. Use rowspan??
	}
	sort(order, counters);
	if (!sizeof(counters)) counters = ({"(none) |"});
	//if (changes_made) make_echocommand(0, 0); //Trigger a save
	return render_template("chan_counters.md", ([
		//"user text": user,
		"channel": req->misc->channel_name, "counters": counters * "\n",
		"messages": messages * "\n",
		"save_or_login": req->misc->login_link || "<input type=submit value=\"Save all\">",
	]));
}
