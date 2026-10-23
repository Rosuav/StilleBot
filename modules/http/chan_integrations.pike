#charset utf-8
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

//NOTE: The name "makeship" is often used in contexts where both Makeship and Kickstarter are valid.
//It would be nice to rename these things to "campaigns" or something, but it's not worth the breakage.

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

> ### For additional Ko-fi pages, add their tokens here
>
> Label | Token |
> ------|-------|-
> loading... |
>
> Use the `{origin}` placeholder in special triggers, or the `origin` alert field, to
> differentiate. Goal bars will by default respond to all Ko-fi accounts identically;
> to react to one and not another, advance it using the special trigger instead.
>
{:tag=details id=kofitokens}

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

## Makeship and Kickstarter

Track [Makeship](https://www.makeship.com/) plushies and [Kickstarter](https://www.kickstarter.com/) campaigns here!

* loading...
{:#makeship_campaigns}

[Start tracking!](:.opendlg data-dlg=newmakeshipdlg)

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
#kofitokens {border: 1px solid rebeccapurple; margin: 8px; padding: 5px;}
#campaigndetails.error {background: #fee; border: 1px solid #800;}
.date time {text-decoration: underline dotted;}
.date.upcoming time {font-weight: bold;}
</style>

> ### Makeship/Kickstarter Campaign
>
> To start tracking a Makeship or Kickstarter petition/campaign, paste its URL here:
>
> <label>URL: <input type=url id=campaignurl size=60></label><br>
> eg: `https://www.makeship.com/products/candicat-cozy` for a Makeship campaign<br>
> or `https://www.makeship.com/petitions/kiko-bat-cat` for a Makeship petition<br>
> or `https://www.kickstarter.com/projects/buriedcandy/the-calling-1` for a Kickstarter campaign<br>
> [Look up](:#lookup)
> <div id=campaigndetails></div>
>
> [Close](:.dialog_close)
{: tag=dialog #newmakeshipdlg}
";

constant platform_config_fields = ([
	"kofi": (<"token">),
	"fourthwall": (<"token">), //Shouldn't need this, ideally - it should all be done with OAuth.
]);

//NOTE: Currently this is only used by chan_vipleaders, which is alphabetically after
//chan_kofi. If others start using it, it may be necessary to move this to some higher
//level module, which would break encapsulation.
@create_hook: constant kofi_support = ({"object channel", "string type", "mapping params", "mapping raw"});

constant kofi_dono = special_trigger("!kofi_dono", "Donation received on Ko-fi.", "The broadcaster", "amount, msg, from_name, origin", "Ko-fi");
constant kofi_member = special_trigger("!kofi_member", "New monthly membership on Ko-fi.", "The broadcaster", "amount, msg, from_name, tiername, origin", "Ko-fi");
constant kofi_shop = special_trigger("!kofi_shop", "Shop sale on Ko-fi.", "The broadcaster", "amount, msg, from_name, shop_item_ids, shop_item_count, origin", "Ko-fi");
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
		string|zero origin = 0;
		if (stringp(data->verification_token)) {
			//The primary Ko-fi token has a blank label (implicitly). For many users, this is
			//the ONLY token.
			if (data->verification_token == cfg->?verification_token) origin = "";
			else foreach (cfg->additional_tokens || ({ }), mapping tok)
				if (data->verification_token == tok->token) origin = tok->label;
			//Note that, if we don't have any tokens on file, it's guaranteed to be a bad
			//token. This means that any mis-sent POST requests that happen to have a
			//data mapping somehow will just come back "bad token".
		}
		if (!origin) return (["error": 404, "type": "text/plain", "data": "Bad verification token"]);
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
			"{origin}": origin,
		]);
		mapping alertparams = ([
			"amount": amount,
			"cents": cents,
			"msg": data->message,
			"username": data->from_name,
			"origin": origin,
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
		Stdio.append_file("patreon.log", sprintf("GOT PATREON NOTIFICATION %O %O\n", req->misc->channel->name, body));
		return "Thanks!";
	}
	if (await(modprobe(req))) {
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
		//Special case: Ko-fi tokens can be saved to an array of additional tokens. This excludes
		//all other configuration in that message.
		if (msg->platform == "kofi" && msg->prevlabel) {
			if (msg->prevlabel == "") { //Add new token
				if (!stringp(msg->label) || msg->label == "" || !stringp(msg->token) || msg->token == "") return; //Deleting doesn't make sense while adding
				cfg->additional_tokens += ({(["label": msg->label, "token": msg->token])});
				return;
			}
			int idx; mapping tok = (["label": ""]);
			foreach (cfg->additional_tokens || ({ }); idx; tok) if (tok->label == msg->prevlabel) break;
			if (tok->label != msg->prevlabel) return; //Not found
			if (!stringp(msg->token) || msg->token == "") //Delete existing token
				cfg->additional_tokens = cfg->additional_tokens[..idx-1] + cfg->additional_tokens[idx+1..];
			else if (has_prefix(msg->token, "...")) //Probably an accidental click
				return;
			else //Update the token while leaving the label unchanged
				tok->token = msg->token;
			return;
		}
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
	//This is a lot of configs. Would it be worth making a multi-load API that can do
	//this in a single database query?
	mapping kofi = await(G->G->DB->load_config(channel->userid, "kofi"));
	mapping fw = await(G->G->DB->load_config(channel->userid, "fourthwall"));
	mapping pat = await(G->G->DB->load_config(channel->userid, "patreon"));
	mapping ms = await(G->G->DB->load_config(channel->userid, "makeship"));
	return ([
		"kofitoken": stringp(kofi->verification_token) && "..." + kofi->verification_token[<3..],
		"kofitokens": map(kofi->additional_tokens || ({ })) {return (["label": __ARGS__[0]->label, "token": "..." + __ARGS__[0]->token[<3..]]);},
		"fwtoken": stringp(fw->verification_token) && "..." + fw->verification_token[<3..], //Deprecated
		"fwshopname": fw->refresh_token && fw->shopname, //This one's the flag - if absent, the front end assumes no FW config
		"fwurl": fw->url, "fwusername": fw->username,
		"paturl": pat->campaign_url, //May be null
		"makeship_campaigns": ms->campaigns || ({ }), //Can also contain Kickstarter campaigns
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

//I am crying here. This is stupid.
#if 1
mapping host_to_ip = ([]);
class cloudflare_fetcher(string url) {
	inherit Concurrent.Promise;
	string server;
	object sock;
	string writeme, result = "";

	protected void create() {
		Standards.URI uri = Standards.URI(url);
		writeme = replace(sprintf(#"GET %s HTTP/1.0
		Host: %s
		User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0
		Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8
		Accept-Language: en-US,en;q=0.5
		Dont-Accept-Encoding: gzip, deflate, br, zstd
		Sec-GPC: 1
		Connection: close
		Upgrade-Insecure-Requests: 1
		Sec-Fetch-Dest: document
		Sec-Fetch-Mode: navigate
		Sec-Fetch-Site: none
		Sec-Fetch-User: ?1
		Priority: u=0, i

		", uri->path, server = uri->host), "\n", "\r\n") - "\t";
		if (!host_to_ip[server]) {
			array|zero ip = gethostbyname(server);
			if (!ip || !sizeof(ip[1])) {failure(backtrace()); return;}
			host_to_ip[server] = ip[1][0];
		}
		sock = Stdio.File();
		sock->open_socket(-1, 0, host_to_ip[server]);
		sock->set_nonblocking(sockread, connected, sockclosed);
		sock->connect(host_to_ip[server], 443);
	}

	void sockread(mixed _, string data) {result += data;}
	void sockclosed() {
		//TODO: Properly parse HTTP
		sscanf(result, "%s\r\n\r\n%s", string headers, string body);
		success(body);
	}

	void sockwrite() {
		if (writeme == "") return;
		sock->write(writeme);
		writeme = "";
	}

	void connected() {
		sock = SSL.File(sock, SSL.Context());
		sock->connect(server);
		sock->set_nonblocking(sockread, sockwrite, sockclosed);
	}
}

Concurrent.Future cloudflare_fetch(string url) {return cloudflare_fetcher(url)->future();}
#else
object provide_user_agent = Protocols.HTTP.Promise.Arguments((["headers": ([
	"Accept": "text/html",
	"Accept-Language": "en-US,en;q=0.9",
	"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 MustardMine/2026.10",
])]));

__async__ string cloudflare_fetch(string url) {
	object res = await(Protocols.HTTP.Promise.get_url(url, provide_user_agent));
	string data = res->get();
	//this doesn't work
	if (sscanf(data, "%*s__cf_chl_tk=%[^\"]", string chltk) && chltk) {
		werror("CLOUDFLARE TOKEN %O %O\n", res->status, chltk);
		res = await(Protocols.HTTP.Promise.get_url(url + "?__cf_chl_tk=" + chltk, provide_user_agent));
		data = res->get();
		werror("NEW STATUS %O    \n", res->status);
	}
	return data;
}
#endif

//If the returned mapping has an "error" key, something went wrong, otherwise it gives a basic summary.
__async__ mapping makeship_lookup(string url) {
	string data = await(cloudflare_fetch(url));
	sscanf(data, "%*s<script id=\"__NEXT_DATA__\" type=\"application/json\">%s</script>", string json);
	if (!json) return (["error": "Unable to read Makeship campaign - check the URL or contact Rosuav"]);
	mapping info = Standards.JSON.decode(json);
	mapping props = info->props->?pageProps;
	mapping product = props->?product;
	if (!product) return (["error": "Unable to read Makeship campaign - check the URL or contact Rosuav"]);
	mapping meta = ([]);
	foreach (product->metafields, mapping|Val.Null f) if (mappingp(f)) {
		if (!meta[f->namespace]) meta[f->namespace] = ([]);
		meta[f->namespace][f->key] = f->value;
	}
	int productid;
	if (product->id) sscanf(product->id, "gid://shopify/Product/%d", productid);
	return ([
		"url": url,
		"sales": props->pledgeCount || props->productSalesQuantity->?quantity, //Will be updated by the poll
		"platform": "makeship", "pfmid": "makeship-" + productid,
		"productid": productid,
		"metadata": meta, "creator": meta->name->creator,
		"dates": meta->date || ([]),
		"title": product->title,
		"tags": product->tags,
	]);
}

__async__ mapping kickstarter_lookup(string url) {
	string data = await(cloudflare_fetch(url));
	sscanf(data, "%*shttps://api.kickstarter.com/v1/projects/%s&quot;", string apiurl);
	if (!apiurl) return (["error": "Unable to read Kickstarter campaign - check the URL or contact Rosuav"]);
	apiurl = "https://api.kickstarter.com/v1/projects/" + apiurl;
	mapping info = Standards.JSON.decode(await(Protocols.HTTP.Promise.get_url(apiurl))->get());
	if (!info) return (["error": "Unable to read Kickstarter details - check the URL or contact Rosuav"]);
	return ([
		"url": url, "apiurl": apiurl,
		"sales": info->backers_count, "amount": info->pledged, "goal": info->goal,
		"platform": "kickstarter", "pfmid": "kickstarter-" + info->id,
		"creator": info->creator->name,
		"productid": info->id,
		"state": info->state,
		"title": info->name,
		//Multiply Unix time by 1000 for the convenience of the front end
		"dates": (["launched_at": info->launched_at * 1000, "deadline": info->deadline * 1000]),
	]);
}

Concurrent.Future campaign_lookup(string url) {
	if (has_prefix(url, "https://www.makeship.com/")) return makeship_lookup(url);
	if (has_prefix(url, "https://www.kickstarter.com/")) return kickstarter_lookup(url);
	return Concurrent.resolve((["error": "Unrecognized platform: " + url]));
}

@"is_mod": @"demo_ok": __async__ mapping wscmd_makeship_lookup(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!stringp(msg->url)) return (["error": "Bad message"]);
	string url = msg->url;
	if (!has_value(url, "://")) url = "https://" + url;
	Standards.URI uri = Standards.URI(msg->url, "https://www.makeship.com/"); //Use a base URL in case it's somehow still relative. Most likely that would result in a broken URL though.
	if (uri->scheme == "http") {uri->scheme = "https"; uri->port = 443;}
	uri->query = 0; //Any query parameters are just going to be statistical and tracking anyway
	if (uri->host == "makeship.com") uri->host = "www.makeship.com"; //They redirect us anyway, so shortcut the process
	if (uri->host == "kickstarter.com") uri->host = "www.kickstarter.com"; //It's easier to be consistent internally, too
	return await(campaign_lookup((string)uri)) | (["cmd": "makeship_lookup"]);
}

mapping campaign_provides(mapping cp, string|void newsales, string|void newamount) {
	return ([
		"{platform}": cp->platform, //Normally you'll know what you're attaching an action to, but this will allow you to chain to a generic handler
		"{productid}": (string)cp->productid,
		"{sales}": newsales || (string)cp->sales,
		"{prevsales}": (string)cp->sales,
		"{saleamount}": newamount || (string)cp->amount,
		"{prevsaleamount}": (string)cp->amount,
		"{title}": cp->title,
	]);
}

__async__ mapping cmdedit_execute_provides(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping cfg = await(G->G->DB->load_config(channel->userid, "makeship"));
	//The command name should match the platform-and-id.
	foreach (cfg->campaigns || ({ }), mapping cp)
		if (cp->pfmid == msg->cmdname) return campaign_provides(cp);
	return ([]); //Not found, use stub/default data
}

//Largely similar to check_makeship() but not similar enough to fold the two together.
//Handles both Makeship and Kickstarter.
__async__ void makeship_poll() {
	remove_call_out(G->G->makeship_poll_call_out);
	if (!is_active_bot()) return;
	mapping cfg = await(G->G->DB->load_config(1, "makeship"));
	if (!cfg->channels) return;
	array(string) chanids = ({ });
	foreach (cfg->channels; string chanid; mapping info)
		if (info->phase_status == "active") chanids += ({chanid});
	//In theory we could now query configs for all of these channel IDs; currently fetching one at a time.
	int active = 0;
	foreach (chanids, string chanid) {
		mapping cfg = await(G->G->DB->load_config(chanid, "makeship"));
		foreach (cfg->campaigns, mapping cp) {
			if (cp->phase_status != "active") continue;
			active = 1;
			int sales = cp->sales, amount = cp->amount;
			if (cp->platform == "kickstarter") {
				mapping stats = Standards.JSON.decode(await(cloudflare_fetch(cp->url + "/stats.json")));
				sales = stats->project->backers_count;
				//Comes through as a float, but fractional dollars aren't usually relevant. TODO: Check other currencies.
				amount = (int)stats->project->pledged;
				//If the project seems no longer to be live, ping it. We MIGHT know when the deadline is,
				//but it's also possible we won't, so check here too.
				if (stats->project->state != "live") call_out(makeship_track, 3, chanid, cp->url);
			}
			else if (cp->phase == "petition") { //Else platform is Makeship, which has two different ping URLs depending on phase
				string raw = await(cloudflare_fetch("https://storefront.makeship.com/orders/petitions/" + cp->productid + "/pledges/count"));
				sales = (int)String.trim(raw);
			} else { //phase is "campaign"
				string raw = await(cloudflare_fetch("https://storefront.makeship.com/products/" + cp->productid + "/sales-quantity"));
				sales = (int)Standards.JSON.decode(raw)->quantity;
			}
			if (sales != cp->sales || amount != cp->amount) {
				werror("SALES CHANGED %O %O %O\n", cp->pfmid, cp->sales, sales);
				if (cp->action) G->G->irc->id[(int)chanid]->send(0, cp->action, campaign_provides(cp, (string)sales, (string)amount));
				//In theory we might be overwriting some other change. Would be better to mutate_config
				//and do a deep mutation inside the transaction, but I can't be bothered.
				cp->sales = sales;
				if (amount) cp->amount = amount;
				await(G->G->DB->save_config(chanid, "makeship", cfg));
				send_updates_all("#" + chanid);
			}
		}
	}
	if (active) G->G->makeship_poll_call_out = call_out(makeship_poll, 60);
}

__async__ void check_makeship() {
	//Check all active Makeship campaigns to see if they've changed phase
	//Scheduled for the next time one is expected to change phase, and also
	//run any time this bot becomes active.
	remove_call_out(G->G->check_makeship_call_out);
	mapping cfg = await(G->G->DB->load_config(1, "makeship"));
	if (!cfg->channels) return;
	int now = time(), changed = 0, active = 0;
	foreach (cfg->channels; int chanid; mapping info) {
		if (info->next_phase_time <= now) foreach (await(G->G->DB->load_config(chanid, "makeship"))->campaigns, mapping cp) {
			//Any campaign that was scheduled to have changed phase by now, do a full re-check and re-query.
			//Note that this will potentially update the master list multiple times; this will only happen
			//if multiple campaigns have changed state, which shouldn't happen unless we've lagged out badly
			//(or the platform batches their campaign starts/ends). A bit of extra database load is no big deal.
			await(makeship_track(chanid, cp->url));
			changed = 1;
		}
		if (info->phase_status == "active") active = 1;
	}
	if (!changed) {
		//If any campaign has changed, the call_out will have been retriggered inside makeship_track().
		//Otherwise, retrigger it now, at the timestamp of the earliest next_phase_time.
		int next_phase_time = min(@values(cfg->channels)->next_phase_time);
		if (next_phase_time < 0xf0000000000000) G->G->check_makeship_call_out = call_out(check_makeship, next_phase_time - time());
		if (active) makeship_poll();
	}
}

@hook_database_settings: void check_makeship_when_active(mapping settings) {
	//On startup, code reload, and any time we become active, check to see if we need to start pinging.
	//This has minor overhead of querying one config even if there are no campaigns of interest.
	if (!is_active_bot()) remove_call_out(G->G->check_makeship_call_out);
	else check_makeship();
}

__async__ void makeship_track(int chanid, string url) {
	mapping data = await(campaign_lookup(url));
	if (data->error) return; //Shouldn't happen - should have done a lookup before getting to this point
	if (data->platform == "makeship") {
		//Okay. Question: What phase are we in? Pre-petition, petition, interstage, campaign, post-campaign?
		//(Note that "post-campaign" includes everything from manufacturing to delivery to arrival and forever after,
		//even though these are very important distinctions to the humans.)
		mapping dates = data->metadata->date;
		int now = time();
		foreach (({"petitionLaunchDate", "petitionEndDate", "launch", "enddate"}), string date) {
			int tm = dates[date] && Calendar.ISO.parse("%Y-%M-%DT%h:%m:%s%z", dates[date])->unix_time();
			if (tm > now) {
				data->phase = (<"petitionLaunchDate", "petitionEndDate">)[date] ? "petition" : "campaign";
				data->phase_status = (<"petitionEndDate", "enddate">)[date] ? "active" : "upcoming";
				data->next_phase_time = tm;
				break;
			}
		}
	} else {
		//For Kickstarter, all we can see is the current state, and there's no "upcoming" option.
		//We also might not get told when the campaign will end, in which case check every hour.
		if (data->state == "live") {
			data->phase_status = "active";
			data->next_phase_time = data->dates->?deadline / 1000;
			if (data->next_phase_time < time()) data->next_phase_time = time() + 3600;
		}
	}
	if (!data->phase_status) {data->phase_status = "done"; data->next_phase_time = 0xf0000000000000;}
	await(update_makeship_campaign(chanid, data->pfmid, data));
}

__async__ void update_makeship_campaign(int chanid, string pfmid, mapping|zero data) {
	string phase_status = "done"; int next_phase_time;
	await(G->G->DB->mutate_config(chanid, "makeship") {mapping cfg = __ARGS__[0];
		if (!cfg->campaigns) cfg->campaigns = ({ });
		int idx = search(cfg->campaigns->pfmid, pfmid);
		if (!data) {
			//Delete (untrack) this campaign
			if (idx > -1) cfg->campaigns[idx] = 0;
			cfg->campaigns -= ({0});
		}
		else if (idx == -1) {
			//New campaign, add to end of list (no reordering option, sorry)
			//If you were trying to do a partial update but the pfmid wasn't found,
			//let the update fail. The bare minimum for a valid product is probably more
			//than just the URL but this is a start.
			if (data->url) cfg->campaigns += ({data});
		}
		else cfg->campaigns[idx] |= data; //Update campaign with new info
		array statuses = cfg->campaigns->phase_status;
		if (has_value(statuses, "active")) phase_status = "active";
		else if (has_value(statuses, "upcoming")) phase_status = "upcoming";
		else phase_status = "done";
		next_phase_time = min(@cfg->campaigns->next_phase_time);
	});
	await(G->G->DB->mutate_config(1, "makeship") {mapping cfg = __ARGS__[0];
		if (!cfg->channels) cfg->channels = ([]);
		if (phase_status == "done") m_delete(cfg->channels, (string)chanid); //Once the last campaign finishes, the channel no longer needs to be tracked.
		else cfg->channels[(string)chanid] = ([
			"phase_status": phase_status,
			"next_phase_time": next_phase_time,
		]);
		next_phase_time = min(@values(cfg->channels)->next_phase_time);
	});
	send_updates_all("#" + chanid);
	if (phase_status == "active") makeship_poll();
	//Run a full check the next time something is expected to change phase
	remove_call_out(G->G->check_makeship_call_out);
	if (next_phase_time < 0xf0000000000000) G->G->check_makeship_call_out = call_out(check_makeship, next_phase_time - time());
}

@"is_mod": __async__ mapping wscmd_makeship_track(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!stringp(msg->url)) return (["error": "Bad message"]);
	makeship_track(channel->userid, msg->url);
}

@"is_mod": __async__ mapping wscmd_makeship_untrack(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!msg->pfmid) return (["error": "Bad message"]);
	update_makeship_campaign(channel->userid, msg->pfmid, 0);
}

@"is_mod": __async__ void wscmd_set_action(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!stringp(msg->pfmid)) return;
	array valid = G->G->cmdmgr->validate_command(channel, "", msg->pfmid, msg->response, ([
		"language": msg->language == "mustard" ? "mustard" : ""
	]));
	if (!valid) return;
	update_makeship_campaign(channel->userid, msg->pfmid, (["action": valid[2]]));
}

protected void create(string name) {::create(name); call_out(check_makeship_when_active, 2, ([]));}
