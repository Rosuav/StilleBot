inherit http_websocket;
constant markdown = #"# Leaderboards and VIPs

$$save_or_login$$
";

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	return render(req, ([
		"vars": (["ws_group": "control" * req->misc->is_mod]),
		"save_or_login": "(logged in)",
	]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return grp == "control";}
mapping get_chan_state(object channel, string grp, string|void id) {
	return ([]);
}
