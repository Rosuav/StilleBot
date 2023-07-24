inherit http_endpoint;
inherit annotated;
inherit builtin_command;

constant markdown = "# Emote grid";

@retain: mapping built_emotes = ([]);

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req) {
	mapping info = built_emotes[req->variables->code];
	if (!info) return 0; //TODO: Better page
	return render_template(markdown, ([
		"vars": (["emotedata": info]),
	]));
}

void make_emote(int emoteid, string|void channel) {
	
}

constant builtin_name = "Emote grid";
constant builtin_param = ({"Emote", "Channel name"});
constant vars_provided = ([
	"{error}": "Error message, if any",
	"{code}": "Unique code for the generated grid",
	"{url}": "Web address where the grid can be viewed",
]);

continue mapping|Concurrent.Future message_params(object channel, mapping person, string|array param) {
	return (["{error}": "Not yet implemented"]);
}

protected void create(string name) {::create(name);}
