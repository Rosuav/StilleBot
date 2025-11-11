inherit http_websocket;
inherit builtin_command;

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
	mapping cfg = channel->config->hyperlinks || ([]);
}

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

protected void create(string name) {::create(name);}
