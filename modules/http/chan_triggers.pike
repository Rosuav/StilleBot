inherit http_endpoint;

string respstr(mapping|string resp) {return Parser.encode_html_entities(stringp(resp) ? resp : resp->message);}

constant TEMPLATES = ({
	"hello | world!",
	"Kappa | MiniK Kappa KappaHD ZombieKappa",
	"buy-follows | /ban $$",
});

//Due to the nature of triggers, templates ALL use the advanced view.
constant COMPLEX_TEMPLATES = ([
	"hello": ([
		"casefold": "on",
		"conditional": "contains",
		"expr1": "hello", "expr2": "%s",
		"message": "world!",
	]),
	"Kappa": ([
		"conditional": "regexp",
		"expr1": "\\<Kappa\\>", "expr2": "%s",
		"message": "MiniK Kappa KappaHD ZombieKappa",
	]),
	"buy-follows": ([
		"conditional": "number",
		"expr1": "{@buyfollows} && {@mod} == 0",
		"message": "/ban $$",
	]),
]);

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	array commands = ({ });
	if (!req->misc->is_mod) {
		//Read-only view is a bit of a hack - it just doesn't say it's loading.
		return render_template("chan_triggers.md", ([
			"loadingmsg": "Restricted to moderators only",
			"save_or_login": "", "templates": "- | -",
		]) | req->misc->chaninfo);
	}
	return render_template("chan_triggers.md", ([
		"vars": ([
			"ws_type": "chan_commands", "ws_group": "!!trigger" + req->misc->channel->name,
			"ws_code": "chan_triggers", "complex_templates": COMPLEX_TEMPLATES,
			"builtins": G->G->commands_builtins,
		]),
		"loadingmsg": "Loading...",
		"templates": TEMPLATES * "\n",
		"save_or_login": "<p><a href=\"#examples\" id=examples>Create new trigger</a></p>",
	]) | req->misc->chaninfo);
}
