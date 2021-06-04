inherit http_websocket;
inherit builtin_command;
constant hidden_command = 1;
constant require_allcmds = 1;
constant access = "none";
constant markdown = #"# MPN - $$channel$$

<$$contenttag$$ id=content rows=25 cols=80></$$contenttag$$>

$$save_or_login||Changes made above will be automatically saved.$$
";

void rebuild_lines(mapping(string:mixed) doc) {
	if (!doc->lines) doc->lines = mkmapping(doc->sequence->id, doc->sequence);
	foreach (doc->sequence; int i; mapping line) line->position = i;
}

mapping(string:int) render_squelch = ([]);
void unsquelch(string group) {
	if (m_delete(render_squelch, group) > 1) update_rendered(group);
}
void update_rendered(string group) {
	if (render_squelch[group]) {++render_squelch[group]; return;}
	send_updates_all(replace(group, "#", " html#"));
	render_squelch[group] = 1;
	call_out(unsquelch, 1, group);
}

void add_line(string group, mapping(string:mixed) doc, string addme, string|void beforeid) {
	string newid = (string)++doc->lastid;
	mapping line = doc->lines[newid] = (["id": newid, "content": addme]);
	//If a valid "before" ID is given, insert the line before that one. Otherwise, append.
	mapping before = doc->lines[beforeid];
	int pos = before ? before->position : sizeof(doc->sequence);
	doc->sequence = doc->sequence[..pos - 1] + ({line}) + doc->sequence[pos..];
	rebuild_lines(doc);
	send_updates_all(group);
	update_rendered(group);
}

array(object|mapping|string) split_channel(string|void group) {
	[object channel, string document] = ::split_channel(group);
	sscanf(document, "%s %s", document, string mode);
	return ({channel, persist_status->path("mpn", channel->name)[document], mode || ""});
}

constant valid_modes = (["": 1, "html": 2, "embed": 2]); //Map to 2 if anyone can, or 1 if mods only
string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, mapping doc, string mode] = split_channel(msg->group);
	if (!channel) return "Bad channel";
	conn->is_mod = channel->mods[conn->session->?user->?login];
	if (valid_modes[mode] - !conn->is_mod <= 0) return "Bad mode flag"; //No default-to-HTML here - keep it dependable
	if (!doc) return "Bad document name"; //Allowed to be ugly as it'll normally be trapped at the HTTP request end
}

mapping get_state(string group, string|void id) {
	[object channel, mapping doc, string mode] = split_channel(group);
	if (!channel) return 0;
	if (!doc) return 0; //Can't create implicitly. Create with the command first.
	if (mode == "html") {
		string content = doc->sequence->content * "\n";
		content = channel->expand_variables(content);
		#if constant(Parser.Markdown)
		//If we don't have a Markdown parser, just keep the text as-is (assume it's HTML).
		content = Tools.Markdown.parse(content, ([
			"renderer": Renderer, "lexer": Lexer,
			"attributes": 1, //Ignored if using older Pike (or, as of 2020-04-13, vanilla Pike - it's only on branch rosuav/markdown-attribute-syntax)
		]));
		#endif
		return (["html": content]);
	}
	if (doc->lines[id]) return doc->lines[id];
	return (["items": doc->sequence]);
}

//TODO maybe: Have a "rewrite document" message that fully starts over?
void websocket_cmd_update(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, mapping doc, string mode] = split_channel(conn->group); if (!channel) return;
	if (!conn->is_mod || !doc || mode != "") return;
	if (!doc->lines[msg->id]) {add_line(conn->group, doc, (string)msg->content, msg->before); return;}
	mapping l = doc->lines[msg->id];
	if (!msg->content) { //Delete line
		doc->sequence = doc->sequence[..l->position - 1] + doc->sequence[l->position + 1..];
		m_delete(doc->lines, msg->id);
		rebuild_lines(doc);
		send_updates_all(conn->group);
		update_rendered(conn->group);
		return;
	}
	l->content = (string)msg->content;
	update_one(conn->group, l->id);
	update_rendered(conn->group);
}

mapping(string:string|array) safe_query_vars(mapping(string:string|array) vars) {
	mapping ret = vars & (<"document">);
	if (valid_modes[vars->mode] == 1) ret->mode = vars->mode;
	return ret;
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
	string mode = req->variables->mode || "";
	//TODO: mode == "embed", render like "html" but with no boilerplate
	if (valid_modes[mode] - !req->misc->is_mod <= 0) {
		if (mode == "") mode = "html"; //Not logged in, didn't specify mode? Default to a simple view-only.
		else return "TODO: Not logged in or mode not valid";
	}
	if (mode != "") document += " " + mode;
	return render(req, ([
		"vars": (["ws_group": document]),
		"contenttag": (["html": "div"])[mode] || "textarea",
		"save_or_login": (["html": "Changes will appear above as they are made.", "embed": ""])[mode],
	]) | req->misc->chaninfo);
}

constant command_description = "Create, manage, or link to an MPN document";
constant builtin_name = "MPN document";
constant default_response = ([
	"conditional": "string", "expr1": "{error}", "expr2": "",
	"message": ([
		"conditional": "string", "expr1": "{url}", "expr2": "",
		"message": "{action} Document does not exist.",
		"otherwise": "{action} Document can be found at: {url}",
	]),
	"otherwise": "{error}",
]);
constant vars_provided = ([
	"{error}": "Error message, if any",
	"{action}": "Action performed (if any)",
	"{url}": "URL to the manipulated document, blank if no such document",
]);
constant command_suggestions = ([]); //No default command suggestions as yet. Maybe I'll figure out some later.

mapping|Concurrent.Future message_params(object channel, mapping person, string param)
{
	write("message_params(channel %O, person %O, %O)\n", channel->name, person->user, param);
	if (param == "") return (["{error}": "Need a subcommand"]);
	sscanf(param, "%s %[^ ]%*[ ]%s", string cmd, string document, string arg);
	mapping doc;
	string action = "";
	if (cmd == "create" && document && document != "") {
		doc = persist_status->path("mpn", channel->name, document);
		if (!doc->sequence) doc->sequence = ({ });
		m_delete(doc, "lines"); rebuild_lines(doc);
		persist_status->save();
		action = "Created " + document + ".";
	}
	else {
		doc = persist_status->path("mpn", channel->name)[document];
		if (!doc) return (["{error}": "Document does not exist."]);
	}
	switch (cmd) {
		case "delete":
			m_delete(persist_status->path("mpn", channel->name), document);
			persist_status->save();
			action = "Deleted " + document + ".";
			break;
		case "append":
			add_line(document + channel->name, doc, arg);
			action = "Added line.";
			break;
		default:
			return (["{error}": "Invalid subcommand " + cmd]);
	}
	return ([
		"{url}": sprintf("%s/channels/%s/mpn?document=%s",
			persist_config["ircsettings"]->http_address || "http://BOT_ADDRESS",
			channel->name[1..],
			Protocols.HTTP.uri_encode(document),
		),
		"{action}": action,
		"{error}": "",
	]);
}

protected void create(string name) {::create(name);}
