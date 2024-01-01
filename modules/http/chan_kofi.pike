inherit http_websocket;
inherit hook;

constant markdown = #"
# Ko-fi integration

## Enabling Ko-fi notifications

Go to [Ko-Fi's configuration](https://ko-fi.com/manage/webhooks) and paste
this value into the Webhook URL: <input readonly value=\"$$webhook_url$$\" size=60>

<form id=kofitoken autocomplete=off>Then take the Verification Token from that page and paste it here:
<input name=token size=40><input type=submit value=\"Save token\"></form>

Once authenticated, Ko-fi events will begin showing up in [Special Triggers](specials),
[Alerts](alertbox#kofi), and [Goal Bars](monitors).
";

//NOTE: Currently this is only used by chan_vipleaders, which is alphabetically after
//chan_kofi. If others start using it, it may be necessary to move this to some higher
//level module, which would break encapsulation.
@create_hook: constant kofi_support = ({"object channel", "string type", "mapping params", "mapping raw"});

mapping(string:mixed)|string|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	if (req->request_type == "POST") {
		//Ko-fi webhook. Check the Verification Token against the one
		//we have stored, and if it matches, fire all the signals.
		mapping data = Standards.JSON.decode(req->variables->data); //If malformed, will bomb and send back a 500. (Note: Don't use decode_utf8 here, it's already Unicode text.)
		if (!mappingp(data)) return (["error": 400, "type": "text/plain", "data": "No data mapping given"]);
		mapping cfg = persist_status->has_path("kofi", req->misc->channel->name[1..]);
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
		G->G->goal_bar_autoadvance(req->misc->channel, (["user": chan]), special[1..], cents);
		return "Cool thanks!";
	}
	if (req->misc->is_mod) {
		return render(req, ([
			"vars": (["ws_group": ""]),
			"webhook_url": sprintf("%s/channels/%s/kofi",
				persist_config["ircsettings"]->http_address,
				req->misc->channel->name[1..]),

		]) | req->misc->chaninfo);
	}
	return render(req, ([
		"webhook_url": "",
	]) | req->misc->chaninfo);
}

@"is_mod": void wscmd_settoken(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!stringp(msg->token)) return;
	mapping cfg = persist_status->path("kofi", channel->name[1..]);
	cfg->verification_token = msg->token;
	persist_status->save();
	send_updates_all(conn->group);
}

bool need_mod(string grp) {return 1;}
mapping get_chan_state(object channel, string grp) {
	mapping cfg = persist_status->path("kofi", channel->name[1..]);
	return ([
		"token": stringp(cfg->verification_token) && "..." + cfg->verification_token[<3..],
	]);
}

protected void create(string name) {::create(name);}
