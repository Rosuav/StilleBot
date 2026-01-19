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
__async__ mapping wscmd_deepbot_translate(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	werror("Requesting translation\n");
	array commands = Array.arrayify(msg->commands); //Generally we expect an array (even if of just one), but allow the outer brackets to be omitted.
	array xlat = ({ });
	mapping unknowns = ([]);
	foreach (commands, mapping cmd) {
		//Attempt to interpret the command into native. Anything we don't understand,
		//put a comment at the top of the script. We'll turn this into MustardScript for the
		//display (or maybe call on the command GUI??).
		echoable_message body = m_delete(cmd, "message") || "";
		array(string) pre_comments = ({ }), post_comments = ({ });
		//TODO: If the message matches "%*s@%[A-Za-z0-9]@", check for special command variables and translate those too
		mapping flags = ([]);
		string cmdname = m_delete(cmd, "command");
		if (!cmdname) xlat += ({(["error": "No command name"])}); //Not sure how to link this back to the JSON with no command name.
		//DeepBot maintains statistics, which we won't worry about.
		cmd -= deepbot_uninteresting;

		if (m_delete(cmd, "status") == Val.false) continue; //TODO: Have an option to include, or at least mention, disabled commands
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

		foreach (sort(indices(deepbot_comments)), string key) {
			string val = m_delete(cmd, key) || "";
			if (val != "") pre_comments = ({deepbot_comments[key] + ": " + val});
		}

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
		xlat += ({(["cmdname": cmdname, "mustard": G->G->mustard->make_mustard(flags | (["message": body]))])});
	}
	werror("Unknowns: %O\n", unknowns);
	return (["cmd": "translated", "commands": xlat]);
}
