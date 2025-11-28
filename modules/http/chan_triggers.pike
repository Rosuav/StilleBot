inherit http_endpoint;
inherit enableable_module;

constant markdown = #{# Triggered responses for $$channel$$

Every chat message is checked against these triggers (in order). All matching
responses will be sent. Unlike [commands](commands), triggers do not require
that the command name be at the start of the message; they can react to any
word or phrase anywhere in the message. They can also react to a variety of
other aspects of the message, including checking whether the person is a mod,
by using appropriate conditionals. Any response can be given, as per command
handling.

To respond to special events such as subscriptions, see [Special Triggers](specials).

Channel moderators may add and edit these responses below.

ID          | Response | -
------------|----------|----
-           | $$loadingmsg$$
{: #triggers}

[Add trigger](:#addtrigger)

$$save_or_login||$$

<style>
table {width: 100%;}
th, td {width: 100%;}
dialog td:last-of-type {width: 100%;}
th:first-of-type, th:last-of-type, td:first-of-type, td:last-of-type {width: max-content;}
td:nth-of-type(2n+1):not([colspan]) {white-space: nowrap;}
code {overflow-wrap: anywhere;}
.gap {height: 1em;}
td ul {margin: 0;}
</style>
#};

constant ENABLEABLE_FEATURES = ([
	"buy-follows": ([
		"description": "Automatically ban those bots that try to sell you followers",
		"response": ([
			"conditional": "number",
			"expr1": "{@buyfollows} && {@mod} == 0",
			"message": "/ban $$ Atttempting to sell followers.",
		]),
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
	G->G->update_command(channel, "!!trigger", get_trig_id(channel, kwd) || "", state ? info->response : "");
	//HACK: When you enable buy-follows, also enable the special trigger.
	if (kwd == "buy-follows") G->G->update_command(channel, "!!", "!suspiciousmsg", state ? info->response : "");
}

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	//Read-only view is a bit of a hack - it just doesn't say it's loading.
	if (!req->misc->is_mod) return render_template(markdown, ([
		"loadingmsg": "Restricted to moderators only",
	]) | req->misc->chaninfo);
	return render_template(markdown, ([
		"vars": ([
			"ws_type": "chan_commands", "ws_group": "!!trigger" + req->misc->channel->name,
			"ws_code": "chan_triggers",
		]),
		"loadingmsg": "Loading...",
		"save_or_login": "[Save all](:#saveall)",
	]) | req->misc->chaninfo);
}

protected void create(string name) {::create(name);}
