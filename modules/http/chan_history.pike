inherit http_websocket;
inherit annotated;
/* Command history. Maybe other changelogs too in the future.

TODO:
* Filter by command name (drop-down, exact match only)
* Search within the JSON (text search, nonstructured). Space separates multiple search terms?
*/

constant markdown = #"# Command history for $$channel$$

Every time a command is saved, it is added here; commands that are deleted or
replaced remain here. You can view old versions of commands, and (TODO) revert
to them as required.

Created | Command | Output |
--------|---------|--------|-
- | - | Loading....
{: #commandview}
";

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	if (!req->misc->is_mod) return render_template("login.md", (["msg": "moderator privileges"]) | req->misc->chaninfo);
	return render(req, ([
		"vars": (["ws_group": ""]) | G->G->command_editor_vars(req->misc->channel),
		"save_or_login": ("<p><a href=\"#examples\" id=examples>Example and template commands</a></p>"
			"[Save all](:#saveall)"
		),
	]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return 1;}

__async__ mapping get_chan_state(object channel, string group, string|void id) {
	//NOTE: Single-item updates will be triggered by _save_command() or by the database directly.
	//However, they will not call into get_chan_state, as they will already have the necessary state.
	array commands = await(G->G->DB->load_commands(channel->userid, 0, 1));
	foreach (commands, mapping c) {
		if (!c->created->usecs) c->created = Val.null; //Hide the 1970 timestamps representing imported commands with unknown creation times
		c->message = m_delete(c, "content");
	}
	return (["items": commands]);
}

void wscmd_update(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	//TODO: Detect if any changes have been made to the command. If so, don't revert,
	//just create a new command as if it had been freshly saved.
	//TODO: Handle triggers. Somehow.
	if (!msg->cmdname || msg->cmdname == "" || msg->cmdname[0] != '!' || msg->cmdname == "!!trigger") return;
	G->G->DB->revert_command(channel->userid, msg->cmdname[1..], msg->original);
}

protected void create(string name) {::create(name);}
