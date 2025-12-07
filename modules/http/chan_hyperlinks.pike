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

<style>
select:not(:has( [value="timeout"]:checked)) ~ .timeout-duration {display: none;}
</style>

$$save_or_login$$
#};

@retain: mapping(int:mapping(int:int)) hyperlink_bans = ([]);

constant hyperlink = special_trigger("!hyperlink", "A user posted a hyperlink (if filtering is active)", "The user", ([
	"{offense}": "0 if given a permit, else number of times they've posted links this stream",
	"{msg}": "The message that was posted",
]), "Status");

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
	if (grp == "control") {
		//TODO: Filter to just moderators (and the broadcaster). This could be done if we have permission
		//from the broadcaster (moderation:read or channel:manage:moderators), or from the voice in question
		//(user:read:moderated_channels), so we could guarantee to check this for Rosuav and MustardMine,
		//but not always for arbitrary voices. Maybe just filter out MM if not a mod?
		mapping voices = G->G->DB->load_cached_config(channel->userid, "voices");
		array vox = values(voices); sort((array(int))indices(voices), vox);
		return (channel->botconfig->hyperlinks || ([])) | (["voices": vox]);
	}
	//TODO: Reduced info for non-mods
	return ([]);
}

//Common TLDs that might be being linked to in simple two-part form. Don't bother with any TLD that
//only registers within its subdomains (eg "au", where you won't be posting "spam.au" but "spam.com.au")
//as they will be caught by the two-dot check. Also, this only needs to catch links that don't have a
//path after them, eg "twitch.tv/rosuav" will be caught by the "has a slash" check.
constant common_tlds = (<
	"com", "net", "org", //The classics
	"name", "biz", "info", "edu", "gov", "mil", //Others that might come up, albeit less commonly
	"xxx", //If someone posts a .xxx link, it almost certainly needs to be blocked.
>);

int(1bit) contains_link(string msg) {
	if (has_value(msg, "HTTPKICKME")) return 1; //For testing, we actually block the word HTTPKICKME, to ensure that other bots don't ban for it.
	//If you have anything that looks like a protocol, even not at the start of a word, it's a link.
	if (has_value(msg, "http://") || has_value(msg, "https://")) return 1;
	foreach (msg / " ", string word) {
		sscanf(word, "%*s.%s", string tail);
		if (!tail || tail == "") continue; //No dot, no link.
		//NOTE: At present, we only check for ASCII alphabetics after the dot. Non-Latin scripts may well
		//not get caught here. As of 20251117, these do not get autolinked by Twitch, so they won't be
		//clickable; thus they are less relevant for blocking, as they're harder to accidentally go to.
		//This may need to be reviewed in the future, but for now I will only block ASCII links.
		if (sscanf(tail, "%s.%[A-Za-z]", string alpha1, string alpha2) && alpha1 && alpha2 && alpha1 != "" && alpha2 != "") return 1; //eg www.example.com or kepl.com.au, but not 11.5.2025
		if (common_tlds[tail]) return 1;
		if (has_value(tail, "/")) return 1; //eg instagram.com/something
	}
}

@hook_allmsgs: int message(object channel, mapping person, string msg) {
	mapping cfg = channel->config->hyperlinks || ([]);
	if (!cfg->blocked) return 0; //All links are permitted, no filtering is being done
	if (person->badges->?_mod) {
		//Mods are always permitted, no matter what settings we have. Check for a !permit magic command,
		//or maybe this should be an explicit builtin?? Note that there's no message in chat here.
		if (has_value(cfg->permit, "permit") && sscanf(msg, "!permit %*[@]%s", string user) && user) get_user_id(user)->then() {
			mapping bans = hyperlink_bans[channel->userid];
			if (!bans) bans = hyperlink_bans[channel->userid] = ([]);
			bans[__ARGS__[0]] = -1;
			werror("%O\n", bans);
		};
		return 0;
	}
	if (!cfg->warnings || !sizeof(cfg->warnings)) return 0; //No actions to be taken against links
	if (!contains_link(msg)) return 0; //No link? No problem.
	if (person->badges->?vip && has_value(cfg->permit, "vip")) return 0;
	if (channel->raiders[person->uid] && has_value(cfg->permit, "raider")) return 0;
	//If we got this far, the user probably needs to be punished.
	mapping bans = hyperlink_bans[channel->userid];
	if (!bans) bans = hyperlink_bans[channel->userid] = ([]);
	//Humans will talk about "strike one" as the first, but since we're looking up in an array,
	//the first offense is strike 0.
	int strike = bans[person->uid]++;
	channel->trigger_special("!hyperlink", person, (["{offense}": (string)(strike + 1), "{msg}": msg]));
	if (strike < 0) return 0; //Actually, no punishment; the user had a permit (aka "Get Out Of Jail Free Card")
	if (strike >= sizeof(cfg->warnings)) strike = sizeof(cfg->warnings) - 1;
	//TODO: If we don't have moderator:manage:banned_users on the broadcaster, demand that a voice
	//be selected. Otherwise this will just fail.
	int voiceid = cfg->voice || channel->userid;
	mapping warn = cfg->warnings[strike];
	if (warn->msg != "") channel->send(person, (["message": warn->msg, "voice": (string)voiceid]));
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
	cfg->warnings += ({(["action": "warn", "msg": ""])});
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
	if (msg->action == "purge") {warn->action = "timeout"; warn->duration = 1;} //A purge is a short timeout, and is indistinguishable from same.
	else if (msg->action == "timeout" && warn->action != "timeout") {warn->action = "timeout"; warn->duration = 60;} //The timeout can be configured afterwards, but default to a minute.
	else if ((<"warn", "delete", "ban">)[msg->action]) warn->action = msg->action;
	channel->botconfig_save();
	send_updates_all(channel, "");
	send_updates_all(channel, "control");
}

@"is_mod": void wscmd_configure(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping cfg = channel->botconfig->hyperlinks;
	if (!cfg) cfg = channel->botconfig->hyperlinks = ([]);
	if ((int)msg->voice) cfg->voice = (int)msg->voice;
	channel->botconfig_save();
	send_updates_all(channel, "");
	send_updates_all(channel, "control");
}

protected void create(string name) {::create(name);}
