inherit http_endpoint;
inherit websocket_handler;

inherit builtin_command;
constant hidden_command = 1;
constant require_allcmds = 1;
constant access = "mod";

string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string document] = split_channel(msg->group);
	if (!channel) return "Bad channel";
	conn->is_mod = channel->mods[conn->session->user->login];
}

mapping get_state(string group, string|void id)
{
	[object channel, string document] = split_channel(group);
	if (!channel) return 0;
	mapping doc = persist_status->path("mpn", channel->name)[document];
	if (!doc) return 0; //Can't create implicitly. Create with the command first.
	write("%O\n", doc);
	array items = values(doc->lines); sort(items, items->id);
	return (["items": items]);
}

void websocket_cmd_update(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string document] = split_channel(conn->group); if (!channel) return;
	if (!conn->is_mod) return;
	mapping doc = persist_status->path("mpn", channel->name)[document];
	if (!doc) return;
	if (!doc->lines[msg->id]) {
		//New!
		string newid = "0";
		//TODO: Respect msg->before and construct an ID that will be immediately before
		//that ID. If no msg->before, construct an ID greater than all current IDs.
		doc->lines[msg->id = newid] = (["id": newid]);
	}
	doc->lines[msg->id]->content = msg->content;
	send_updates_all(conn->group);
}

mapping(string:mixed)|string|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	string document = req->variables->document;
	if (!document) {
		return "TODO: Give explanatory info or maybe a list";
	}
	if (!persist_status->path("mpn", req->misc->channel->name)[document]) {
		return "TODO: No such document, maybe suggest how to create it";
	}
	//TODO: Ensure that the document exists
	return render_template("chan_mpn.md", ([
		"vars": (["ws_type": "chan_mpn", "ws_group": document + req->misc->channel->name]),
	]) | req->misc->chaninfo);
}

constant command_description = "Create, manage, or link to an MPN document";
constant default_response = ([
	"conditional": "string", "expr1": "{url}", "expr2": "",
	"message": "No such document.",
	"otherwise": "{action} Document can be found at: {url}",
]);

mapping|Concurrent.Future message_params(object channel, mapping person, string param)
{
	write("message_params(channel %O, person %O, %O)\n", channel->name, person->user, param);
	if (param == "") return (["{url}": ""]); //TODO: Give a help message?
	sscanf(param, "%s %s", string cmd, string arg);
	mapping document;
	if (cmd == "create" && arg && arg != "") {
		document = persist_status->path("mpn", channel->name, arg);
		if (!document->lines) document->lines = ([]);
		persist_status->save();
	}
	else {
		document = persist_status->path("mpn", channel->name)[arg];
		if (!document) return (["{url}": ""]); //TODO: Error message?
	}
	return ([
		"{url}": "https://......./",
		"{action}": "",
	]);
}

protected void create(string name) {::create(name);}
