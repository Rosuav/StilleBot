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
mapping get_chan_state(object channel, string grp, string|void id) {
	mapping err = persist_status->path("errors", channel);
	if (id) {
		foreach (err->msglog || ({}), mapping msg)
			if (msg->id == id) return msg;
		return 0;
	}
	return ([
		"items": err->msglog || ({ }),
		//Others incl which levels should be shown by default
	]);
}
