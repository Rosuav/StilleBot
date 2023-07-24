inherit http_endpoint;
inherit annotated;
inherit builtin_command;

constant markdown = "# Emote grid\n\n<div id=grid></div>";

@retain: mapping built_emotes = ([]);

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req) {
	mapping info = built_emotes[req->variables->code];
	if (!info) return 0; //TODO: Better page
	return render_template(markdown, ([
		"vars": (["emotedata": info]),
		"js": "emotegrid",
	]));
}

continue string make_emote(string emoteid, string|void channel) {
	string code = sprintf("%024x", random(1<<96)); //TODO: check for collisions
	mapping info = built_emotes[code] = (["emoteid": emoteid, "channel": channel]);
	return code;
}

constant builtin_name = "Emote grid";
constant builtin_param = ({"Emote", "Channel name"});
constant vars_provided = ([
	"{error}": "Error message, if any",
	"{code}": "Unique code for the generated grid",
	"{url}": "Web address where the grid can be viewed",
]);

continue mapping|Concurrent.Future message_params(object channel, mapping person, string|array param) {
	//PROBLEM: Channel point redemptions don't actually include emote data. So having this
	//as a points reward is actually problematic.
	if (!person->emotes) return (["{error}": "Unfortunately this doesn't work as a channel point redemption (currently)."]);
	if (!sizeof(person->emotes)) return (["{error}": "Please include an emote to build a grid of."]);
	if (stringp(param)) param /= " ";
	string channame = sizeof(param) > 1 && param[1]; //TODO: Support "channelname emoteGoesHere" as well
	string code = yield(make_emote(person->emotes[0][0], channame));
	return (["{code}": code, "{url}": sprintf("%s/emotegrid?code=%s",
		persist_config["ircsettings"]->http_address || "http://BOT_ADDRESS",
		code,
	)]);
}

protected void create(string name) {::create(name);}
