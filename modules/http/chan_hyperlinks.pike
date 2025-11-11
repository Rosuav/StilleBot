inherit http_websocket;
inherit builtin_command;

constant markdown = #{# Hyperlink blocking for $$channel$$

Posting of hyperlinks can be blocked in your Twitch Dashboard. If they are, none of these
settings will take effect, and non-moderators will not be able to post any links.
Go to [your dashboard](https://dashboard.twitch.tv/moderation/settings) and "Show All Advanced
Settings" if necessary, then scroll down to "Block Hyperlinks" and ensure that it is disabled.

<table id=permitted></table>

	
$$save_or_login||$$
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
	//TODO: Read-only view so people can see what the settings are
	if (!req->misc->is_mod) return render_template(markdown, ([
		"loadingmsg": "TODO",
	]) | req->misc->chaninfo);
	return render(req, ([
		"vars": (["ws_group": ""]),
		"save_or_login": "[Save all](:#saveall)",
	]) | req->misc->chaninfo);
}

protected void create(string name) {::create(name);}
