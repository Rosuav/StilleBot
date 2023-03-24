//Transform slash commands (other than /me) into API calls

/* Other slash commands, not easy (or maybe even possible) to implement:
/poll, /deletepoll, /endpoll, /vote, /goal, /prediction (won't open the window, so syntax will differ)
/pin (would love this but with a message ID instead)
/monitor, /unmonitor, /restrict, /unrestrict
*/
mapping scopes = ([
	//Scopes last updated from https://dev.twitch.tv/docs/authentication/scopes/ 20230324
	//TODO: Annotate the ones that should get a yellow warning triangle added
	"analytics:read:extensions": "View analytics data for Twitch Extensions",
	"analytics:read:games": "View analytics data for games",
	"bits:read": "See cheers and the bits leaderboard",
	"channel:edit:commercial": "Run ads (broadcaster only)",
	"channel:manage:broadcast": "Configure broadcast incl category, title, and VOD markers (editor only)",
	"channel:read:charity": "See charity campaign details",
	"channel:manage:extensions": "Activate/deactivate Twitch Extensions",
	"channel:manage:moderators": "Add/remove mod swords (broadcaster only)",
	"channel:manage:polls": "Start and end polls",
	"channel:manage:predictions": "Start and end predictions",
	"channel:manage:raids": "Go raiding (broadcaster only)",
	"channel:manage:redemptions": "Create and manage channel point rewards and redemptions",
	"channel:manage:schedule": "Update the channel broadcast schedule",
	"channel:manage:videos": "Delete VODs",
	"channel:manage:vips": "Add/remove VIP badges (broadcaster only)",
	"channel:read:editors": "See who is an editor for the channel",
	"channel:read:goals": "View goals (eg follower/subscriber counts)",
	"channel:read:hype_train": "See hype train status and get notifications",
	"channel:read:polls": "View a current poll in progress and get notifications",
	"channel:read:predictions": "View a current prediction in progress and get notifications",
	"channel:read:redemptions": "See channel point rewards and redemptions",
	"channel:read:stream_key": "See your stream key and stream on your behalf",
	"channel:read:subscriptions": "See who's subscribed to your channel",
	"channel:read:vips": "List current channel VIPs",
	"clips:edit": "Create clips of the current broadcast",
	"moderation:read": "See who's banned, who's a mod, etc",
	"moderator:manage:announcements": "Send announcements",
	"moderator:manage:automod": "Make decisions on automodded messages",
	"moderator:read:automod_settings": "See Automod settings",
	"moderator:manage:automod_settings": "Change Automod settings",
	"moderator:manage:banned_users": "Ban/timeout/unban users",
	"moderator:read:blocked_terms": "See currently-blocked words and phrases",
	"moderator:manage:blocked_terms": "Change the blocked words/phrases list",
	"moderator:manage:chat_messages": "Delete individual chat messages",
	"moderator:read:chat_settings": "View chat restrictions eg slow mode",
	"moderator:manage:chat_settings": "Set/remove chat restrictions eg slow mode",
	"moderator:read:chatters": "See who's currently in chat",
	"moderator:read:followers": "List your channel followers and get notified on new follows",
	"moderator:read:shield_mode": "See whether shield mode is active and get notified when it's activated",
	"moderator:manage:shield_mode": "Engage/disengage shield mode",
	"moderator:read:shoutouts": "Get notified when you shout out or get shouted out",
	"moderator:manage:shoutouts": "Send shoutouts",
	"user:edit": "Update the user's description",
	"user:edit:follows": "Deprecated - no longer functional (was follow/unfollow)",
	"user:manage:blocked_users": "Block or unblock other users",
	"user:read:blocked_users": "See who you've blocked (not the same as banned from the channel)",
	"user:read:broadcast": "See which Twitch extensions you're using",
	"user:edit:broadcast": "Activate and deactivate extensions",
	"user:manage:chat_color": "Change chat color",
	"user:read:email": "See your email address",
	"user:read:follows": "See who you follow",
	"user:read:subscriptions": "Check if you are subscribed to a channel",
	"user:manage:whispers": "Send whispers (requires phone auth)",
	//Chat/PubSub scopes
	"channel:moderate": "Perform and see moderation actions in a channel",
	"chat:edit": "Send chat messages",
	"chat:read": "View chat messages as they happen",
	"whispers:read": "View your whispers as they arrive",
	"whispers:edit": "Send whispers (may no longer be functional)",
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
@"moderator:manage:chat_messages":
continue Concurrent.Future deletemsg(object c, string v, string m, mapping t) {return clear(c, v, "", t, m);}

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

@"channel:edit:commercial":
continue Concurrent.Future commercial(object channel, string voiceid, string msg, mapping tok) {
	mapping ret = yield(twitch_api_request("https://api.twitch.tv/helix/channels/commercial",
		(["Authorization": "Bearer " + tok->token]), ([
			"method": "POST",
			"json": ([
				"broadcaster_id": (string)channel->userid,
				"length": (int)msg || 30,
			]),
		]),
	));
}

@"channel:manage:broadcast":
continue Concurrent.Future marker(object channel, string voiceid, string msg, mapping tok) {
	mapping ret = yield(twitch_api_request("https://api.twitch.tv/helix/streams/markers",
		(["Authorization": "Bearer " + tok->token]), ([
			"method": "POST",
			"json": ([
				"user_id": (string)channel->userid,
				"description": msg,
			]),
		]),
	));
}

@"channel:manage:raids":
continue Concurrent.Future raid(object channel, string voiceid, string msg, mapping tok) {
	mapping ret = yield(twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/raids?from_broadcaster_id=%d&to_broadcaster_id={{USER}}",
			channel->userid),
		(["Authorization": "Bearer " + tok->token]), ([
			"method": "POST",
			"username": replace(msg, ({"@", " "}), ""),
		]),
	));
}

@"channel:manage:raids":
continue Concurrent.Future unraid(object channel, string voiceid, string msg, mapping tok) {
	mapping ret = yield(twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/raids?broadcaster_id=%d",
			channel->userid),
		(["Authorization": "Bearer " + tok->token]), ([
			"method": "DELETE",
		]),
	));
}

@"channel:manage:vips":
continue Concurrent.Future vip(object channel, string voiceid, string msg, mapping tok, int|void remove) {
	mapping ret = yield(twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/channels/vips?broadcaster_id=%d&user_id={{USER}}",
			channel->userid),
		(["Authorization": "Bearer " + tok->token]), ([
			"method": remove ? "DELETE" : "POST",
			"username": replace(msg, ({"@", " "}), ""),
		]),
	));
}
@"channel:manage:vips":
mixed unvip(object c, string v, string m, mapping t) {return vip(c, v, m, t, 1);}

@"channel:manage:moderators":
continue Concurrent.Future mod(object channel, string voiceid, string msg, mapping tok, int|void remove) {
	mapping ret = yield(twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/moderation/moderators?broadcaster_id=%d&user_id={{USER}}",
			channel->userid),
		(["Authorization": "Bearer " + tok->token]), ([
			"method": remove ? "DELETE" : "POST",
			"username": replace(msg, ({"@", " "}), ""),
		]),
	));
}
@"channel:manage:moderators":
mixed unmod(object c, string v, string m, mapping t) {return mod(c, v, m, t, 1);}

Regexp.SimpleRegexp bicap = Regexp.SimpleRegexp("[a-z][A-Z]");
string bicap_to_snake(string pair) {return pair / 1 * "_";}
@"user:manage:chat_color":
continue Concurrent.Future color(object channel, string voiceid, string msg, mapping tok) {
	if (msg == "") return 0; //No error return here for simplicity (we can't send to just the user anyway)
	//Twitch expects users to write BiCapitalized colour names eg "GoldenRod", but
	//the API expects them in snake_case instead eg "golden_rod". Don't add any
	//underscores in a hex string though, as it's likely a coincidence.
	if (msg[0] != '#') msg = lower_case(bicap->replace(msg, bicap_to_snake));
	mapping ret = yield(twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/chat/color?user_id=%s&color=%s",
			voiceid, Protocols.HTTP.uri_encode(msg)),
		(["Authorization": "Bearer " + tok->token]), ([
			"method": "PUT",
		]),
	));
}

@"moderator:manage:shield_mode":
continue Concurrent.Future shield(object channel, string voiceid, string msg, mapping tok, int|void remove) {
	mapping ret = yield(twitch_api_request(sprintf(
		"https://api.twitch.tv/helix/moderation/shield_mode?broadcaster_id=%d&moderator_id=%s",
			channel->userid, voiceid),
		(["Authorization": "Bearer " + tok->token]), ([
			"method": "PUT",
			"json": (["is_active": remove ? Val.false : Val.true]),
		]),
	));
}
@"moderator:manage:shield_mode":
mixed shieldoff(object c, string v, string m, mapping t) {return shield(c, v, m, t, 1);}

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
	G->G->send_chat_command = send_chat_command;
	mapping voice_scopes = ([]);
	foreach (Array.transpose(({indices(this), annotations(this)})), [string key, mixed ann]) {
		if (ann) foreach (indices(ann), mixed anno) {
			if (!scopes[anno]) scopes[anno] = anno; //Ensure that every scope is listed in the description mapping
			need_scope[key] = anno;
			voice_scopes[anno] = scopes[anno]; //If there's a function that uses it, the voices subsystem can grant it.
		}
	}
	G->G->voice_additional_scopes = voice_scopes;
	//send_chat_command("/announce This is an announcement from the bot!", G->G->irc->channels["#rosuav"], 0);
	//send_chat_command("/announce This is an announcement from Mustard Mine!", G->G->irc->channels["#rosuav"], "279141671");
}
