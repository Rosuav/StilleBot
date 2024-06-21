//Transform slash commands (other than /me) into API calls
//TODO: Delay execution of a multi-part command until the API call returns
//This will ensure ordering of output when slash commands and regular text
//are interleaved.

/* Other slash commands, not easy (or maybe even possible) to implement:
/poll, /deletepoll, /endpoll, /vote, /goal, /prediction (won't open the window, so syntax will differ)
/pin (would love this but with a message ID instead)
/monitor, /unmonitor, /restrict, /unrestrict
*/
mapping need_scope = ([]); //Filled in by create()

@"moderator:manage:announcements":
void announce(object channel, string voiceid, string msg, mapping tok, string|void color) {
	twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/chat/announcements?broadcaster_id=%d&moderator_id=%s",
		channel->userid, voiceid),
		(["Authorization": "Bearer " + tok->token]),
		(["json": ([
			"message": msg,
			"color": color || "primary",
		])]),
	);
}

@"moderator:manage:announcements":
void announceblue(object c, string v, string m, mapping t) {announce(c, v, m, t, "blue");}
@"moderator:manage:announcements":
void announcegreen(object c, string v, string m, mapping t) {announce(c, v, m, t, "green");}
@"moderator:manage:announcements":
void announceorange(object c, string v, string m, mapping t) {announce(c, v, m, t, "orange");}
@"moderator:manage:announcements":
void announcepurple(object c, string v, string m, mapping t) {announce(c, v, m, t, "purple");}

void chat_settings(object channel, string voiceid, string msg, mapping tok, string field, mixed val, string|void duration) {
	mapping cfg = ([field: val]);
	//For /followers and /slow, a parameter specifies the duration too.
	if (duration) cfg[duration] = (int)msg;
	twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/chat/settings?broadcaster_id=%d&moderator_id=%s",
		channel->userid, voiceid),
		(["Authorization": "Bearer " + tok->token]),
		(["method": "PATCH", "json": cfg]),
	);
}

@"moderator:manage:chat_settings":
void emoteonly(object c, string v, string m, mapping t) {chat_settings(c, v, m, t, "emote_mode", Val.true);}
@"moderator:manage:chat_settings":
void emoteonlyoff(object c, string v, string m, mapping t) {chat_settings(c, v, m, t, "emote_mode", Val.false);}
@"moderator:manage:chat_settings":
void followers(object c, string v, string m, mapping t) {chat_settings(c, v, m, t, "follower_mode", Val.true, "follower_mode_duration");}
@"moderator:manage:chat_settings":
void followersoff(object c, string v, string m, mapping t) {chat_settings(c, v, m, t, "follower_mode", Val.false);}
@"moderator:manage:chat_settings":
void slow(object c, string v, string m, mapping t) {chat_settings(c, v, m, t, "slow_mode", Val.true, "slow_mode_wait_time");}
@"moderator:manage:chat_settings":
void slowoff(object c, string v, string m, mapping t) {chat_settings(c, v, m, t, "slow_mode", Val.false);}
@"moderator:manage:chat_settings":
void subscribers(object c, string v, string m, mapping t) {chat_settings(c, v, m, t, "subscriber_mode", Val.true);}
@"moderator:manage:chat_settings":
void subscribersoff(object c, string v, string m, mapping t) {chat_settings(c, v, m, t, "subscriber_mode", Val.false);}
@"moderator:manage:chat_settings":
void uniquechat(object c, string v, string m, mapping t) {chat_settings(c, v, m, t, "unique_chat_mode", Val.true);}
@"moderator:manage:chat_settings":
void uniquechatoff(object c, string v, string m, mapping t) {chat_settings(c, v, m, t, "unique_chat_mode", Val.false);}

@"moderator:manage:chat_messages":
void clear(object channel, string voiceid, string msg, mapping tok, string|void msgid) {
	//Pass a msgid to delete an individual message, else clears all chat
	twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/moderation/chat?broadcaster_id=%d&moderator_id=%s%s",
		channel->userid, voiceid, msgid ? "&message_id=" + msgid : ""),
		(["Authorization": "Bearer " + tok->token]),
		(["method": "DELETE"]),
	);
}
@"moderator:manage:chat_messages":
void deletemsg(object c, string v, string m, mapping t) {clear(c, v, "", t, m);}

@"moderator:manage:banned_users":
void ban(object channel, string voiceid, string msg, mapping tok, int|void timeout) {asyncban(channel, voiceid, msg, tok, timeout);}
//Can't annotate async functions?
__async__ void asyncban(object channel, string voiceid, string msg, mapping tok, int|void timeout) {
	sscanf(msg, "%s %s", string username, string reason);
	int uid = await(get_user_id(username || msg));
	mapping params = (["user_id": uid]);
	if (timeout == 1) {
		//The /timeout command accepts a duration prior to the reason.
		sscanf(reason || "", "%d %s", int duration, string r);
		params->duration = duration || 600;
		reason = r; //Ensure that reason is reassigned (otherwise "/timeout user 120" would time them out for 120 seconds with a reason of "120")
	}
	if (reason && reason != "") params->reason = reason;
	twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/moderation/bans?broadcaster_id=%d&moderator_id=%s",
		channel->userid, voiceid),
		(["Authorization": "Bearer " + tok->token]),
		(["method": "POST", "json": (["data": params])]), //Not sure why it needs to be wrapped like this
	);
}
@"moderator:manage:banned_users":
void timeout(object c, string v, string m, mapping t) {ban(c, v, m, t, 1);}
@"moderator:manage:banned_users":
void t(object c, string v, string m, mapping t) {ban(c, v, m, t, 1);}

@"moderator:manage:banned_users":
void unban(object channel, string voiceid, string msg, mapping tok) {
	twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/moderation/bans?broadcaster_id=%d&moderator_id=%s&user_id={{USER}}",
		channel->userid, voiceid),
		(["Authorization": "Bearer " + tok->token]),
		(["method": "DELETE", "username": msg]),
	);
}
@"moderator:manage:banned_users":
void untimeout(object c, string v, string m, mapping t) {unban(c, v, m, t);}

mapping(int:int) qso = ([]); //Not retained, will be purged on code reload
@"moderator:manage:shoutouts":
void shoutout(object channel, string voiceid, string msg, mapping tok, int|void queue) {asyncso(channel, voiceid, msg, tok, queue);}
__async__ void asyncso(object channel, string voiceid, string msg, mapping tok, int|void queue) {
	if (queue) {
		int delay = qso[channel->userid] - time();
		qso[channel->userid] = max(qso[channel->userid], time()) + 121; //Update the queue time before sleeping
		if (delay > 0) await(task_sleep(delay));
	}
	mapping ret = await(twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/chat/shoutouts?from_broadcaster_id=%d"
			+ "&to_broadcaster_id={{USER}}&moderator_id=%s",
			channel->userid, voiceid),
		(["Authorization": "Bearer " + tok->token]), ([
			"method": "POST",
			"username": replace(msg, ({"@", " "}), ""),
			"return_errors": 1,
		]),
	));
	if (ret->status >= 400) {
		//Something went wrong. Likely possibilities:
		//400 - no self-shoutouts, no offline shoutouts
		//429 - either too quick on the shoutouts, or you just shouted that streamer out
		//TODO: Log this somewhere for the broadcaster to see
		if (ret->status == 429 && queue && !has_value(ret->message, "the specified streamer")) {
			werror("** qshoutout failure: Got 429 error, qso %O time %O\n", qso[channel->userid], time());
		}
		else channel->report_error("WARN", ret->message, "/shoutout " + msg);
	}
}
@"moderator:manage:shoutouts":
void qshoutout(object c, string v, string m, mapping t) {shoutout(c, v, m, t, 1);}

@"user:manage:whispers":
void w(object channel, string voiceid, string msg, mapping tok) {
	sscanf(String.trim(msg), "%s %s", string user, string message);
	if (!message) return 0;
	twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/whispers?from_user_id=%s&to_user_id={{USER}}",
			voiceid),
		(["Authorization": "Bearer " + tok->token]), ([
			"method": "POST",
			"username": replace(user, ({"@", " "}), ""),
			"json": (["message": message]),
		]),
	);
}
@"user:manage:whispers":
void whisper(object c, string v, string m, mapping t) {w(c, v, m, t);}

@"channel:edit:commercial":
void commercial(object channel, string voiceid, string msg, mapping tok) {
	twitch_api_request("https://api.twitch.tv/helix/channels/commercial",
		(["Authorization": "Bearer " + tok->token]), ([
			"method": "POST",
			"json": ([
				"broadcaster_id": (string)channel->userid,
				"length": (int)msg || 30,
			]),
		]),
	);
}

@"channel:manage:broadcast":
void marker(object channel, string voiceid, string msg, mapping tok) {
	twitch_api_request("https://api.twitch.tv/helix/streams/markers",
		(["Authorization": "Bearer " + tok->token]), ([
			"method": "POST",
			"json": ([
				"user_id": (string)channel->userid,
				"description": msg,
			]),
		]),
	);
}

@"channel:manage:raids":
void raid(object channel, string voiceid, string msg, mapping tok) {
	twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/raids?from_broadcaster_id=%d&to_broadcaster_id={{USER}}",
			channel->userid),
		(["Authorization": "Bearer " + tok->token]), ([
			"method": "POST",
			"username": replace(msg, ({"@", " "}), ""),
		]),
	);
}

@"channel:manage:raids":
void unraid(object channel, string voiceid, string msg, mapping tok) {
	twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/raids?broadcaster_id=%d",
			channel->userid),
		(["Authorization": "Bearer " + tok->token]), ([
			"method": "DELETE",
		]),
	);
}

@"channel:manage:vips":
void vip(object channel, string voiceid, string msg, mapping tok, int|void remove) {
	twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/channels/vips?broadcaster_id=%d&user_id={{USER}}",
			channel->userid),
		(["Authorization": "Bearer " + tok->token]), ([
			"method": remove ? "DELETE" : "POST",
			"username": replace(msg, ({"@", " "}), ""),
		]),
	);
}
@"channel:manage:vips":
void unvip(object c, string v, string m, mapping t) {vip(c, v, m, t, 1);}

@"channel:manage:moderators":
void mod(object channel, string voiceid, string msg, mapping tok, int|void remove) {
	twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/moderation/moderators?broadcaster_id=%d&user_id={{USER}}",
			channel->userid),
		(["Authorization": "Bearer " + tok->token]), ([
			"method": remove ? "DELETE" : "POST",
			"username": replace(msg, ({"@", " "}), ""),
		]),
	);
}
@"channel:manage:moderators":
void unmod(object c, string v, string m, mapping t) {mod(c, v, m, t, 1);}

Regexp.SimpleRegexp bicap = Regexp.SimpleRegexp("[a-z][A-Z]");
string bicap_to_snake(string pair) {return pair / 1 * "_";}
@"user:manage:chat_color":
void color(object channel, string voiceid, string msg, mapping tok) {
	if (msg == "") return 0; //No error return here for simplicity (we can't send to just the user anyway)
	//Twitch expects users to write BiCapitalized colour names eg "GoldenRod", but
	//the API expects them in snake_case instead eg "golden_rod". Don't add any
	//underscores in a hex string though, as it's likely a coincidence.
	if (msg[0] != '#') msg = lower_case(bicap->replace(msg, bicap_to_snake));
	twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/chat/color?user_id=%s&color=%s",
			voiceid, Protocols.HTTP.uri_encode(msg)),
		(["Authorization": "Bearer " + tok->token]), ([
			"method": "PUT",
		]),
	);
}

@"moderator:manage:shield_mode":
void shield(object channel, string voiceid, string msg, mapping tok, int|void remove) {
	twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/moderation/shield_mode?broadcaster_id=%d&moderator_id=%s",
			channel->userid, voiceid),
		(["Authorization": "Bearer " + tok->token]), ([
			"method": "PUT",
			"json": (["is_active": remove ? Val.false : Val.true]),
		]),
	);
}
@"moderator:manage:shield_mode":
void shieldoff(object c, string v, string m, mapping t) {shield(c, v, m, t, 1);}

//TODO: Should there be a corresponding special trigger when the user acknowledges it?
@"moderator:manage:warnings":
__async__ void warn(object channel, string voiceid, string msg, mapping tok) {
	sscanf(msg, "%s %s", string user, string reason);
	if (!user) user = msg;
	int uid = await(get_user_id(user));
	twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/moderation/warnings?broadcaster_id=%d&moderator_id=%s",
			channel->userid, voiceid),
		(["Authorization": "Bearer " + tok->token]), ([
			"method": "POST",
			"json": (["data": (["user_id": (string)uid, "reason": reason || ""])]),
		]),
	);
}

//Returns 0 if it sent the message, otherwise a reason code.
//Yes, the parameter order is a bit odd; it makes filtering by this easier.
string|zero send_chat_command(string msg, object channel, string voiceid) {
	sscanf(msg, "/%[^ ] %s", string cmd, string param);
	if (!need_scope[cmd]) return "not a command";
	mapping tok = G->G->user_credentials[(int)voiceid];
	if (!voiceid || voiceid == "0") {
		voiceid = (string)G->G->bot_uid;
		tok = (["token": G->G->dbsettings->credentials->token,
			"scopes": G->G->dbsettings->credentials->scopes || ({"whispers:edit"})]);
	}
	if (!has_value(tok->scopes, need_scope[cmd])) {
		channel->report_error("ERROR", "This command requires " + need_scope[cmd] + " permission", msg);
		return 0; //Note that this will still suppress the chat message.
	}
	this[cmd](channel, voiceid, param || "", tok);
}

protected void create(string name) {
	G->G->send_chat_command = send_chat_command;
	mapping voice_scopes = ([]), scope_commands = ([]);
	foreach (Array.transpose(({indices(this), annotations(this)})), [string key, mixed ann]) {
		if (ann) foreach (indices(ann), mixed anno) {
			need_scope[key] = anno;
			voice_scopes[anno] = all_twitch_scopes[anno] || anno; //If there's a function that uses it, the voices subsystem can grant it.
			scope_commands[anno] += ({"/" + key});
		}
	}
	//There are additional scopes that don't correspond to any slash command, but might be granted
	//to a voice.
	foreach ("moderator:read:chatters user:read:emotes" / " ", string scope)
		voice_scopes[scope] = all_twitch_scopes[scope] || scope;
	G->G->voice_additional_scopes = voice_scopes;
	G->G->voice_scope_commands = scope_commands;
	G->G->voice_command_scopes = need_scope;
	//send_chat_command("/announce This is an announcement from the bot!", G->G->irc->channels["#rosuav"], "0");
	//send_chat_command("/announce This is an announcement from Mustard Mine!", G->G->irc->channels["#rosuav"], "279141671");
}
