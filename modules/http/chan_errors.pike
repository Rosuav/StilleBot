inherit http_websocket;

constant markdown = #"
# Channel Error Log

Errors that happen during bot operation will be shown here.

[x] Errors [x] Warnings [ ] Info

Timestamp | Level | Message | Context
----------|-------|---------|---------
- | - | - | loading...
{:#msglog}

";

mapping(string:mixed)|string|Concurrent.Future http_request(Protocols.HTTP.Server.Request req) {
	if (!req->misc->is_mod) return render_template("login.md", (["msg": "moderator status"]) | req->misc->chaninfo);
	return render(req, ([
		"vars": (["ws_group": ""]),
	]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return 1;}
mapping get_chan_state(object channel, string grp) {
	mapping cfg = persist_status->path("errors", channel);
	return ([
		"items": cfg->msglog || ({ }),
		//Others incl which should be shown by default
	]);
}
