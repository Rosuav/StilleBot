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

//DeepBot has a number of command attributes whose meanings I do not know, but which
//in all commands that I've seen have had the same value. If any command has a DIFFERENT
//value, report it, but otherwise, these values are considered uninteresting. Some of
//these have fairly intuitive meanings, but they're here since they correlate with
//features that are impossible for StilleBot to support, and so if they are at non-default
//settings, they need to be reported.
constant deepbot_unknowns = ([
	"APITarget": Val.false,
	"CommandChaningRunAsAdmin": Val.false,
	"OBSRemoteAction": 0,
	"OBSRemoteEnabled": Val.false,
	"OBSRemoteSceneName": "",
	"OnScreenWidgetAnimMode": 0,
	"OnScreenWidgetEnabled": Val.false,
	"OnScreenWidgetImageLink": "",
	"OnScreenWidgetMessage": "",
	"OnScreenWidgetName": "",
	"OnScreenWidgetTitle": "",
	"VIPModAddDays": 30,
	"VIPModEnabled": Val.false,
	"VIPModIfVIPB": 0,
	"VIPModIfVIPG": 0,
	"VIPModIfVIPS": 0,
	"VIPModIfViewer": 0,
	"accessDeniedMsg": "",
	"costAll": 0,
	"costEnabled": Val.false,
	"costVIPB": 0,
	"costVIPG": 0,
	"costVIPMod": 0,
	"costVIPS": 0,
	"costVIPStreamer": 0,
	"costVIPViewer": 0,
	"disableChanAccess": Val.false,
	"disableDiscordAccess": Val.false,
	"disableWhisperAccess": Val.false,
	"isSoundVolumeSet": Val.true,
	"minHours": 0,
	"minPoints": 0,
	"noPointsMsg": "",
	"runAsBot": Val.false,
	"runAsUserElevated": Val.false,
	"soundFile": "",
	"soundVolume": 100,
	"startsWithEx": Val.false,
]);
//DeepBot has some command settings that aren't interesting, mostly statistical.
multiset deepbot_uninteresting = (<
	"lastUsed", "counter", "lastModified",
	"countdown", //No idea what this means. It's the date/time of something, but what? Maybe creation date???
>);
//Some things can just become comments. They're not essential but they could be of value.
mapping deepbot_comments = ([
	"description": "Description",
	"group": "Group",
]);

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
	mapping unknowns = ([]);
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
		cmd -= deepbot_uninteresting;

		if (m_delete(cmd, "status") == Val.false) continue; //TODO: Have an option to include, or at least mention, disabled commands
		if (m_delete(cmd, "hideFromCmdList")) flags->visibility = "hidden";

		foreach (sort(indices(deepbot_comments)), string key) {
			string val = m_delete(cmd, key) || "";
			if (val != "") body = ({(["dest": "//", "message": deepbot_comments[key] + ": " + val])}) + body;
		}

		//Scan the unknowns and get rid of them if, and only if, they are at their defaults.
		foreach (deepbot_unknowns; string key; mixed expected) {
			mixed actual = m_delete(cmd, key);
			if (actual != expected) body += ({(["dest": "//", "message": sprintf("UNKNOWN: %s -> %O expected %O", key, actual, expected)])});
		}

		//Okay. Anything left is unknown; add them as comments at the end.
		foreach (sort(indices(cmd)), string key) {
			body += ({(["dest": "//", "message": sprintf("UNKNOWN: %s -> %O", key, cmd[key])])});
			if (!has_value(unknowns[key] || ({ }), cmd[key])) unknowns[key] += ({cmd[key]});
		}
		xlat += ({(["cmdname": cmdname, "mustard": G->G->mustard->make_mustard(flags | (["message": body]))])});
	}
	werror("Unknowns: %O\n", unknowns);
	return (["cmd": "translated", "commands": xlat]);
}
