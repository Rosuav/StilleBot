inherit http_websocket;
inherit builtin_command;
inherit annotated;
inherit hook;

//NOTE: This saves into channel->botconfig since it needs to be checked for every single
//message that gets posted. It's like how commands/triggers/specials are all preloaded.

constant markdown = #{# Hyperlink blocking for $$channel$$

Posting of hyperlinks can be blocked in your Twitch Dashboard. If they are, none of these
settings will take effect, and non-moderators will not be able to post any links.
Go to [your dashboard](https://dashboard.twitch.tv/moderation/settings) and "Show All Advanced
Settings" if necessary, then scroll down to "Block Hyperlinks" and ensure that it is disabled.

<div id=settings></div>

$$save_or_login$$
#};

@retain: mapping(int:mapping(int:int)) hyperlink_bans = ([]);

constant ENABLEABLE_FEATURES = ([
	"block-links": ([
		"description": "Block links except from VIPs and raiders (configurable)",
	]),
]);

int can_manage_feature(object channel, string kwd) {return channel->something ? 2 : 1;}

void enable_feature(object channel, string kwd, int state) {
	mapping info = ENABLEABLE_FEATURES[kwd]; if (!info) return;
	//TODO: If state, enable link blocking with default settings, else disable all link blocking
}

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {

	return render(req, ([
		"vars": (["ws_group": req->misc->is_mod ? "control" : ""]),
		req->misc->is_mod ? "save_or_login" : "ignoreme": "",
	]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return grp == "control";}
__async__ mapping get_chan_state(object channel, string grp) {
	if (grp == "control") return channel->botconfig->hyperlinks || ([]);
	//TODO: Reduced info for non-mods
	return ([]);
}

@hook_allmsgs: int message(object channel, mapping person, string msg) {
	if (person->badges->?_mod) return 0; //Mods are always permitted, no matter what settings we have
	mapping cfg = channel->config->hyperlinks || ([]);
	if (!cfg->blocked) return 0; //All links are permitted, no filtering is being done
	if (!cfg->warnings || !sizeof(cfg->warnings)) return 0; //No actions to be taken against links
	if (!has_value(msg, "KICKME")) return 0; //For testing, we actually block the word KICKME, instead of hyperlinks.
	if (person->badges->?vip && has_value(cfg->permit, "vip")) return 0;
	if (channel->raiders[person->uid] && has_value(cfg->permit, "raider")) return 0;
	//TODO: !permit command
	//If we got this far, the user needs to be punished.
	mapping bans = hyperlink_bans[channel->userid];
	if (!bans) bans = hyperlink_bans[channel->userid] = ([]);
	//Humans will talk about "strike one" as the first, but since we're looking up in an array,
	//the first offense is strike 0.
	int strike = bans[person->uid]++;
	if (strike >= sizeof(cfg->warnings)) strike = sizeof(cfg->warnings) - 1;
	mapping warn = cfg->warnings[strike];
	if (warn->msg != "") channel->send(person, warn->msg);
	int voiceid = 49497888; //FIXME
	mapping params = (["user_id": person->uid]);
	switch (warn->action) {
		case "delete": twitch_api_request(sprintf(
			"https://api.twitch.tv/helix/moderation/chat?broadcaster_id=%d&moderator_id=%d&message_id=%s",
			channel->userid, voiceid, person->msgid),
			(["Authorization": voiceid]),
			(["method": "DELETE"]),
		);
		break;
		case "timeout": params->duration = warn->duration; //Fall through
		case "ban": twitch_api_request(sprintf(
			"https://api.twitch.tv/helix/moderation/bans?broadcaster_id=%d&moderator_id=%d",
			channel->userid, voiceid),
			(["Authorization": voiceid]),
			(["method": "POST", "json": (["data": params])]), //Not sure why it needs to be wrapped like this
		);
		break;
		case "warn": default: break; //Just a warning (message), no timeout/ban.
	}
}

@hook_channel_offline: int channel_offline(string channel, int uptime, int id) {m_delete(hyperlink_bans, id);}

@"is_mod": void wscmd_allow(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping cfg = channel->botconfig->hyperlinks;
	if (!cfg) cfg = channel->botconfig->hyperlinks = ([]);
	if (msg->all) {
		cfg->blocked = 0;
		m_delete(cfg, "permit");
	} else {
		cfg->blocked = 1;
		cfg->permit = msg->permit || ({ });
	}
	channel->botconfig_save();
	send_updates_all(channel, "");
	send_updates_all(channel, "control");
}

@"is_mod": void wscmd_addwarning(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping cfg = channel->botconfig->hyperlinks;
	if (!cfg) cfg = channel->botconfig->hyperlinks = ([]);
	if (msg->action == "purge") cfg->warnings += ({(["action": "timeout", "duration": 1, "msg": ""])}); //A purge is a short timeout, and is indistinguishable from same.
	else if (msg->action == "timeout") cfg->warnings += ({(["action": "timeout", "duration": 60, "msg": ""])}); //The timeout can be configured afterwards, default to a minute.
	else if ((<"warn", "delete", "timeout", "ban">)[msg->action]) cfg->warnings += ({(["action": msg->action, "msg": ""])});
	channel->botconfig_save();
	send_updates_all(channel, "");
	send_updates_all(channel, "control");
}

@"is_mod": void wscmd_delwarning(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping cfg = channel->botconfig->hyperlinks;
	if (!cfg) cfg = channel->botconfig->hyperlinks = ([]);
	if (!cfg->warnings) return; //Nothing to delete
	int idx = (int)msg->idx;
	if (idx < 0 || idx >= sizeof(cfg->warnings)) return;
	cfg->warnings = cfg->warnings[..idx-1] + cfg->warnings[idx+1..];
	channel->botconfig_save();
	send_updates_all(channel, "");
	send_updates_all(channel, "control");
}

@"is_mod": void wscmd_editwarning(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping cfg = channel->botconfig->hyperlinks;
	if (!cfg) cfg = channel->botconfig->hyperlinks = ([]);
	if (!cfg->warnings) return; //Nothing to do
	int idx = (int)msg->idx;
	if (idx < 0 || idx >= sizeof(cfg->warnings)) return;
	mapping warn = cfg->warnings[idx];
	if (msg->msg) warn->msg = msg->msg;
	if ((int)msg->duration && warn->action == "timeout") warn->duration = (int)msg->duration;
	channel->botconfig_save();
	send_updates_all(channel, "");
	send_updates_all(channel, "control");
}

protected void create(string name) {::create(name);}
