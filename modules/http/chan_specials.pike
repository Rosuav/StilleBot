inherit http_endpoint;

string respstr(mapping|string resp) {return Parser.encode_html_entities(stringp(resp) ? resp : resp->message);}

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	array commands = ({ });
	if (!req->misc->is_mod) {
		//Read-only view is a bit of a hack - it just doesn't say it's loading.
		return render_template("chan_specials.md", ([
			"loadingmsg": "Restricted to moderators only",
			"save_or_login": "",
		]) | req->misc->chaninfo);
	}
	object addcmd = function_object(G->G->commands->addcmd);
	foreach (addcmd->SPECIALS, [string spec, [string desc, string originator, string params], string tab])
		commands += ({(["id": spec + req->misc->channel->name, "desc": desc, "originator": originator, "params": params, "tab": tab])});
	return render_template("chan_specials.md", ([
		"vars": ([
			"commands": commands,
			"SPECIAL_PARAMS": mkmapping(@Array.transpose(addcmd->SPECIAL_PARAMS)),
			"ws_type": "chan_commands", "ws_group": "!!" + req->misc->channel->name, "ws_code": "chan_specials",
			"builtins": G->G->commands_builtins,
		]),
		"loadingmsg": "Loading...",
		"save_or_login": "<input type=submit value=\"Save all\">",
	]) | req->misc->chaninfo);
}
