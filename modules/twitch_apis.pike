//Transform slash commands (other than /me) into API calls

/* Scopes listed but not implemented:
/ban, /unban, /timeout, /untimeout
https://dev.twitch.tv/docs/api/reference/#ban-user
/clear
https://dev.twitch.tv/docs/api/reference/#delete-chat-messages
/commercial
https://dev.twitch.tv/docs/api/reference/#start-commercial
/followers, /followersoff, /slow, /slowoff, /subscribers, /subscribersoff, /uniquechat, /uniquechatoff
https://dev.twitch.tv/docs/api/reference/#update-chat-settings
/marker
https://dev.twitch.tv/docs/api/reference/#create-stream-marker
/raid, /unraid
https://dev.twitch.tv/docs/api/reference/#start-a-raid
/shield, /shieldoff
https://dev.twitch.tv/docs/api/reference/#update-shield-mode-status
/shoutout
https://dev.twitch.tv/docs/api/reference/#send-a-shoutout
/vip, /unvip
https://dev.twitch.tv/docs/api/reference/#add-channel-vip
/mod, /unmod
https://dev.twitch.tv/docs/api/reference/#add-channel-moderator
/color
https://dev.twitch.tv/docs/api/reference/#update-user-chat-color
/w (/whisper)
https://dev.twitch.tv/docs/api/reference/#send-whisper

Maybe:
/poll, /deletepoll, /endpoll, /vote, /goal, /prediction (won't open the window, so syntax will differ)

Not currently possible:
/pin
/monitor, /unmonitor, /restrict, /unrestrict
/gift (probably never possible)
*/
mapping scopes = ([
	"channel:edit:commercial": "Run ads (broadcaster only)",
	"channel:manage:broadcast": "Configure broadcast incl markers (editor only)",
	"channel:manage:moderators": "Add/remove mod swords (broadcaster only)",
	"channel:manage:raids": "Go raiding (broadcaster only)",
	"channel:manage:vips": "Add/remove VIP badges (broadcaster only)",
	"moderator:manage:announcements": "Send announcements",
	"moderator:manage:banned_users": "Ban/timeout/unban users",
	"moderator:manage:chat_messages": "Delete individual chat messages",
	"moderator:manage:chat_settings": "Set/remove chat restrictions eg slow mode",
	"moderator:manage:shield_mode": "Engage/disengage shield mode",
	"moderator:manage:shoutouts": "Send shoutouts",
	"user:manage:chat_color": "Change chat color",
	"user:manage:whispers": "Send whispers (requires phone auth)",
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
mixed announceblue(object c, string v, string m, mapping t) {return announce(c, v, m, t, "blue");}
@"moderator:manage:announcements":
mixed announcegreen(object c, string v, string m, mapping t) {return announce(c, v, m, t, "green");}
@"moderator:manage:announcements":
mixed announceorange(object c, string v, string m, mapping t) {return announce(c, v, m, t, "orange");}
@"moderator:manage:announcements":
mixed announcepurple(object c, string v, string m, mapping t) {return announce(c, v, m, t, "purple");}

continue Concurrent.Future chat_settings(object channel, string voiceid, string msg, mapping tok, string field, mixed val) {
	mapping ret = yield(twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/chat/settings?broadcaster_id=%d&moderator_id=%s",
		channel->userid, voiceid),
		(["Authorization": "Bearer " + tok->token]),
		(["method": "PATCH", "json": ([field: val])]),
	));
}

@"moderator:manage:chat_settings":
mixed emoteonly(object c, string v, string m, mapping t) {return chat_settings(c, v, m, t, "emote_mode", Val.true);}
@"moderator:manage:chat_settings":
mixed emoteonlyoff(object c, string v, string m, mapping t) {return chat_settings(c, v, m, t, "emote_mode", Val.false);}

//Returns 0 if it sent the message, otherwise a reason code.
//Yes, the parameter order is a bit odd; it makes filtering by this easier.
string send_chat_command(string msg, object channel, string voiceid) {
	sscanf(msg, "/%[^ ] %s", string cmd, string param);
	if (!need_scope[cmd]) return "not a command";
	mapping tok = persist_status["voices"][voiceid];
	if (!voiceid || voiceid == "0") {
		voiceid = (string)G->G->bot_uid;
		mapping config = persist_config["ircsettings"];
		sscanf(config["pass"] || "", "oauth:%s", string pass);
		tok = (["token": pass, "scopes": config->scopes || ({"whispers:edit"})]);
	}
	if (!has_value(tok->scopes, need_scope[cmd])) return "no perms";
	spawn_task(this[cmd](channel, voiceid, param || "", tok));
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
	//send_chat_command("/announce This is an announcement from the bot!", G->G->irc->channels["#rosuav"], 0);
	//send_chat_command("/announce This is an announcement from Mustard Mine!", G->G->irc->channels["#rosuav"], "279141671");
}
