//NOTE: This technically violates the unique-in-two rule with imgbuilder, but both are
//undocumented pages. Not sure if this is worth the hassle of differentiating.
inherit http_websocket;

constant markdown = #"# Import from other services - $$channel$$

## DeepBot commands

1. Go to DeepBot
2. Find the thing. Do the thing. Copy to clipboard.
3. Paste the result here.

* <textarea id=deepbot_commands></textarea>
* <button type=button id=import_deepbot>Translate</button>
* <div id=deepbot_results></div>
{:#deepbot}

<style>
#deepbot {
	width: 100%;
	list-style-type: none;
	display: flex;
	flex-direction: column;
	padding-left: 0;
}
#deepbot textarea {
	width: 100%;
	height: 20em;
}
</style>

";

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	if (!req->misc->is_mod) return render_template("login.md", (["msg": "moderator privileges"]) | req->misc->chaninfo);
	return render(req, (["vars": (["ws_group": ""])]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return 1;}
__async__ mapping get_chan_state(object channel, string grp, string|void id) {
	return ([]); //Do we even need a websocket here? Maybe it'll be useful for the final import stage.
}
__async__ mapping wscmd_deepbot_translate(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	werror("Requesting translation\n");
	array commands = Array.arrayify(msg->commands); //Generally we expect an array (even if of just one), but allow the outer brackets to be omitted.
	array xlat = ({ });
	foreach (commands, mapping cmd) {
		//Attempt to interpret the command into native. Anything we don't understand,
		//put a comment at the top of the script. We'll turn this into MustardScript for the
		//display (or maybe call on the command GUI??).
		echoable_message body = ({m_delete(cmd, "message") || ""});
		//TODO: If the message matches "%*s@%[A-Za-z0-9]@", check for special command variables and translate those too
		mapping flags = ([]);
		string cmdname = m_delete(cmd, "command");
		if (!cmdname) xlat += ({(["error": "No command name"])}); //Not sure how to link this back to the JSON with no command name.
		//DeepBot maintains statistics, which we won't worry about.
		m_delete(cmd, "lastUsed");
		if (string grp = m_delete(cmd, "group")) body = ({(["dest": "//", "message": "Group: " + grp])}) + body;

		//Okay. Anything left is unknown; add them as comments at the end.
		foreach (sort(indices(cmd)), string key) {
			body += ({(["dest": "//", "message": sprintf("UNKNOWN: %s -> %O", key, cmd[key])])});
		}
		xlat += ({(["cmdname": cmdname, "mustard": G->G->mustard->make_mustard(flags | (["message": body]))])});
	}
	werror("Returning %d messages\n", sizeof(xlat));
	return (["cmd": "translated", "commands": xlat]);
}
