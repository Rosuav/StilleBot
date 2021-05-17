inherit http_endpoint;
inherit websocket_handler;

inherit builtin_command;
constant hidden_command = 1;
constant require_allcmds = 1;
constant access = "mod";

/*

* MPN - Multi-Part Notes
  - Permissions based on Twitch channel ownership
    - By default, mods can edit, nobody can view. Can "publish" to allow viewing w/o login.
  - Websocket synchronization.
    - Cursor synchronization is going to have to be a thing.
    - Each newline-separated block of text is a separate syncable, like triggers?
  - Markdown parsing and variable interpolation
    - Could allow mods to make full changes, but also non-mod commands can affect variables
    - A published version could be a browser source. Would allow more flexibility than the
      standard Monitor system. Maybe a separate "embed" option to eliminate the surrounds.
  - Example for development: Current goals in Night of the Rabbit
    - Need cake, for which we need fondue (have cheese, have foil)
    - Need light in order to get to leprechaun
    - Coffee for guard?
    - Find jokes
  - Maintain a client-side array of lines with IDs
  - On change:
    - Take textarea value, split into lines
    - If line count > array length:
      - Iterate backwards across both. Count number of trailing matches.
      - Insert null entries into cache array to pad to line count
    - Else if line count < array length:
      - Iterate backwards as above. If matching pair, keep. If nonmatching,
        issue a Delete request for that line ID, decrement difference, and
        carry on, until difference reaches zero.
    - Iterate forwards, issuing Update requests for all that aren't same
    - Server will see an Update w/o an ID and will create a new one
    - Creation of new entries will require a Position marker ("before X"),
      and if omitted, will result in append
    - Make local changes to the lines array immediately.
  - On receipt of change:
    - Ignore textarea value and assume that all changes have gone through
      the onchange already
    - Get textarea cursor position as (lineID, col)
    - Go through all server-provided line changes. If we don't have the ID,
      insert it at the given position, or append.
    - Recalculate desired cursor position based on line ID and column. If
      that line has been deleted, take the next line and column 0. If it's
      been shortened, use end of that line (before the newline).
  - Built-in !chan_mpn that has the ability to create documents (no implicits),
    append lines, and maybe change lines (if only for debugging).

*/

void rebuild_lines(mapping(string:mixed) doc) {
	if (!doc->lines) doc->lines = mkmapping(doc->sequence->id, doc->sequence);
	foreach (doc->sequence; int i; mapping line) line->position = i;
}

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
	if (doc->lines[id]) return doc->lines[id];
	return (["items": doc->sequence]);
}

//TODO: Have a "delete line", and maybe a "rewrite document" that fully starts over
void websocket_cmd_update(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string document] = split_channel(conn->group); if (!channel) return;
	if (!conn->is_mod) return;
	mapping doc = persist_status->path("mpn", channel->name)[document];
	if (!doc) return;
	if (!doc->lines[msg->id]) {
		//New!
		string newid = (string)++doc->lastid;
		mapping line = doc->lines[newid] = (["id": newid, "content": (string)msg->content]);
		//If a "before" ID is given, insert the line before that one. Otherwise, append.
		mapping before = doc->lines[msg->before];
		int pos = before ? before->position : sizeof(doc->sequence);
		doc->sequence = doc->sequence[..pos - 1] + ({line}) + doc->sequence[pos..];
		rebuild_lines(doc);
		send_updates_all(conn->group);
		return;
	}
	mapping l = doc->lines[msg->id];
	if (!msg->content) { //Delete line
		doc->sequence = doc->sequence[..l->position - 1] + doc->sequence[l->position + 1..];
		m_delete(doc->lines, msg->id);
		rebuild_lines(doc);
		send_updates_all(conn->group);
		return;
	}
	l->content = (string)msg->content;
	update_one(conn->group, l->id);
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
	return render_template("chan_mpn.md", ([
		"vars": (["ws_type": "chan_mpn", "ws_group": document + req->misc->channel->name]),
	]) | req->misc->chaninfo);
}

constant command_description = "Create, manage, or link to an MPN document";
constant builtin_name = "MPN document";
constant default_response = ([
	"conditional": "string", "expr1": "{url}", "expr2": "",
	"message": "No such document.",
	"otherwise": "{action} Document can be found at: {url}",
]);
constant vars_provided = ([
	"{action}": "Action performed (if any)",
	"{url}": "URL to the manipulated document, blank if error",
]);

mapping|Concurrent.Future message_params(object channel, mapping person, string param)
{
	write("message_params(channel %O, person %O, %O)\n", channel->name, person->user, param);
	if (param == "") return (["{url}": ""]); //TODO: Give a help message?
	sscanf(param, "%s %s", string cmd, string arg);
	mapping doc;
	if (cmd == "create" && arg && arg != "") {
		doc = persist_status->path("mpn", channel->name, arg);
		if (!doc->sequence) doc->sequence = ({ });
		m_delete(doc, "lines"); rebuild_lines(doc);
		persist_status->save();
	}
	else if (cmd == "delete" && arg && arg != "") {
		m_delete(persist_status->path("mpn", channel->name), arg);
		persist_status->save();
	}
	else {
		doc = persist_status->path("mpn", channel->name)[arg];
		if (!doc) return (["{url}": ""]); //TODO: Error message?
	}
	return ([
		"{url}": "https://......./",
		"{action}": "",
	]);
}

protected void create(string name) {::create(name);}
