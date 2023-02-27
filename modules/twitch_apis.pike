//Transform slash commands (other than /me) into API calls

mapping scopes = ([
	"moderator:manage:announcements": "Send announcements",
]);

mapping need_scope = ([]); //Filled in by create()

@"moderator:manage:announcements":
continue Concurrent.Future announce(object channel, string voiceid, string msg, mapping tok, string|void color) {
	mapping ret = yield(twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/chat/announcements?broadcaster_id=%d&moderator_id=%s",
		channel->userid, voiceid),
		(["Authorization": "Bearer " + tok->token]),
		(["json": ([
			"message": msg,
			"color": color || "primary",
		])]),
	));
}

@"moderator:manage:announcements":
mixed announceblue(object c, string v, mapping t, string m) {return announce(c, v, m, t, "blue");}
@"moderator:manage:announcements":
mixed announcegreen(object c, string v, mapping t, string m) {return announce(c, v, m, t, "green");}
@"moderator:manage:announcements":
mixed announceorange(object c, string v, mapping t, string m) {return announce(c, v, m, t, "orange");}
@"moderator:manage:announcements":
mixed announcepurple(object c, string v, mapping t, string m) {return announce(c, v, m, t, "purple");}

int(0..1) send_chat_command(object channel, string voiceid, string msg) {
	sscanf(msg, "/%s %s", string cmd, string param);
	if (!cmd || !param || !need_scope[cmd]) return 0;
	mapping tok = persist_status["voices"][voiceid];
	if (!voiceid || voiceid == "0") {
		voiceid = (string)G->G->bot_uid;
		sscanf(persist_config["ircsettings"]["pass"] || "", "oauth:%s", string pass);
		//TODO: Figure out which scopes the bot's primary auth has, rather than assuming all
		tok = (["token": pass, "scopes": indices(scopes)]);
	}
	if (!has_value(tok->scopes, need_scope[cmd])) return 0;
	spawn_task(this[cmd](channel, voiceid, tok, param));
	return 1;
}

protected void create(string name) {
	G->G->voice_additional_scopes = scopes;
	G->G->send_chat_command = send_chat_command;
	foreach (Array.transpose(({indices(this), annotations(this)})), [string key, mixed ann]) {
		if (ann) foreach (indices(ann), mixed anno) {
			if (!scopes[anno]) scopes[anno] = anno; //Ensure that every scope is listed in the description mapping
			need_scope[key] = anno;
		}
	}
	//send_chat_command(G->G->irc->channels["#rosuav"], 0, "/announce This is an announcement from the bot!");
	//send_chat_command(G->G->irc->channels["#rosuav"], "279141671", "/announce This is an announcement from Mustard Mine!");
}
