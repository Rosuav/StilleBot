inherit http_endpoint;

string respstr(mapping|string resp) {return Parser.encode_html_entities(stringp(resp) ? resp : resp->message);}

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	array commands = ({ });
	if (!req->misc->is_mod) {
		//Read-only view is a bit of a hack - it just doesn't say it's loading.
		return render_template("chan_triggers.md", ([
			"loadingmsg": "Restricted to moderators only",
			"save_or_login": "",
		]) | req->misc->chaninfo);
	}
	return render_template("chan_triggers.md", ([
		"vars": (["ws_type": "chan_commands", "ws_group": "!!trigger" + req->misc->channel->name, "ws_code": "chan_triggers"]),
		"loadingmsg": "Loading...",
		"save_or_login": "<input type=submit value=\"Save all\"> <button type=button id=addtrigger>Add new</button>",
	]) | req->misc->chaninfo);
}
