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
@"Send an announcement (add suffix for color) -> message":
Concurrent.Future announce(object channel, string voiceid, string msg, mapping tok, string|void color) {
	return twitch_api_request(sprintf(
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
@"Announce in blue -> message":
Concurrent.Future announceblue(object c, string v, string m, mapping t) {return announce(c, v, m, t, "blue");}
@"moderator:manage:announcements":
@"Announce in green -> message":
Concurrent.Future announcegreen(object c, string v, string m, mapping t) {return announce(c, v, m, t, "green");}
@"moderator:manage:announcements":
@"Announce in orange -> message":
Concurrent.Future announceorange(object c, string v, string m, mapping t) {return announce(c, v, m, t, "orange");}
@"moderator:manage:announcements":
@"Announce in purple -> message":
Concurrent.Future announcepurple(object c, string v, string m, mapping t) {return announce(c, v, m, t, "purple");}

Concurrent.Future chat_settings(object channel, string voiceid, string msg, mapping tok, string field, mixed val, string|void duration) {
	mapping cfg = ([field: val]);
	//For /followers and /slow, a parameter specifies the duration too.
	if (duration) cfg[duration] = (int)msg;
	return twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/chat/settings?broadcaster_id=%d&moderator_id=%s",
		channel->userid, voiceid),
		(["Authorization": "Bearer " + tok->token]),
		(["method": "PATCH", "json": cfg]),
	);
}

@"moderator:manage:chat_settings":
@"Enable emote-only mode until /emoteonlyoff ->":
Concurrent.Future emoteonly(object c, string v, string m, mapping t) {return chat_settings(c, v, m, t, "emote_mode", Val.true);}
@"moderator:manage:chat_settings":
@"End emote-only mode ->":
Concurrent.Future emoteonlyoff(object c, string v, string m, mapping t) {return chat_settings(c, v, m, t, "emote_mode", Val.false);}
@"moderator:manage:chat_settings":
@"Enable follower-only mode until /followersoff -> [min-follow-time]":
Concurrent.Future followers(object c, string v, string m, mapping t) {return chat_settings(c, v, m, t, "follower_mode", Val.true, "follower_mode_duration");}
@"moderator:manage:chat_settings":
@"End follower-only mode ->":
Concurrent.Future followersoff(object c, string v, string m, mapping t) {return chat_settings(c, v, m, t, "follower_mode", Val.false);}
@"moderator:manage:chat_settings":
@"Enable slow mode (eg /slow 3) until /slowoff -> delay-time":
Concurrent.Future slow(object c, string v, string m, mapping t) {return chat_settings(c, v, m, t, "slow_mode", Val.true, "slow_mode_wait_time");}
@"moderator:manage:chat_settings":
@"End slow mode ->":
Concurrent.Future slowoff(object c, string v, string m, mapping t) {return chat_settings(c, v, m, t, "slow_mode", Val.false);}
@"moderator:manage:chat_settings":
@"Enable sub-only mode until /subscribersoff ->":
Concurrent.Future subscribers(object c, string v, string m, mapping t) {return chat_settings(c, v, m, t, "subscriber_mode", Val.true);}
@"moderator:manage:chat_settings":
@"End sub-only mode ->":
Concurrent.Future subscribersoff(object c, string v, string m, mapping t) {return chat_settings(c, v, m, t, "subscriber_mode", Val.false);}
@"moderator:manage:chat_settings":
@"Enable unique chat mode (R9K) until /uniquechatoff ->":
Concurrent.Future uniquechat(object c, string v, string m, mapping t) {return chat_settings(c, v, m, t, "unique_chat_mode", Val.true);}
@"moderator:manage:chat_settings":
@"End unique-chat mode ->":
Concurrent.Future uniquechatoff(object c, string v, string m, mapping t) {return chat_settings(c, v, m, t, "unique_chat_mode", Val.false);}

@"moderator:manage:chat_messages":
@"Clear all chat (not commonly necessary) ->":
Concurrent.Future clear(object channel, string voiceid, string msg, mapping tok, string|void msgid) {
	//Pass a msgid to delete an individual message, else clears all chat
	return twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/moderation/chat?broadcaster_id=%d&moderator_id=%s%s",
		channel->userid, voiceid, msgid ? "&message_id=" + msgid : ""),
		(["Authorization": "Bearer " + tok->token]),
		(["method": "DELETE"]),
	);
}
@"moderator:manage:chat_messages":
@"Delete a single message -> message-id":
Concurrent.Future deletemsg(object c, string v, string m, mapping t) {return clear(c, v, "", t, m);}

@"moderator:manage:banned_users":
@"Ban a user -> username [reason]":
__async__ void ban(object channel, string voiceid, string msg, mapping tok, int|void timeout) {
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
	await(twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/moderation/bans?broadcaster_id=%d&moderator_id=%s",
		channel->userid, voiceid),
		(["Authorization": "Bearer " + tok->token]),
		(["method": "POST", "json": (["data": params])]), //Not sure why it needs to be wrapped like this
	));
}
@"moderator:manage:banned_users":
@"Time out a user -> username time [reason]":
Concurrent.Future timeout(object c, string v, string m, mapping t) {return ban(c, v, m, t, 1);}
@"moderator:manage:banned_users":
@"Time out a user -> username time [reason]":
Concurrent.Future t(object c, string v, string m, mapping t) {return ban(c, v, m, t, 1);}

@"moderator:manage:banned_users":
@"Cancel a ban/timeout -> username":
Concurrent.Future unban(object channel, string voiceid, string msg, mapping tok) {
	return twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/moderation/bans?broadcaster_id=%d&moderator_id=%s&user_id={{USER}}",
		channel->userid, voiceid),
		(["Authorization": "Bearer " + tok->token]),
		(["method": "DELETE", "username": msg]),
	);
}
@"moderator:manage:banned_users":
@"Cancel a ban/timeout -> username":
Concurrent.Future untimeout(object c, string v, string m, mapping t) {return unban(c, v, m, t);}

mapping(int:int) qso = ([]); //Not retained, will be purged on code reload
@"moderator:manage:shoutouts":
@"Send an on-platform shoutout immediately, or fail if it can't be done -> streamername":
__async__ void shoutout(object channel, string voiceid, string msg, mapping tok, int|void queue) {
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
@"Send an on-platform shoutout, delaying it until the previous /qshoutout is done -> streamername":
Concurrent.Future qshoutout(object c, string v, string m, mapping t) {return shoutout(c, v, m, t, 1);}

@"user:manage:whispers":
@"Whisper a message to a user -> username message":
Concurrent.Future whisper(object channel, string voiceid, string msg, mapping tok) {
	sscanf(String.trim(msg), "%s %s", string user, string message);
	if (!message) return Concurrent.resolve(1);
	return twitch_api_request(sprintf(
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
@"Whisper a message to a user -> username message":
Concurrent.Future w(object c, string v, string m, mapping t) {return whisper(c, v, m, t);}

@"channel:edit:commercial":
@"Start an ad break -> [length]":
Concurrent.Future commercial(object channel, string voiceid, string msg, mapping tok) {
	return twitch_api_request("https://api.twitch.tv/helix/channels/commercial",
		(["Authorization": "Bearer " + tok->token]), ([
			"method": "POST",
			"json": ([
				"broadcaster_id": (string)channel->userid,
				"length": (int)msg || 30,
			]),
		]),
	);
}

@"channel:manage:ads":
@"Delay the next scheduled ad break by 5 minutes ->":
__async__ void snooze(object channel, string voiceid, string msg, mapping tok) {
	await(twitch_api_request("https://api.twitch.tv/helix/channels/ads/schedule/snooze?broadcaster_id=" + channel->userid,
		(["Authorization": "Bearer " + tok->token]), (["method": "POST"]),
	));
	G->G->recheck_ad_status(channel);
}

@"channel:manage:broadcast":
@"Add a VOD marker so you can find back this point for highlighting -> label":
Concurrent.Future marker(object channel, string voiceid, string msg, mapping tok) {
	return twitch_api_request("https://api.twitch.tv/helix/streams/markers",
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
@"Raid someone! -> target-streamer":
Concurrent.Future raid(object channel, string voiceid, string msg, mapping tok) {
	return twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/raids?from_broadcaster_id=%d&to_broadcaster_id={{USER}}",
			channel->userid),
		(["Authorization": "Bearer " + tok->token]), ([
			"method": "POST",
			"username": replace(msg, ({"@", " "}), ""),
		]),
	);
}

@"channel:manage:raids":
@"Cancel a raid that's been started but hasn't gone through yet ->":
Concurrent.Future unraid(object channel, string voiceid, string msg, mapping tok) {
	return twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/raids?broadcaster_id=%d",
			channel->userid),
		(["Authorization": "Bearer " + tok->token]), ([
			"method": "DELETE",
		]),
	);
}

@"channel:manage:vips":
@"Give someone a VIP badge -> username":
Concurrent.Future vip(object channel, string voiceid, string msg, mapping tok, int|void remove) {
	return twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/channels/vips?broadcaster_id=%d&user_id={{USER}}",
			channel->userid),
		(["Authorization": "Bearer " + tok->token]), ([
			"method": remove ? "DELETE" : "POST",
			"username": replace(msg, ({"@", " "}), ""),
		]),
	);
}
@"channel:manage:vips":
@"Remove someone's VIP badge -> username":
Concurrent.Future unvip(object c, string v, string m, mapping t) {return vip(c, v, m, t, 1);}

@"channel:manage:moderators":
@"Give someone a mod sword -> username":
Concurrent.Future mod(object channel, string voiceid, string msg, mapping tok, int|void remove) {
	return twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/moderation/moderators?broadcaster_id=%d&user_id={{USER}}",
			channel->userid),
		(["Authorization": "Bearer " + tok->token]), ([
			"method": remove ? "DELETE" : "POST",
			"username": replace(msg, ({"@", " "}), ""),
		]),
	);
}
@"channel:manage:moderators":
@"Remove a mod sword -> username":
Concurrent.Future unmod(object c, string v, string m, mapping t) {return mod(c, v, m, t, 1);}

Regexp.SimpleRegexp bicap = Regexp.SimpleRegexp("[a-z][A-Z]");
string bicap_to_snake(string pair) {return pair / 1 * "_";}
@"user:manage:chat_color":
@"Set your chat color. Words eg GoldenRod, or hex eg #663399 -> color":
Concurrent.Future color(object channel, string voiceid, string msg, mapping tok) {
	if (msg == "") return Concurrent.resolve(1); //No error return here for simplicity (we can't send to just the user anyway)
	//Twitch expects users to write BiCapitalized colour names eg "GoldenRod", but
	//the API expects them in snake_case instead eg "golden_rod". Don't add any
	//underscores in a hex string though, as it's likely a coincidence.
	if (msg[0] != '#') msg = lower_case(bicap->replace(msg, bicap_to_snake));
	return twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/chat/color?user_id=%s&color=%s",
			voiceid, Protocols.HTTP.uri_encode(msg)),
		(["Authorization": "Bearer " + tok->token]), ([
			"method": "PUT",
		]),
	);
}

@"moderator:manage:shield_mode":
@"Engage shield mode immediately ->":
Concurrent.Future shield(object channel, string voiceid, string msg, mapping tok, int|void remove) {
	return twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/moderation/shield_mode?broadcaster_id=%d&moderator_id=%s",
			channel->userid, voiceid),
		(["Authorization": "Bearer " + tok->token]), ([
			"method": "PUT",
			"json": (["is_active": remove ? Val.false : Val.true]),
		]),
	);
}
@"moderator:manage:shield_mode":
@"Disengage shield mode ->":
Concurrent.Future shieldoff(object c, string v, string m, mapping t) {return shield(c, v, m, t, 1);}

//TODO: Should there be a corresponding special trigger when the user acknowledges it?
@"moderator:manage:warnings":
@"Give a moderatorial warning to a user - they must acknowledge it to continue chatting -> username warning":
__async__ void warn(object channel, string voiceid, string msg, mapping tok) {
	sscanf(msg, "%s %s", string user, string reason);
	if (!user) return; //Must have a reason
	int uid = await(get_user_id(user));
	await(twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/moderation/warnings?broadcaster_id=%d&moderator_id=%s",
			channel->userid, voiceid),
		(["Authorization": "Bearer " + tok->token]), ([
			"method": "POST",
			"json": (["data": (["user_id": (string)uid, "reason": reason])]),
		]),
	));
}

//Process a slash command and return a promise when it will be done, or return any
//non-command chat message for direct delivery. Note that the Future returned does
//not have any useful data in it (it's probably just a status report from an API
//call or something).
string|Concurrent.Future send_chat_command(object channel, string voiceid, string msg) {
	if (!has_prefix(msg, "/")) return msg;
	sscanf(msg, "/%[^ ] %s", string cmd, string param);
	//Special cases: You can "/me" in chat, without using the API
	if (cmd == "me") return msg;
	if (!need_scope[cmd]) return " " + msg; //Return "/asdf" as " /asdf" so it gets output correctly
	mapping tok = G->G->user_credentials[(int)voiceid];
	if (!voiceid || voiceid == "0") {
		voiceid = (string)G->G->bot_uid;
		tok = (["token": G->G->dbsettings->credentials->token,
			"scopes": G->G->dbsettings->credentials->scopes || ({"whispers:edit"})]);
	}
	if (!has_value(tok->scopes, need_scope[cmd])) {
		channel->report_error("ERROR", "This command requires " + need_scope[cmd] + " permission", msg);
		return Concurrent.resolve(1); //Note that this will still suppress the chat message.
	}
	return this[cmd](channel, voiceid, param || "", tok);
}

protected void create(string name) {
	G->G->send_chat_command = send_chat_command;
	mapping voice_scopes = ([]), scope_commands = ([]);
	mapping slashcommands = (["me": "Describe an action -> msg"]);
	foreach (Array.transpose(({indices(this), annotations(this)})), [string key, mixed ann]) {
		if (ann) foreach (indices(ann), mixed anno) {
			if (has_value(anno, " ->")) slashcommands[key] = anno;
			else {
				need_scope[key] = anno;
				voice_scopes[anno] = all_twitch_scopes[anno] || anno; //If there's a function that uses it, the voices subsystem can grant it.
				scope_commands[anno] += ({"/" + key});
			}
		}
	}
	//There are additional scopes that don't correspond to any slash command, but might be granted
	//to a voice.
	foreach ("moderator:read:chatters user:read:emotes" / " ", string scope)
		voice_scopes[scope] = all_twitch_scopes[scope] || scope;
	G->G->voice_additional_scopes = voice_scopes;
	G->G->voice_scope_commands = scope_commands;
	G->G->voice_command_scopes = need_scope;
	G->G->slash_commands = slashcommands;
}
