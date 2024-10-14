inherit http_websocket;
inherit hook;

constant markdown = #"
# Integrations

## Enabling Ko-fi notifications

Go to [Ko-Fi's configuration](https://ko-fi.com/manage/webhooks) and paste
this value into the Webhook URL: <input readonly value=\"$$webhook_url$$\" size=60>

<form class=token data-platform=kofi autocomplete=off>Then take the Verification Token from that page and paste it here:
<input name=token id=kofitoken size=40><input type=submit value=\"Save token\"></form>

Once authenticated, Ko-fi events will begin showing up in [Special Triggers](specials),
[Alerts](alertbox#kofi), and [Goal Bars](monitors).

## Enabling Fourth Wall notifications

Go to [Fourth Wall's configuration](https://my-shop.fourthwall.com/admin/dashboard/settings/for-developers?redirect)
and select \"Create webhook\". Paste this value in as the URL: <input readonly value=\"$$webhook_url$$\" size=60>

Select the events you want integrations for; I suggest Order Placed, Gift Purchase, Donation, and
Subscription Purchased. Click Save.

<form class=token data-platform=fourthwall autocomplete=off>There will be a secret signing token on the settings page
that looks something like: `8e7d24cf-66b4-4695-a651-3e744df5a861`<br>Paste it here to complete integration:
<input name=token id=fwtoken size=40><input type=submit value=\"Save token\"></form>

Once this is complete, Fourth Wall events will begin showing up in [Alerts](alertbox#fourthwall) and
anywhere else they end up getting added.

$$loginprompt||$$
";

//NOTE: Currently this is only used by chan_vipleaders, which is alphabetically after
//chan_kofi. If others start using it, it may be necessary to move this to some higher
//level module, which would break encapsulation.
@create_hook: constant kofi_support = ({"object channel", "string type", "mapping params", "mapping raw"});

__async__ mapping(string:mixed)|string http_request(Protocols.HTTP.Server.Request req) {
	if (req->request_type == "POST" && req->variables->data) {
		//Ko-fi webhook. Check the Verification Token against the one
		//we have stored, and if it matches, fire all the signals.
		if (string other = !is_active_bot() && get_active_bot()) {
			werror("Ko-fi integration - forwarding...\n");
			Concurrent.Future fwd = Protocols.HTTP.Promise.post_url("https://" + other + req->not_query,
				Protocols.HTTP.Promise.Arguments((["headers": (["content-type": req->request_headers["content-type"]]), "data": req->body_raw])));
			//Not currently awaiting the promise. Should we?
			return "Passing it along.";
		}
		mapping data = Standards.JSON.decode(req->variables->data); //If malformed, will bomb and send back a 500. (Note: Don't use decode_utf8 here, it's already Unicode text.)
		if (!mappingp(data)) return (["error": 400, "type": "text/plain", "data": "No data mapping given"]);
		mapping cfg = await(G->G->DB->load_config(req->misc->channel->userid, "kofi"));
		if (!stringp(data->verification_token) || cfg->?verification_token != data->verification_token)
			//Note that, if we don't have a token on file, it's guaranteed to be a bad
			//token. This means that any mis-sent POST requests that happen to have a
			//data mapping somehow will just come back "bad token".
			return (["error": 404, "type": "text/plain", "data": "Bad verification token"]);
		//ENSURE: If the message is not public (data->is_public is Val.false), the text
		//should not be shown anywhere (blank it? replace with "Private note"?). The
		//financial value should still be visible though. I think. Check with Ko-fi
		//support folks to ensure that it's okay to reveal the dollar amount of private
		//donations.
		if (data->message && !data->is_public) data->message = "";

		/* Possible notification types:
		Subscription
		- is_subscription_payment && is_first_subscription_payment
		- Fire alert, include message if is_public
		Resubscription
		- is_subscription_payment && !is_first_subscription_payment
		- Ignore. There's no concept of resub messages as there is on Twitch.
		Shop sale
		- shop_items exists and is non-empty array
		- Fire alert, provide item list. May need extra work - can we list item titles?
		Simple donation
		- !is_subscription_payment && !shop_items
		- Fire alert, include message if is_public
		All of the above:
		- Potentially advance a goal bar (according to settings)
		- Fire special trigger
		*/

		Stdio.append_file("kofi.log", sprintf("GOT KOFI NOTIFICATION %O %O\n", req->misc->channel->name, data));
		string chan = req->misc->channel->name[1..];
		string amount = data->amount;
		if (amount[<2..] == ".00") amount = amount[..<3];
		amount += " " + data->currency;
		string special;
		//TODO: What about currencies like JPY, which don't scale the same way?
		//Ko-fi may or may not send us the right number of decimal places.
		sscanf(data->amount, "%d.%d", int dollars, int cents);
		cents += dollars * 100; //TODO: Scale differently for different currencies
		//TODO maybe: Filter to only your currency??? Attempt an approximate conversion?
		//If the latter, just do a lookup and get a value back, and be consistent.
		mapping params = ([
			"{amount}": amount,
			"{cents}": (string)cents,
			"{msg}": data->message,
			"{from_name}": data->from_name,
		]);
		mapping alertparams = ([
			"amount": amount,
			"cents": cents,
			"msg": data->message,
			"username": data->from_name,
		]);
		if (data->is_subscription_payment) {
			if (data->is_first_subscription_payment) special = "!kofi_member"; //Renewals aren't currently interesting.
			alertparams->is_membership = "1";
			alertparams->tiername = params["{tiername}"] = data->tiername || "";
		} else if (arrayp(data->shop_items) && sizeof(data->shop_items)) {
			special = "!kofi_shop";
			if (data->is_public) params["{shop_item_ids}"] = data->shop_items->direct_link_code * " ";
			else params["{shop_item_ids}"] = "";
			alertparams->is_shopsale = "1";
			//If we could get the item names too, that'd be great.
			//What about quantities??
		} else special = "!kofi_dono";
		if (special) {
			//TODO: Replace the others with hooks
			event_notify("kofi_support", req->misc->channel, special, alertparams, data);
			G->G->send_alert(req->misc->channel, "kofi", alertparams);
			req->misc->channel->trigger_special(special, (["user": chan]), params);
		} else special = "!kofi_renew"; //Hack: Goal bars (might) advance on renewals even though nothing else does.
		G->G->goal_bar_autoadvance(req->misc->channel, (["user": chan, "from_name": data->from_name || "Anonymous"]), special[1..], cents);
		return "Cool thanks!";
	}
	if (string sig = req->request_type == "POST" && req->request_headers["x-fourthwall-hmac-sha256"]) {
		//Fourth Wall integration - could be a sale, donation, subscription, etc
		if (string other = !is_active_bot() && get_active_bot()) {
			werror("Fourth Wall integration - forwarding...\n");
			Concurrent.Future fwd = Protocols.HTTP.Promise.post_url("https://" + other + req->not_query,
				Protocols.HTTP.Promise.Arguments((["headers": (["x-fourthwall-hmac-sha256": sig]), "data": req->body_raw])));
			//Not currently awaiting the promise. Should we?
			return "Passing it along.";
		}
		//TODO: Deduplicate based on the ID
		mapping fw = await(G->G->DB->load_config(req->misc->channel->userid, "fourthwall"));
		object signer = Crypto.SHA256.HMAC(fw->verification_token || "");
		if (sig != MIME.encode_base64(signer(req->body_raw))) {
			Stdio.append_file("fourthwall.log", sprintf("\n%sFAILED INTEGRATION for %O: %O\nSig: %O\nHeaders %O\n", ctime(time()), req->misc->channel->login, req->body_raw, sig, req->request_headers));
			return (["error": 418, "data": "My teapot thinks your signature is wrong."]);
		}
		mapping body = Standards.JSON.decode_utf8(req->body_raw);
		mapping data = mappingp(body) && body->data;
		if (!mappingp(data)) return (["error": 400, "data": "No data in body"]);
		foreach ("shipping billing email" / " ", string key) if (data[key]) data[key] = "(...)";
		Stdio.append_file("fourthwall.log", sprintf("\n%s%s INTEGRATION for %O: %O\n", ctime(time()), body->type || "UNKNOWN", req->misc->channel->login, body));
		string special = "!fw_other";
		mapping params = (["{notif_type}": body->type]);
		switch (body->type) {
			case "ORDER_PLACED": special = "!fw_shop"; params = ([
				"{is_test}": (string)body->testMode,
				"{from_name}": data->username || "Anonymous",
				"{amount}": data->amounts->?total->?value + " " + data->amounts->?total->?currency,
				"{msg}": data->message || "",
				"{shop_item_ids}": Array.arrayify(data->offers->?id) * " ",
			]); break;
			case "GIVEAWAY_PURCHASED": special = "!fw_gift"; params = ([
				"{from_name}": data->username || "Anonymous",
				"{amount}": data->amounts->?total->?value + " " + data->amounts->?total->?currency,
				"{msg}": data->message || "",
				"{shop_item_ids}": Array.arrayify(data->offer->?id) * " ",
			]); break;
			case "DONATION": special = "!fw_dono"; params = ([
				"{from_name}": data->username || "Anonymous",
				"{amount}": data->amounts->?total->?value + " " + data->amounts->?total->?currency,
				"{msg}": data->message || "",
			]); break;
			//TODO: Check this against what we see in the log
			case "SUBSCRIPTION_PURCHASED": special = "!fw_member"; params = ([
				"{from_name}": data->username || "Anonymous",
				"{amount}": data->amounts->?total->?value + " " + data->amounts->?total->?currency,
				"{msg}": data->message || "",
			]); break;
			default: break;
		}
		if (special != "!fw_other") G->G->send_alert(req->misc->channel, "fourthwall", ([
			"username": data->username || "Anonymous",
			"amount": (string)data->amounts->?total->?value,
			"msg": data->message || "",
		]));
		req->misc->channel->trigger_special(special, (["user": req->misc->channel->login]), params);
		int|float amount = data->amounts->?total->?value;
		if (floatp(amount)) amount = (int)(amount * 100 + 0.5); else amount *= 100;
		if (amount) G->G->goal_bar_autoadvance(req->misc->channel, (["user": req->misc->channel->login, "from_name": data->username || "Anonymous"]), special[1..], amount);
		return "Awesome, thanks!";
	}
	if (req->misc->is_mod) {
		return render(req, ([
			"vars": (["ws_group": ""]),
			"webhook_url": sprintf("%s/channels/%s/integrations",
				G->G->instance_config->http_address,
				req->misc->channel->name[1..]),

		]) | req->misc->chaninfo);
	}
	return render(req, ([
		"webhook_url": "",
		"loginprompt": "[Log in to make changes](:.twitchlogin)",
	]) | req->misc->chaninfo);
}

@"is_mod": __async__ void wscmd_settoken(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!stringp(msg->token)) return;
	if (!(<"kofi", "fourthwall">)[msg->platform]) return;
	await(G->G->DB->mutate_config(channel->userid, msg->platform) {mapping cfg = __ARGS__[0];
		cfg->verification_token = msg->token;
	});
	send_updates_all(conn->group);
}

bool need_mod(string grp) {return 1;}
__async__ mapping get_chan_state(object channel, string grp, string|void id) {
	mapping kofi = await(G->G->DB->load_config(channel->userid, "kofi"));
	mapping fw = await(G->G->DB->load_config(channel->userid, "fourthwall"));
	return ([
		"kofitoken": stringp(kofi->verification_token) && "..." + kofi->verification_token[<3..],
		"fwtoken": stringp(fw->verification_token) && "..." + fw->verification_token[<3..],
	]);
}

protected void create(string name) {::create(name);}
