__async__ void pingmakeship() {
	G->G->makeship_call_out = call_out(pingmakeship, 30);
	object res = await(Protocols.HTTP.Promise.get_url("https://storefront.makeship.com/orders/petitions/8310765486236/pledges/count"));
	string n = String.trim(res->get());
	object channel = G->G->irc->channels["#devicat"];
	if (n != channel->expand_variables("$pledges$")) {
		channel->set_variable("pledges", n);
		channel->send((["user": "devicat", "uid": channel->userid]), ({
			"devicatAww Thank you! We now have $pledges$ pledges!! devicatBless",
			([
				"builtin": "chan_streamsetup",
				"builtin_param": ({
					"title",
					'\U0001f534 $pledges$ / 200 Plushie Petition \u2022 ENDS IN 6 DAYS \u2605\u5f61 makeship.com/petitions/candicat-cozy \u2022 !plushie !hoodie'
				}),
				"message": "",
			]),
		}));
	}
}

protected void create(string name) {
	remove_call_out(G->G->makeship_call_out);
	//G->G->makeship_call_out = call_out(pingmakeship, 60);
}
