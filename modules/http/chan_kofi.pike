inherit http_websocket;

constant markdown = #"
# Ko-fi integration

## Enabling Ko-fi notifications

Go to [Ko-Fi's configuration](https://ko-fi.com/manage/webhooks) and paste
this value into the Webhook URL: <input readonly value=\"$$webhook_url$$\" size=60>

<form id=kofitoken autocomplete=off>Then take the Verification Token from that page and paste it here:
<input name=token size=40><input type=submit value=\"Save token\"></form>

* TODO:
* Show a list
* of recent
* donations,
* shop sales,
* and new subs.
";

mapping(string:mixed)|string|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	if (req->request_type == "POST") {
		//Ko-fi webhook. Check the Verification Token against the one
		//we have stored, and if it matches, fire all the signals.
		mapping data = Standards.JSON.decode_utf8(req->variables->data); //If malformed, will bomb and send back a 500.
		if (!mappingp(data)) return (["error": 400, "type": "text/plain", "data": "No data mapping given"]);
		mapping cfg = persist_status->path("kofi")[req->misc->channel->name[1..]];
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

		werror("GOT KOFI NOTIFICATION %O\n", data);
		string chan = req->misc->channel->name[1..];
		string amount = data->amount;
		if (amount[<2..] == ".00") amount = amount[..<3];
		amount += " " + data->currency;
		string special;
		mapping params = ([
			"{amount}": amount,
			"{msg}": data->message,
			"{from_name}": data->from_name,
		]);
		if (data->is_subscription_payment) {
			if (data->is_first_subscription_payment) special = "!kofi_sub"; //Resubs aren't currently interesting.
		} else if (arrayp(data->shop_items) && sizeof(data->shop_items)) {
			special = "!kofi_shop";
			params["{shop_item_ids}"] = data->shop_items->direct_link_code * " ";
			//If we could get the item names too, that'd be great.
			//What about quantities??
		} else special = "!kofi_dono";
		if (special) req->misc->channel->trigger_special(special, (["user": chan]), params);
		return "Cool thanks!";
	}
	if (req->misc->is_mod) {
		//NOTE: The token can be set from this page, but will not be shown. It is also
		//not part of the websocket state. This prevents leaks which could result in a
		//fake message being sent, deceiving StilleBot into thinking an event happened.
		req->misc->chaninfo->autoform = req->misc->chaninfo->autoslashform = "";
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
}
