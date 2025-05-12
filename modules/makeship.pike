__async__ void pingmakeship() {
	G->G->makeship_call_out = call_out(pingmakeship, 30);
	//For a petition:
	//object res = await(Protocols.HTTP.Promise.get_url("https://storefront.makeship.com/orders/petitions/8310765486236/pledges/count"));
	//string n = String.trim(res->get());
	//For a campaign:
	object res = await(Protocols.HTTP.Promise.get_url("https://storefront.makeship.com/products/8310765486236/sales-quantity"));
	string n = (string)Standards.JSON.decode(res->get())->quantity;
	//Everything else should be the same (yeah, it's called "pledges" but whatever).
	//The wording of the message might want to change.
	object channel = G->G->irc->channels["#devicat"];
	if (n != channel->expand_variables("$pledges$")) {
		channel->set_variable("pledges", n);
		array digits = n / "";
		channel->set_variable("pileA:hundred", digits[-3]);
		channel->set_variable("pileA:ten", digits[-2]);
		channel->set_variable("pileA:one", digits[-1]);
		mapping prev = await(twitch_api_request("https://api.twitch.tv/helix/channels?broadcaster_id=" + channel->userid,
			(["Authorization": channel->userid])));
		channel->send((["user": "devicat", "uid": channel->userid]), ({
			"devicatAww Thank you! Now devicatPlush $pledges$ plushies devicatPlush will find their forever homes!! devicatBless",
			([
				"builtin": "chan_streamsetup",
				"builtin_param": ({
					"title",
					Regexp.replace("([0-9]+) Plushies Adopted", prev->data[0]->title, n + " Plushies Adopted"),
				}),
				"message": "",
			]),
		}));
	}
}

protected void create(string name) {
	remove_call_out(G->G->makeship_call_out);
	if (is_active_bot()) G->G->makeship_call_out = call_out(pingmakeship, 60);
}
