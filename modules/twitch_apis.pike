//Transform slash commands (other than /me) into API calls

/* Scopes listed but not implemented:
/commercial
https://dev.twitch.tv/docs/api/reference/#start-commercial
/marker
https://dev.twitch.tv/docs/api/reference/#create-stream-marker
/raid, /unraid
https://dev.twitch.tv/docs/api/reference/#start-a-raid
/shield, /shieldoff
https://dev.twitch.tv/docs/api/reference/#update-shield-mode-status
/vip, /unvip
https://dev.twitch.tv/docs/api/reference/#add-channel-vip
/mod, /unmod
https://dev.twitch.tv/docs/api/reference/#add-channel-moderator
/color
https://dev.twitch.tv/docs/api/reference/#update-user-chat-color

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

continue Concurrent.Future chat_settings(object channel, string voiceid, string msg, mapping tok, string field, mixed val, string|void duration) {
	mapping cfg = ([field: val]);
	//For /followers and /slow, a parameter specifies the duration too.
	if (duration) cfg[duration] = (int)msg;
	mapping ret = yield(twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/chat/settings?broadcaster_id=%d&moderator_id=%s",
		channel->userid, voiceid),
		(["Authorization": "Bearer " + tok->token]),
		(["method": "PATCH", "json": cfg]),
	));
}

@"moderator:manage:chat_settings":
mixed emoteonly(object c, string v, string m, mapping t) {return chat_settings(c, v, m, t, "emote_mode", Val.true);}
@"moderator:manage:chat_settings":
mixed emoteonlyoff(object c, string v, string m, mapping t) {return chat_settings(c, v, m, t, "emote_mode", Val.false);}
@"moderator:manage:chat_settings":
mixed followers(object c, string v, string m, mapping t) {return chat_settings(c, v, m, t, "follower_mode", Val.true, "follower_mode_duration");}
@"moderator:manage:chat_settings":
mixed followersoff(object c, string v, string m, mapping t) {return chat_settings(c, v, m, t, "follower_mode", Val.false);}
@"moderator:manage:chat_settings":
mixed slow(object c, string v, string m, mapping t) {return chat_settings(c, v, m, t, "slow_mode", Val.true, "slow_mode_wait_time");}
@"moderator:manage:chat_settings":
mixed slowoff(object c, string v, string m, mapping t) {return chat_settings(c, v, m, t, "slow_mode", Val.false);}
@"moderator:manage:chat_settings":
mixed subscribers(object c, string v, string m, mapping t) {return chat_settings(c, v, m, t, "subscriber_mode", Val.true);}
@"moderator:manage:chat_settings":
mixed subscribersoff(object c, string v, string m, mapping t) {return chat_settings(c, v, m, t, "subscriber_mode", Val.false);}
@"moderator:manage:chat_settings":
mixed uniquechat(object c, string v, string m, mapping t) {return chat_settings(c, v, m, t, "unique_chat_mode", Val.true);}
@"moderator:manage:chat_settings":
mixed uniquechatoff(object c, string v, string m, mapping t) {return chat_settings(c, v, m, t, "unique_chat_mode", Val.false);}

@"moderator:manage:chat_messages":
continue Concurrent.Future clear(object channel, string voiceid, string msg, mapping tok, string|void msgid) {
	//Pass a msgid to delete an individual message, else clears all chat
	mapping ret = yield(twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/moderation/chat?broadcaster_id=%d&moderator_id=%s%s",
		channel->userid, voiceid, msgid ? "&message_id=" + msgid : ""),
		(["Authorization": "Bearer " + tok->token]),
		(["method": "DELETE"]),
	));
}

@"moderator:manage:banned_users":
continue Concurrent.Future ban(object channel, string voiceid, string msg, mapping tok, int|void timeout) {
	sscanf(msg, "%s %s", string username, string reason);
	int uid = yield(get_user_id(username || msg));
	mapping params = (["user_id": uid]);
	if (timeout == 1) {
		//The /timeout command accepts a duration prior to the reason.
		sscanf(reason || "", "%d %s", int duration, string r);
		params->duration = duration || 600;
		reason = r; //Ensure that reason is reassigned (otherwise "/timeout user 120" would time them out for 120 seconds with a reason of "120")
	}
	if (reason && reason != "") params->reason = reason;
	mapping ret = yield(twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/moderation/bans?broadcaster_id=%d&moderator_id=%s",
		channel->userid, voiceid),
		(["Authorization": "Bearer " + tok->token]),
		(["method": "POST", "json": (["data": params])]), //Not sure why it needs to be wrapped like this
	));
}
@"moderator:manage:banned_users":
mixed timeout(object c, string v, string m, mapping t) {return ban(c, v, m, t, 1);}
@"moderator:manage:banned_users":
mixed t(object c, string v, string m, mapping t) {return ban(c, v, m, t, 1);}

@"moderator:manage:banned_users":
continue Concurrent.Future unban(object channel, string voiceid, string msg, mapping tok) {
	mapping ret = yield(twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/moderation/bans?broadcaster_id=%d&moderator_id=%s&user_id={{USER}}",
		channel->userid, voiceid),
		(["Authorization": "Bearer " + tok->token]),
		(["method": "DELETE", "username": msg]),
	));
}
@"moderator:manage:banned_users":
mixed untimeout(object c, string v, string m, mapping t) {return unban(c, v, m, t);}

@"moderator:manage:shoutouts":
continue Concurrent.Future shoutout(object channel, string voiceid, string msg, mapping tok) {
	mapping ret = yield(twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/chat/shoutouts?from_broadcaster_id=%d"
			+ "&to_broadcaster_id={{USER}}&moderator_id=%s",
			channel->userid, voiceid),
		(["Authorization": "Bearer " + tok->token]), ([
			"method": "POST",
			"username": replace(msg, ({"@", " "}), ""),
		]),
	));
}

@"user:manage:whispers":
continue Concurrent.Future w(object channel, string voiceid, string msg, mapping tok) {
	sscanf(msg, "%s %s", string user, string message);
	if (!message) return 0;
	mapping ret = yield(twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/whispers?from_user_id=%s&to_user_id={{USER}}",
			voiceid),
		(["Authorization": "Bearer " + tok->token]), ([
			"method": "POST",
			"username": replace(user, ({"@", " "}), ""),
			"json": (["message": message]),
		]),
	));
}
@"user:manage:whispers":
mixed whisper(object c, string v, string m, mapping t) {return w(c, v, m, t);}

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
