inherit http_websocket;
constant markdown = #"# Who Funds Me?

<div id=error></div>

## Donation total
{:#total}

* loading...
{:#donos}

$$chattoggle$$

[Drag to OBS as a browser source for an onscreen dono total](/whofundsme?summarycolor=rebeccapurple)
";

constant URL = "https://www.gofundme.com/f/marvincharitystream2021";
mapping state = (["donations": ({ })]);

mapping get_state(string group, string|void id) {return state;}

continue Concurrent.Future do_check() {
	werror("Checking whofundsme [%d clients]...\n", sizeof(websocket_groups[""]));
	multiset seen_ids = G->G->whofundsme_seen_ids; if (!seen_ids) seen_ids = G->G->whofundsme_seen_ids = (<>);
	object result = yield(Protocols.HTTP.Promise.get_url(URL)->thencatch() {return __ARGS__[0];}); //Send failures through as results, not exceptions
	if (result->status != 200) {
		state->error = "Got unexpected status code " + result->status;
		send_updates_all("");
		return 0;
	}
	//There's a script tag that dumps great data straight into the global object.
	sscanf(result->get(), "%*swindow.initialState = %s;</script>", string text);
	text = replace(text, "&#039;", "'"); //TODO: Decode properly
	mapping info = Standards.JSON.decode(text);
	mapping campaign = info["feed"]["campaign"];
	string currency = campaign["currencycode"];
	string total = sprintf("%d %s", campaign["current_amount"], currency);
	int changed = total != state->total;
	state->total = total;
	state->currency = currency;
	//Scan the donations oldest first. New ones will get added underneath.
	state->donations = reverse(info["feed"]["donations"]);
	foreach (state->donations, mapping dono) {
		string id = dono["donation_id"];
		if (seen_ids[id]) continue;
		seen_ids[id] = 1;
		changed = 1;
		write("%s donated %d %s\n", dono["name"], dono["amount"], currency);
		foreach (G->G->whofundsme_announce; string chan; int state) if (state)
			send_message("#" + chan, sprintf("/me maayaSpoiled %s donated %d %s maayaSpoiled\n", dono["name"], dono["amount"], currency));
		if (dono["comment"])
			write(dono["comment"] + "\n");
	}
	if (changed) send_updates_all("");
}

void check() {
	if (mixed id = G->G->whofundsme_callout) remove_call_out(id);
	if (!sizeof(websocket_groups[""])) return;
	G->G->whofundsme_callout = call_out(check, 1800);
	handle_async(do_check()) { };
}

mapping(string:mixed)|string|Concurrent.Future http_request(Protocols.HTTP.Server.Request req) {
	if (!G->G->whofundsme_announce) G->G->whofundsme_announce = ([]);
	string username = req->misc->session->?user->?login;
	check();
	if (req->variables->summarycolor) return render_template("monitor.html", ([
		"styles": "#display {font-size: 72px; color: " + req->variables->summarycolor + "}",
		"vars": (["ws_type": ws_type, "ws_group": "", "ws_code": "whofundsme"]),
	]));
	return render(req, ([
		"vars": (["ws_group": ""]),
		"chattoggle": !username ? "[Log in to enable chat](/twitchlogin?next=/whofundsme)" :
			G->G->whofundsme_announce[username] ? "[Disable announcements in " + username + " chat](:#chattoggle)" :
			"[Enable announcements in " + username + " chat](:#chattoggle)",
	]));

}

void websocket_cmd_chattoggle(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	string username = conn->session->?user->?login;
	if (!username) return;
	int state = !G->G->whofundsme_announce[username];
	G->G->whofundsme_announce[username] = state;
	conn->sock->send_text(Standards.JSON.encode((["cmd": "chatbtn", "label": ({"En", "Dis"})[state] + "able announcements in " + username + " chat"]), 4));
	send_message("#" + username, state ? "New donations will be announced here." : "Halting announcements in this channel.");
}
