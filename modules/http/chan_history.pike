inherit http_websocket;
inherit annotated;
/* Command history. Maybe other changelogs too in the future.

TODO:
* Filter by command name (drop-down, exact match only)
* Search within the JSON (text search, nonstructured). Space separates multiple search terms?
*/

constant markdown = #"# Command history for $$channel$$

Every time a command is saved, it is added here; commands that are deleted or
replaced remain here. You can view old versions of commands, and revert
to them as required.

* Show command: <select id=pickcommand><option value=''>Loading...</select>
* Search for: <input id=filter size=30>
* <label><input type=checkbox id=currentonly> Current versions only</label>
{:#filters}

Created | Command | Output |
--------|---------|--------|-
- | - | Loading....
{: #commandview}

> ### Changes
>
> <div id=diff></div>
>
> [Close](:.dialog_close)
{: tag=dialog #diffdlg}

<style>
#filters {
	display: flex;
	list-style-type: none;
	gap: 2em;
}
/* One line inside the diff */
#diff div {
	white-space: pre;
}
#diff div::before {
	display: inline-block;
	width: 1em;
	content: \"\\00a0\";
}
.diff-context { }
.diff-removed {color: #a00;}
#diff .diff-removed::before {content: \"-\";}
.diff-added {color: green;}
#diff .diff-added::before {content: \"+\";}
.diff-location {color: #088; display: none;} /* With max context, the location markers aren't necessary */
.diff-unknown {color: white; background: rebeccapurple;} /* Make it really obvious if something misparses */
</style>
";

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	if (!req->misc->is_mod) return render_template("login.md", (["msg": "moderator privileges"]) | req->misc->chaninfo);
	return render(req, ([
		"vars": (["ws_group": ""]),
		"save_or_login": ("<p><a href=\"#examples\" class=opendlg data-dlg=templates>Example and template commands</a></p>"
			"[Save all](:#saveall)"
		),
	]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return 1;}

__async__ mapping get_chan_state(object channel, string group, string|void id) {
	//NOTE: Single-item updates will be triggered by _save_command() or by the database directly.
	//However, they will not call into get_chan_state, as they will already have the necessary state.
	array commands = await(G->G->DB->load_commands(channel->userid, 0, 1));
	mapping latest = ([]); //For providing the previd linkages, which otherwise would be tricky
	foreach (commands, mapping c) {
		if (!c->created->usecs) c->created = Val.null; //Hide the 1970 timestamps representing imported commands with unknown creation times
		c->message = m_delete(c, "content");
		if (mapping next = latest[c->cmdname]) next->previd = c->id;
		else c->is_current = 1;
		latest[c->cmdname] = c;
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

__async__ mapping wscmd_diff(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	//Diff the MustardScript versions of two commands
	//Ignores leading/trailing whitespace on the lines, and (TODO) autoreplaces deprecated
	//builtins with the new ones to avoid spurious diffs there too.
	array sel = await(G->G->DB->query_ro("select cmdname, content from stillebot.commands where twitchid = :twitchid and id = :id",
		(["twitchid": channel->userid, "id": msg->id])));
	if (!sizeof(sel)) return (["error": "Invalid command ID"]); //Or wrong channel but don't even bother mentioning that
	string cmdname = sel[0]->cmdname;
	echoable_message old, new;
	string oldid, newid;
	if (msg->against) {
		//Compare this against an older message
		new = sel[0]->content; newid = msg->id;
		//Not worth folding these two queries into one. Also, if you fiddle with the IDs, you
		//could make this toss an exception - I don't really care.
		old = await(G->G->DB->query_ro("select content from stillebot.commands where twitchid = :twitchid and id = :id",
			(["twitchid": channel->userid, "id": msg->against])))[0]->content;
		oldid = msg->against;
	} else {
		//Compare current against this. The current one might be active, but might not.
		new = channel->commands[cmdname];
		newid = "<current>"; //TODO: Give the actual ID
		//If it isn't on the channel object, there's no current command, but grab the most recent anyway.
		//(Note that, in some cases, it would be more correct to say "current is nothingness" - esp special
		//triggers - but it's more useful to compare against the latest non-empty version of the command.)
		if (!new) new = await(G->G->DB->query_ro("select content from stillebot.commands "
			"where twitchid = :twitchid and cmdname = :cmdname order by created desc limit 1",
			(["twitchid": channel->userid, "cmdname": cmdname])))[0]->content;
		old = sel[0]->content; oldid = msg->id;
	}
	//Next: Synthesize MustardScript for each command
	old = G->G->mustard->make_mustard(old);
	new = G->G->mustard->make_mustard(new);
	//Finally, compare the two. We're using enormous context (commands won't usually be 100 lines, let
	//alone thousands) so there'll be some scrolling but you should generally see the entire context.
	//We then parse out the line prefixes and make it easy for the front end to render.
	array(string) diff = await(unified_diff(old, new, ({"-b", "-u5000"}))) / "\n";
	if (sizeof(diff) <= 1) return (["cmd": "diff", "oldid": oldid, "newid": newid, "diff": ({(["text": "Identical!", "style": "context"])})]);
	diff = diff[2..]; //Rip off the first two lines which identify the "files" (actually just pipes)
	array lines = ({ });
	foreach (diff, string line) {
		//Figure out what kind of line this is, and inform the front end accordingly.
		if (line == "") continue; //Do we need interior blank lines? The diff will always end with one.
		string style = ([
			' ': "context",
			'+': "added",
			'-': "removed",
			'@': "location",
		])[line[0]] || "unknown";
		if (style == "location") line = "@" + line; //Slip an extra character in there for these lines to retain the "@@" symmetry
		lines += ({([
			"text": line[1..],
			"style": style,
		])});
	}
	return (["cmd": "diff", "oldid": oldid, "newid": newid, "diff": lines]);
}

protected void create(string name) {::create(name);}
