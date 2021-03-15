inherit http_endpoint;

string respstr(mapping|string resp) {return Parser.encode_html_entities(stringp(resp) ? resp : resp->message);}

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	array commands = ({ });
	if (!req->misc->is_mod) {
		//TODO: Read-only view
		return render_template("chan_specials.md", ([
		]));
	}
	foreach (function_object(G->G->commands->addcmd)->SPECIALS, [string spec, [string desc, string originator, string params]])
		commands += ({(["id": spec + req->misc->channel->name, "desc": desc, "originator": originator, "params": params])});
	return render_template("chan_specials.md", (["vars": ([
		"commands": commands,
		"ws_type": "chan_commands", "ws_group": "!!" + req->misc->channel->name, "ws_code": "chan_specials",
	])]) | req->misc->chaninfo);
}
