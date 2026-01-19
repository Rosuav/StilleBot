//NOTE: This technically violates the unique-in-two rule with imgbuilder, but both are
//undocumented pages. Not sure if this is worth the hassle of differentiating.
inherit http_websocket;

constant markdown = #"# Import from other services - $$channel$$

## DeepBot commands

1. Open DeepBot
2. Click on the tab \"channel commands\"
3. At the top under \"selection\", select \"all\"
3. Right click anywhere in the list of commands
4. Choose \"export commands\"
5. Paste the result here
6. Click \"Translate\" to see them as Mustard Mine commands.

* <textarea id=deepbot_commands></textarea>
* <label><input type=checkbox id=include_groups> Include group names as comments</label>
* <button type=button id=import_deepbot>Translate</button>
* <div id=deepbot_results></div>
{:#deepbot}

> ### Import commands
>
> <div id=import_description></div>
>
> [Import](:#confirmimport) [Cancel](:.dialog_close)
{: tag=dialog #importconfirmdlg}

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
#import_description {
	max-width: 50em;
}
.warning {
	border: 1px solid yellow;
	background: #ffdd99;
}
.warning details {
	margin: 0 5em;
	padding: 0.5em 1em;
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
	"APITarget": Val.false, //Can't see this in the screen shot???
	"CommandChaningRunAsAdmin": Val.false, //Don't know what "Admin Access" on command chaining does
	//Managing OBS from Mustard Mine is more complicated and will require careful permissions.
	"OBSRemoteAction": 0,
	"OBSRemoteEnabled": Val.false,
	"OBSRemoteSceneName": "",
	//Widgets like this might be able to be translated into Labels or other types of monitor,
	//but it's not likely to be worth importing unless someone has a bunch of them.
	"OnScreenWidgetAnimMode": 0,
	"OnScreenWidgetEnabled": Val.false,
	"OnScreenWidgetImageLink": "",
	"OnScreenWidgetMessage": "",
	"OnScreenWidgetName": "",
	"OnScreenWidgetTitle": "",
	//VIP status is a Deepbot-specific flag, not related to the Pink Diamond of Power
	"VIPModAddDays": 30,
	"VIPModEnabled": Val.false,
	"VIPModIfVIPB": 0,
	"VIPModIfVIPG": 0,
	"VIPModIfVIPS": 0,
	"VIPModIfViewer": 0,
	"accessDeniedMsg": "", //Implementing this would require making the command open to all, but having an if {@vip} or {@mod} check
	//We don't have the channel points system so these costs don't translate well.
	"costAll": 0,
	"costEnabled": Val.false,
	"costVIPB": 0,
	"costVIPG": 0,
	"costVIPMod": 0,
	"costVIPS": 0,
	"costVIPStreamer": 0,
	"costVIPViewer": 0,
	//We only handle Twitch chat so these are likely irrelevant.
	"disableChanAccess": Val.false,
	"disableDiscordAccess": Val.false,
	"disableWhisperAccess": Val.false,
	//No sound file support here
	"soundFile": "",
	"soundVolume": 100,
	"isSoundVolumeSet": Val.true,
	//Do we need these?
	"minHours": 0,
	"minPoints": 0,
	"noPointsMsg": "",
	"runAsBot": Val.false,
	"runAsUserElevated": Val.false,
	"startsWithEx": Val.false,
]);
//DeepBot has some command settings that aren't interesting, mostly statistical.
multiset deepbot_uninteresting = (<
	"lastUsed", "counter", "lastModified",
	"countdown", //There's a field for @Countdown@ that might be able to be used for things like Labels do??
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
object special_command_variable = Regexp.PCRE.StudiedWidestring("@([A-Za-z0-9]+)@(\\[.+?\\])?");
__async__ mapping wscmd_deepbot_translate(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	array commands = Array.arrayify(msg->commands); //Generally we expect an array (even if of just one), but allow the outer brackets to be omitted.
	mapping unknowns = ([]);
	mapping commands_by_name = ([]);
	mapping(string:array) warnings = ([]);
	foreach (commands, mapping cmd) {
		//Attempt to interpret the command into native. Anything we don't understand,
		//put a comment at the top of the script. We'll turn this into MustardScript for the
		//display (or maybe call on the command GUI??).
		string cmdname = m_delete(cmd, "command");
		if (channel->commands[cmdname[1..]]) warnings[cmdname] += ({"Command already exists, and will be overwritten by the import"});
		string text = m_delete(cmd, "message") || "";
		array(string) pre_comments = ({ }), post_comments = ({ });
		//If the message matches "%*s@%[A-Za-z0-9]@", check for special command variables and translate those too
		//First, some simple and easy translations.
		text = replace(text, ([
			"@target@": "{param}", //Is this actually the same, or does target have other behaviours?
			"@user@": "{username}",
		]));
		//Then the more complicated ones. Some of them are parameterized. These may require wrapping in
		//a builtin or other layer of structure; omit the "message" key and keep going with the parsing.
		array layers = ({ });
		text = special_command_variable->replace(text) {[string all, string var, string args] = __ARGS__;
			switch (var) {
				case "sendstreamermsg":
					//If you use "@sendstreamermsg@[text]" it will send "text" as the streamer.
					//I've no idea what happens if there's more text before/after that though.
					//For simplicity, assume there won't be, and just return the original text.
					layers += ({(["voice": (string)channel->userid])});
					return String.trim(args[1..<1]); //Strip off the square brackets and any whitespace just inside them
				case "uptime":
					layers += ({(["builtin": "uptime"])});
					return "{uptime|english}";
				//case "followdate": //Maybe support this one?
				default:
					pre_comments += ({"WARNING: Unknown special variable @" + var + "@"});
					warnings[cmdname] += ({"Unknown special variable @" + var + "@"});
			}
			return all;
		};
		echoable_message body = text;
		foreach (layers, mapping l) body = l | (["message": text]);

		mapping flags = ([]);
		mapping ret = (["cmdname": cmdname]);
		if (!cmdname) continue; //Not sure how to link this back to the JSON with no command name.
		//DeepBot maintains statistics, which we won't worry about.
		cmd -= deepbot_uninteresting;

		if (m_delete(cmd, "status") == Val.false) ret->inactive = 1;
		if (m_delete(cmd, "hideFromCmdList")) flags->visibility = "hidden";
		string rew = m_delete(cmd, "pointsRewards") || "";

		//I suspect that these are not storing the ID but the label, so there would need to be a translation.
		//Also, Mustard Mine might need to take over the reward.
		if (rew != "") pre_comments += ({"POINTS REWARDS: " + rew});

		//Wrap the body in cooldown checks if required. We wrap first in a user cooldown (if present), then
		//in the global (if present), so that a global cooldown message takes precedence over a user one.
		//The cooldown and message fields will be unconditionally removed, but a message without a numeric
		//cooldown will be discarded.
		string cdmsg = m_delete(cmd, "userCooldownMsg") || "";
		if (int cd = m_delete(cmd, "userCooldown"))
			body = (["conditional": "cooldown", "cdlength": cd, "message": body, "otherwise": cdmsg, "cdname": "*"]);
		cdmsg = m_delete(cmd, "cmdCooldownMsg") || "";
		if (int cd = m_delete(cmd, "cooldown"))
			body = (["conditional": "cooldown", "cdlength": cd, "message": body, "otherwise": cdmsg]);

		if (int access = m_delete(cmd, "accessLevel")) {
			//TODO: What are the other access fields and are they relevant?
			if (access == 8) flags->access = "mod";
		}

		if (!msg->include_groups) m_delete(cmd, "group"); //The group becomes a comment, if and only if you wanted them kept.
		foreach (sort(indices(deepbot_comments)), string key) {
			string val = m_delete(cmd, key) || "";
			if (val != "") pre_comments = ({deepbot_comments[key] + ": " + val});
		}

		//Command chaining is the way DeepBot does multi-message commands. However, the chained-to
		//commands are themselves valid. Do we need an option to retain them?
		ret->chainto = m_delete(cmd, "CommandChaningCmdName");
		ret->chaindelay = m_delete(cmd, "CommandChaningRunAfter");
		//Handle these in a second pass, since we can't know whether the chained-to command is earlier
		//or later in the import file

		//Scan the unknowns and get rid of them if, and only if, they are at their defaults.
		foreach (deepbot_unknowns; string key; mixed expected) {
			mixed actual = m_delete(cmd, key);
			if (actual != expected) post_comments += ({sprintf("UNKNOWN: %s -> %O expected %O", key, actual, expected)});
		}

		//Okay. Anything left is unknown; add them as comments at the end.
		foreach (sort(indices(cmd)), string key) {
			post_comments += ({sprintf("UNKNOWN: %s -> %O", key, cmd[key])});
			if (!has_value(unknowns[key] || ({ }), cmd[key])) unknowns[key] += ({cmd[key]});
		}
		body = (["dest": "//", "message": pre_comments[*]]) + ({body}) + (["dest": "//", "message": post_comments[*]]);
		ret->body = flags | (["message": body]);
		commands_by_name[cmdname] = ret;
	}
	//Second pass: Grab all command chainings and merge them into single commands.
	//Heuristically, we judge that commands are to be merged if the subsequent ones have names
	//that begin with the initial one, so !rc -> !rc2 -> !rc3 is all combined, but !adbreak -> !ad
	//will not be merged, so those will be two commands with an explicit chain-to.
	foreach (sort(indices(commands_by_name)), string cmdname) {
		mapping cmd = commands_by_name[cmdname];
		if (!cmd->?chainto) continue; //cmd could be null if this was already processed as a chained command
		mapping next = m_delete(commands_by_name, cmd->chainto);
		int chaindelay = cmd->chaindelay;
		multiset(string) comments = (<>);
		foreach (cmd->body->message, mapping msg) if (mappingp(msg) && msg->dest == "//") comments[msg->message] = 1;
		while (next) {
			if (!has_prefix(next->cmdname, cmdname)) {
				commands_by_name[next->cmdname] = next; //Reinstate it so it can be reviewed subsequently
				//Chain to it. To my knowledge, Deepbot has no way to add parameters to the chained
				//command, so the "message" will always be blank.
				cmd->body->message += ({(["dest": "/chain", "target": next->cmdname, "message": "", "delay": chaindelay])});
				break;
			}
			//Duplicated comments in both the base command and the chained-to command are redundant.
			foreach (next->body->message; int i; mapping msg) if (mappingp(msg) && msg->dest == "//") {
				if (comments[msg->message]) next->body->message[i] = 0;
				comments[msg->message] = 1;
			}
			if (chaindelay) cmd->body->message += (["delay": chaindelay, "message": next->body->message - ({0})]);
			else cmd->body->message += next->body->message - ({0});
			chaindelay = next->chaindelay;
			next = m_delete(commands_by_name, next->chainto);
		}
	}
	//Third pass: Translate everything into MustardScript for compactness.
	foreach (commands_by_name; string cmdname; mapping cmd) {
		cmd->mustard = G->G->mustard->make_mustard(cmd->body);
		m_delete(cmd, "chainto");
		m_delete(cmd, "chaindelay");
		m_delete(cmd, "body"); //Unless we want to keep it so the front end can show it graphically?
	}
	if (sizeof(unknowns)) werror("DeepBot import unknowns: %O\n", unknowns);
	array xlat = values(commands_by_name); sort(indices(commands_by_name), xlat);
	return (["cmd": "translated", "commands": xlat, "warnings": warnings]);
}
