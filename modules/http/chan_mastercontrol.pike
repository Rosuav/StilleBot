inherit http_websocket;
constant markdown = #"# Master Control Panel for $$channel$$

From here, you can make all kinds of really important changes. Maybe.

> ### Danger Zone
>
> Caution: These settings may break things!
{:#dangerzone tag=hgroup}

<style>
#dangerzone {
	margin: 4px;
	border: 5px double red;
	padding: 8px;
}
</style>
";

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	if (!req->misc->is_mod) return render_template("login.md", (["msg": "that the broadcaster use it"]) | req->misc->chaninfo);
	if ((int)req->misc->session->user->id != req->misc->channel->userid)
		return render_template("login.md", (["msg": "that the broadcaster use it. It contains settings so dangerous they are not available to mods. Sorry! If you ARE the broadcaster, please reauthenticate"]) | req->misc->chaninfo);
	return render(req, ([
		"vars": ([
			//"ws_group": "", //Not sure if we need a websocket yet
		]),
	]) | req->misc->chaninfo);
}

string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(msg->group);
	if ((int)conn->session->user->?id != channel->userid) return "Broadcaster only";
	return ::websocket_validate(conn, msg);
}

mapping get_chan_state(object channel, string grp, string|void id) {
	return ([]); //Do we need a websocket?
}

void websocket_cmd_login(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (conn->session->fake) return;

}
