inherit http_endpoint;
inherit enableable_module;

constant TEMPLATES = ({
	"Text | Simple text, finds any string of letters",
	"RegExp | Word trigger - \\&lt;some-word\\&gt;",
	"buy-follows | Automatically ban bots that ask you to buy followers",
	"Reward lister | Identify messages that come from custom rewards",
	"Reward trigger | Use the ID from the reward lister to react to a reward",
});

//Due to the nature of triggers, templates ALL use the advanced view.
constant COMPLEX_TEMPLATES = ([
	"Text": ([
		"casefold": "on",
		"conditional": "contains",
		"expr1": "hello", "expr2": "%s",
		"message": "Hello to you too!!",
	]),
	"RegExp": ([
		"conditional": "regexp",
		"expr1": "\\<Kappa\\>", "expr2": "%s",
		"message": "MiniK Kappa KappaHD ZombieKappa",
	]),
	"buy-follows": ([
		"conditional": "number",
		"expr1": "{@buyfollows} && {@mod} == 0",
		"message": "/ban $$",
	]),
	"Reward lister": ([
		"conditional": "contains",
		"expr1": "-", "expr2": "{rewardid}",
		"message": "Reward ID: {rewardid}",
	]),
	"Reward trigger": ([
		"conditional": "contains",
		"expr1": "PASTE-ID-HERE", "expr2": "{rewardid}",
		"message": "Custom reward selected! (Use Reward Lister to find the ID)",
	]),
]);

constant ENABLEABLE_FEATURES = ([
	"buy-follows": ([
		"description": "Automatically ban those bots that try to sell you followers",
		"response": COMPLEX_TEMPLATES["buy-follows"],
	]),
]);

string get_trig_id(object channel, string kwd) {
	echoable_message response = channel->commands["!trigger"];
	mapping info = ENABLEABLE_FEATURES[kwd]->?response; if (!info) return 0;
	if (arrayp(response)) foreach (response, mapping trig) {
		if (trig->conditional == info->conditional &&
			(trig->expr1||"") == (info->expr1||"") &&
			(trig->expr2||"") == (info->expr2||""))
				return trig->id;
	}
}
int can_manage_feature(object channel, string kwd) {return get_trig_id(channel, kwd) ? 2 : 1;}

void enable_feature(object channel, string kwd, int state) {
	mapping info = ENABLEABLE_FEATURES[kwd]; if (!info) return;
	//Hack: Call on the normal commands updater to add a trigger
	G->G->websocket_types->chan_commands[state ? "websocket_cmd_update" : "websocket_cmd_delete"](([
		"group": "!!trigger" + channel->name,
		"sock": (["send_text": lambda(mixed msg) { }]), //Ignore a response being sent back
	]), ([
		"cmdname": get_trig_id(channel, kwd) || "",
		"response": info->response,
	]));
}

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	array commands = ({ });
	if (!req->misc->is_mod) {
		//Read-only view is a bit of a hack - it just doesn't say it's loading.
		return render_template("chan_triggers.md", ([
			"loadingmsg": "Restricted to moderators only",
			"templates": "- | -",
		]) | req->misc->chaninfo);
	}
	return render_template("chan_triggers.md", ([
		"vars": ([
			"ws_type": "chan_commands", "ws_group": "!!trigger" + req->misc->channel->name,
			"ws_code": "chan_triggers",
		]) | G->G->command_editor_vars(req->misc->channel),
		"loadingmsg": "Loading...",
		"templates": TEMPLATES * "\n",
		"save_or_login": "[Save all](:#saveall)\n<p><a href=\"#examples\" id=examples>Create new trigger</a></p>",
	]) | req->misc->chaninfo);
}

protected void create(string name) {::create(name);}
