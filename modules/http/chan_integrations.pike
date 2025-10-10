inherit http_websocket;
inherit hook;
inherit annotated;

/* TODO: UI to configure global settings.

Currently, Patreon's clientid/secret are stored in instance-config.json, which requires copying those
to each instance. Instead, migrate them to G->G->DB->load_config(0, "patreon") to match the way that
Fourth Wall secrets are stored.

There is currently no UI to configure these. It's an unusual thing to need to do, but it will happen,
so it would be useful to have somewhere.

Fourth Wall: hmac_key, clientid, secret
Patreon: (eventually) clientid, secret
*/

//Used both in /c/integrations normal mode, and the mini mode for embeds
constant fourthwall_integrations = #"
Available integrations:
* [Alerts]($$fwembed1||$$alertbox#fourthwall$$fwembed2||$$) on shop sales, donations, etc
* [Chat responses]($$fwembed1||$$specials#Fourth-Wall$$fwembed2||$$) on shop sales, donations, etc
* [Goal bars]($$fwembed1||$$monitors$$fwembed2||$$) that advance based on activity on your shop and/or elsewhere
* Coming Soon: Create giveaway links from chat commands, channel point redemptions, or anything else!
";

constant markdown = #"
# Support Platform Integrations

Mustard Mine can integrate with several other web sites where your community can support you.
When linked together, these services can trigger actions within the bot, such as goal bar
advancement, on-stream alerts, or in-chat appreciative notes.

## Ko-fi

Go to [Ko-Fi's configuration](https://ko-fi.com/manage/webhooks) and paste
this value into the Webhook URL: <input readonly value=\"$$webhook_url$$\" size=60>

<form class=token data-platform=kofi autocomplete=off>Then take the Verification Token from that page and paste it here:
<input name=token id=kofitoken size=40><input type=submit value=\"Save token\"></form>

Once authenticated, Ko-fi events will begin showing up in [Special Triggers](specials),
[Alerts](alertbox#kofi), and [Goal Bars](monitors).

## Fourth Wall

[Link your Fourth Wall shop](:#fwlogin)
{:#fwstatus}

" + fourthwall_integrations + #"

## Patreon

[Link your Patreon account](:#patreonlogin)
{:#patreonstatus}

When linked, Patreon events will begin showing up in [Alerts](alertbox#patreon), [Special Triggers](specials),
and [Goal Bars](monitors).

$$loginprompt||$$

> ### Current Patrons
>
> Your current patrons are:
>
> * loading...
> {: #patrons}
>
> [Close](:.dialog_close)
{: tag=dialog #patrondlg}

<style>
.avatar {max-width: 1.5em;}
vertical-align: middle;
</style>
";

constant platform_config_fields = ([
	"kofi": (<"token">),
	"fourthwall": (<"token">), //Shouldn't need this, ideally - it should all be done with OAuth.
]);

//NOTE: Currently this is only used by chan_vipleaders, which is alphabetically after
//chan_kofi. If others start using it, it may be necessary to move this to some higher
//level module, which would break encapsulation.
@create_hook: constant kofi_support = ({"object channel", "string type", "mapping params", "mapping raw"});

constant kofi_dono = special_trigger("!kofi_dono", "Donation received on Ko-fi.", "The broadcaster", "amount, msg, from_name", "Ko-fi");
constant kofi_member = special_trigger("!kofi_member", "New monthly membership on Ko-fi.", "The broadcaster", "amount, msg, from_name, tiername", "Ko-fi");
constant kofi_shop = special_trigger("!kofi_shop", "Shop sale on Ko-fi.", "The broadcaster", "amount, msg, from_name, shop_item_ids, shop_item_count", "Ko-fi");
constant fw_dono = special_trigger("!fw_dono", "Donation received on Fourth Wall.", "The broadcaster", "amount, msg, from_name", "Fourth Wall");
constant fw_member = special_trigger("!fw_member", "New monthly membership on Fourth Wall.", "The broadcaster", "amount, msg, from_name", "Fourth Wall");
constant fw_shop = special_trigger("!fw_shop", "Shop sale on Fourth Wall.", "The broadcaster", "is_test, amount, msg, from_name, shop_item_ids", "Fourth Wall");
constant fw_gift = special_trigger("!fw_gift", "Gift purchase on Fourth Wall.", "The broadcaster", "amount, msg, from_name, shop_item_ids", "Fourth Wall");
constant fw_other = special_trigger("!fw_other", "Other notification from Fourth Wall - not usually useful.", "The broadcaster", "notif_type", "Fourth Wall");

int to_cents(int|float amount) {
	if (floatp(amount)) return (int)(amount * 100 + 0.5);
	return (amount || 0) * 100;
}

__async__ mapping(string:mixed)|string http_request(Protocols.HTTP.Server.Request req) {
	if (!req->misc->channel->userid && req->variables->shop_id && req->variables->hmac) {
		//We're embedded in the Fourth Wall page.
		//Special case: If you aren't logged in, but the page is actually a Fourth Wall embed,
		//grant access as if logged in as the broadcaster. Note that this special access
		//should apply ONLY to Fourth Wall configs, and only if the HMAC checks out.
		//This will become relevant when quick-activation buttons are added (see fourthwall_integrations above).
		return render_template("# Mustard Mine + Fourth Wall\n" + fourthwall_integrations, ([
			//Make all the links take you to your own site (if logged in) in another tab
			"fwembed1": "/c/",
			"fwembed2": " :target=_blank",
		]));
	}
	if (string other = req->request_type == "POST" && !is_active_bot() && get_active_bot()) {
		//POST requests are likely to be webhooks. Forward them to the active bot, including whichever
		//of the relevant headers we spot. Add headers to this as needed.
		constant headers = (<"x-fourthwall-hmac-apps-sha256", "x-fourthwall-hmac-sha256", "content-type", "x-patreon-event", "x-patreon-signature">);
		werror("Forwarding webhook...\n");
		Concurrent.Future fwd = Protocols.HTTP.Promise.post_url("https://" + other + req->not_query,
			Protocols.HTTP.Promise.Arguments((["headers": req->request_headers & headers, "data": req->body_raw])));
		//As above, not currently awaiting the promise. Should we?
		return "Passing it along.";
	}
	if (req->request_type == "POST" && req->variables->data) {
		//Ko-fi webhook. Check the Verification Token against the one
		//we have stored, and if it matches, fire all the signals.
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
			if (data->is_public) {
				params["{shop_item_ids}"] = data->shop_items->direct_link_code * " ";
				params["{shop_item_count}"] = `+(0, @data->shop_items->quantity);
			}
			else params["{shop_item_ids}"] = params["{shop_item_count}"] = "";
			alertparams->is_shopsale = "1";
			//If we could get the item names too, that'd be great.
			//What about quantities??
		} else if (data->type == "Commission") {
			//TODO maybe: Switch to looking at data->type for most things?
			special = "!kofi_commission"; //TODO: Actually make this special (currently just does the goal bar)
			alertparams->is_commission = "1";
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
	if (string sig = req->request_type == "POST" && req->request_headers["x-fourthwall-hmac-apps-sha256"]) {
		//Fourth Wall integration - could be a sale, donation, subscription, etc
		//TODO: Deduplicate based on the ID
		mapping fw = await(G->G->DB->load_config(req->misc->channel->userid, "fourthwall"));
		mapping fw_core = await(G->G->DB->load_config(0, "fourthwall"));
		object signer = Crypto.SHA256.HMAC(fw_core->hmac_key || "");
		if (sig != MIME.encode_base64(signer(req->body_raw))) {
			werror("Fourth Wall webhook - Failed check with core hmac\n");
			//It might be a deprecated legacy hook, with a unique verification token for each shop.
			//Newer hooks will all use the application key from fw_core, but try this key too.
			//Note that the signature is in a different header here.
			signer = Crypto.SHA256.HMAC(fw->verification_token || "");
			if (req->request_headers["x-fourthwall-hmac-sha256"] != MIME.encode_base64(signer(req->body_raw))) {
				werror("Fourth Wall webhook - Also failed check with unique token\n");
				Stdio.append_file("fourthwall.log", sprintf("\n%sFAILED INTEGRATION for %O: %O\nSig: %O\nHeaders %O\n", ctime(time()), req->misc->channel->login, req->body_raw, sig, req->request_headers));
				return (["error": 418, "data": "My teapot thinks your signature is wrong."]);
			}
		}
		mapping body = Standards.JSON.decode_utf8(req->body_raw);
		mapping data = mappingp(body) && body->data;
		if (!mappingp(data)) return (["error": 400, "data": "No data in body"]);
		string billing_country = data->billing->?address->?country || "";
		//Suppress personal information in the log. Test messages (triggered from the Fourth Wall UI)
		//have fake personal info, so we can keep those and thus easily see the actual message structure.
		if (!body->testMode) foreach ("shipping billing email" / " ", string key) if (data[key]) data[key] = "(...)";
		Stdio.append_file("fourthwall.log", sprintf("\n%s%s INTEGRATION for %O: %O\n", ctime(time()), body->type || "UNKNOWN", req->misc->channel->login, body));
		string special = "!fw_other";
		mapping params = (["{notif_type}": body->type]);
		string message = Parser.parse_html_entities(data->message || "");
		switch (body->type) {
			case "ORDER_PLACED": special = "!fw_shop"; params = ([
				"{is_test}": (string)body->testMode,
				"{from_name}": data->username || "Anonymous",
				"{amount}": data->amounts->?total->?value + " " + data->amounts->?total->?currency,
				"{msg}": message,
				"{shop_item_ids}": Array.arrayify(data->offers->?id) * " ",
			]); break;
			case "GIFT_PURCHASE": special = "!fw_gift"; params = ([
				"{from_name}": data->username || "Anonymous",
				"{amount}": data->amounts->?total->?value + " " + data->amounts->?total->?currency,
				"{msg}": message,
				"{shop_item_ids}": Array.arrayify(data->offer->?id) * " ",
			]); break;
			case "DONATION": special = "!fw_dono"; params = ([
				"{from_name}": data->username || "Anonymous",
				"{amount}": data->amounts->?total->?value + " " + data->amounts->?total->?currency,
				"{msg}": message,
			]); break;
			//TODO: Check this against what we see in the log
			case "SUBSCRIPTION_PURCHASED": special = "!fw_member"; params = ([
				"{from_name}": data->username || "Anonymous",
				"{amount}": data->amounts->?total->?value + " " + data->amounts->?total->?currency,
				"{msg}": message,
			]); break;
			case "GIFT_DRAW_STARTED": case "GIFT_DRAW_ENDED": return "Thanks!"; //Don't count these, they're going to be duplicates
			default: break;
		}
		if (special != "!fw_other") G->G->send_alert(req->misc->channel, "fourthwall", ([
			"username": data->username || "Anonymous",
			"amount": (string)data->amounts->?total->?value,
			"msg": data->message || "",
		]));
		int grossamount = to_cents(data->amounts->?total->?value);
		//To calculate the profit on a sale, we take the total amount as above, then remove the following:
		//1) Shipping
		//2) Tax
		//3) Cost of Goods Sold (summed from offers[*]->cost)
		//4) And the transaction fee. This is the hard part.
		//For now, I am ignoring Buy Now Pay Later (which has significantly higher fees) and PayPal (which has
		//slightly higher fees). The two fee schedules listed on the Fourth Wall docs are, as of 20250904:
		//https://help.fourthwall.com/hc/en-us/articles/13331335648283-Transaction-fees
		//Domestic 2.9% + 30c, International 3.9% + 30c.
		int netamount = grossamount;
		//Note that these calculations might be off by a little, but hopefully not hugely.
		if (data->amounts) netamount -= 30; //Assume a baseline 30c fee on every sale or sale-adjacent action
		if (billing_country == fw->country) //If you haven't set a billing country, all countries will be calculated as foreign.
			netamount -= (int)(netamount * .029);
		else
			netamount -= (int)(netamount * .039);
		netamount -= to_cents(data->amounts->?shipping->?value);
		netamount -= to_cents(data->amounts->?prepaidShipping->?value); //Gifts can have an allocation to shipping, though the exact figure isn't known until a winner is selected
		netamount -= to_cents(data->amounts->?tax->?value);
		foreach (Array.arrayify(data->offers), mapping offer)
			netamount -= to_cents(offer->variant->?cost->?value) || 15; //Digital items have a fee of 15c, which isn't given in the cost field.
		if (netamount) Stdio.append_file("fourthwall.log", sprintf("Calculated profit: %O\n", netamount));
		params["{profit}"] = (string)netamount;
		req->misc->channel->trigger_special(special, (["user": req->misc->channel->login]), params);
		if (grossamount) G->G->goal_bar_autoadvance(req->misc->channel,
			(["user": req->misc->channel->login, "from_name": data->username || "Anonymous"]),
			special[1..], grossamount,
			([
				"partials": (["fw_dono": to_cents(data->amounts->?donation->?value)]), //For shop orders that also include a donation portion.
				"net": netamount,
			]),
		);
		return "Awesome, thanks!";
	}
	if (string sig = req->request_type == "POST" && req->request_headers["x-patreon-signature"]) {
		mapping secret = await(G->G->DB->load_config(req->misc->channel->userid, "patreon"))->hook_secret;
		object signer = Crypto.MD5.HMAC(secret || "-");
		if (req->request_headers["x-patreon-signature"] != String.string2hex(signer(req->body_raw)))
			return (["error": 418, "data": "My teapot thinks your signature is wrong."]);
		mapping body = Standards.JSON.decode_utf8(req->body_raw);
		werror("Got a Patreon %O notification: %O\n", req->request_headers["x-patreon-event"], body);
		return "Thanks!";
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
	if (!(<"kofi", "fourthwall">)[msg->platform]) return;
	await(G->G->DB->mutate_config(channel->userid, msg->platform) {mapping cfg = __ARGS__[0];
		foreach (platform_config_fields[msg->platform]; string field;) {
			//Special case: "token" is stored as "verification_token" for hysterical raisins
			string fld = field == "token" ? "verification_token" : field;
			if (msg[field] == "") m_delete(cfg, fld);
			else if (msg[field]) cfg[fld] = msg[field];
		}
	});
	send_updates_all(conn->group);
}

bool need_mod(string grp) {return 1;}
__async__ mapping get_chan_state(object channel, string grp, string|void id) {
	mapping kofi = await(G->G->DB->load_config(channel->userid, "kofi"));
	mapping fw = await(G->G->DB->load_config(channel->userid, "fourthwall"));
	mapping pat = await(G->G->DB->load_config(channel->userid, "patreon"));
	return ([
		"kofitoken": stringp(kofi->verification_token) && "..." + kofi->verification_token[<3..],
		"fwtoken": stringp(fw->verification_token) && "..." + fw->verification_token[<3..], //Deprecated
		"fwshopname": fw->refresh_token && fw->shopname, //This one's the flag - if absent, the front end assumes no FW config
		"fwurl": fw->url, "fwusername": fw->username,
		"fwcountry": fw->country || "",
		"paturl": pat->campaign_url, //May be null
	]);
}

//Note that this message comes to the bot that's active as of when you click the button,
//and the eventual redirect from Patreon will come to the bot that's active at that time.
//If there's a bot handover during that time, the login will have to be restarted.
@"is_mod": @"demo_ok": mapping wscmd_patreonlogin(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	string tok = String.string2hex(random_string(8));
	G->G->patreon_csrf_states[tok] = (["timestamp": time(), "channel": channel->userid]);
	object uri = Standards.URI("https://www.patreon.com/oauth2/authorize");
	uri->set_query_variables(([
		"response_type": "code",
		"scope": "identity campaigns w:campaigns.webhook campaigns.members",
		"client_id": G->G->instance_config->patreon_clientid,
		"redirect_uri": "https://" + G->G->instance_config->local_address + "/patreon", //Or should it always go to mustardmine.com?
		"state": tok,
	]));
	return (["cmd": "oauthpopup", "uri": (string)uri]);
}

@"is_mod": __async__ mapping|zero wscmd_resyncpatreon(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping lookup = await(G->G->DB->load_config(0, "patreon"))->twitch_from_patreon || ([]);
	mapping cfg = await(G->G->DB->load_config(channel->userid, "patreon"));
	if (!cfg->campaign_url) return 0;
	//Is it worth retaining the campaign ID? What if there are multiple? CAN there ever be multiple?
	object res = await(Protocols.HTTP.Promise.get_url("https://www.patreon.com/api/oauth2/v2/campaigns",
		Protocols.HTTP.Promise.Arguments((["headers": ([
			"Authorization": "Bearer " + cfg->auth->access_token,
		])]))
	));
	mapping campaigns = Standards.JSON.decode_utf8(res->get());
	string cpid = campaigns->data[0]->id;
	array members = ({ });
	do {
		res = await(Protocols.HTTP.Promise.get_url("https://www.patreon.com/api/oauth2/v2/campaigns/" + cpid + "/members?include=user&fields[member]=currently_entitled_amount_cents,full_name",
			Protocols.HTTP.Promise.Arguments((["headers": ([
				"Authorization": "Bearer " + cfg->auth->access_token,
			])]))
		));
		mapping page = Standards.JSON.decode_utf8(res->get());
		members += page->data;
		string next = page->meta->pagination->cursors->next;
		//TODO: What does next look like and how do we use it?
	} while (0); //TODO: while (next);
	mapping ret = (["cmd": "resyncpatreon", "members": ({ })]);
	foreach (members, mapping mem) {
		string patid = mem->relationships->user->data->id;
		string|zero twitchid = lookup[patid];
		werror("PATREON SYNC: User %O (Twitch %O) is paying %d/month\n", patid, twitchid, mem->attributes->currently_entitled_amount_cents);
		mapping user = twitchid && await(get_user_info(twitchid));
		ret->members += ({([
			"patreonid": patid,
			"price": mem->attributes->currently_entitled_amount_cents,
			"name": mem->attributes->full_name,
			"twitch": user,
		])});
	}
	return ret;
}

@"is_mod": @"demo_ok": __async__ mapping wscmd_fwlogin(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping cfg = await(G->G->DB->load_config(0, "fourthwall"));
	string tok = String.string2hex(random_string(8));
	G->G->oauth_csrf_states[tok] = (["platform": "fourthwall", "timestamp": time(), "channel": channel->userid]);
	object uri = Standards.URI("https://my-shop.fourthwall.com/admin/platform-apps/" + cfg->clientid + "/connect");
	uri->set_query_variables(([
		//"scope": "", //Can we configure these on a per-login basis?
		"redirect_uri": "https://" + G->G->instance_config->local_address + "/authenticate",
		"state": tok,
	]));
	return (["cmd": "oauthpopup", "uri": (string)uri]);
}

protected void create(string name) {::create(name);}
