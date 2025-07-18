inherit http_websocket;
inherit builtin_command;
inherit annotated;

constant markdown = #"# External notifications

Create an app that connects to Mustard Mine. A websocket will notify you whenever
something happens. That something is entirely under your control (as the broadcaster).

Note that there is (deliberately) no security, no requirement for a login. This allows
these notifications to be received by browser sources inside OBS, or similar.

[Example page](/static/notifdemo.html :target=_blank) This can be adapted to your needs.
Open both that page and this in separate windows, and whenever you click the 'Notify'
button here, that page will respond. The same notification can be sent by a bot command,
channel point redemption, special trigger, or anything else that the bot can respond to.

Currently active notification groups:

Group | Clients | Notify
------|---------|--------
loading... | -  |-
{:#notifgroups}

Click the 'Loopback' notify button to increment this counter: <span id=loopbacks>0</span>
";

constant builtin_name = "Notify";
constant builtin_description = "Send a notification to API users";
constant builtin_param = ({"Group", "Parameter"});
constant vars_provided = ([
	"{clients}": "Number of clients that the message was sent to",
]);

mapping message_params(object channel, mapping person, array param, mapping cfg) {
	array socks = websocket_groups[param[0] + "#" + channel->userid] || ({ });
	int sent = 0;
	string text = Standards.JSON.encode((["cmd": "notify", "parameter": param[1]]), 4);
	foreach (socks, object sock)
		if (sock && sock->state == 1) {++sent; sock->send_text(text);}
	return (["{clients}": (string)sent]);
}

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	if (!req->misc->is_mod) return render_template("login.md", (["msg": "moderator privileges"]) | req->misc->chaninfo);
	return render(req, ([
		"vars": (["ws_group": ""]),
	]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return grp != "";}
__async__ mapping get_chan_state(object channel, string grp, string|void id) {
	if (grp == "") {
		mapping groups = ([]);
		string suf = "#" + channel->userid;
		foreach (websocket_groups; string groupname; array socks)
			if (has_suffix(groupname, suf)) foreach (socks, object sock)
				if (sock && sock->state == 1) ++groups[groupname - suf];
		m_delete(groups, ""); //No need to report the master socket group
		return (["groups": groups]);
	}
	return ([]); //No default data needed
}

@"demo_ok": void wscmd_init(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (conn->subgroup != "") send_updates_all(channel, "");
}
void websocket_gone(mapping(string:mixed) conn) {
	[object channel, string subgroup] = split_channel(conn->group);
	if (subgroup != "") send_updates_all(channel, "");
}

@"demo_ok": void wscmd_send_notif(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (conn->subgroup != "" || !stringp(msg->group)) return;
	message_params(channel, ([]), ({msg->group, ""}), ([]));
}

protected void create(string name) {::create(name);}
