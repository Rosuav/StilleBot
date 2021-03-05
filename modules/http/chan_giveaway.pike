inherit http_endpoint;
inherit websocket_handler;

Concurrent.Future set_redemption_status(mapping redem, string status) {
	//Reject the redemption, refunding the points
	return twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards/redemptions"
			+ "?broadcaster_id=" + (redem->broadcaster_id || redem->broadcaster_user_id)
			+ "&reward_id=" + redem->reward->id
			+ "&id=" + redem->id,
		(["Authorization": "Bearer " + persist_status->path("bcaster_token")[redem->broadcaster_login || redem->broadcaster_user_login]]),
		(["method": "PATCH", "json": (["status": status])]),
	);
}
void update_ticket_count(mapping cfg, mapping redem, int|void removal) {
	if (!cfg->giveaway) return;
	mapping values = cfg->giveaway->rewards || ([]);
	string chan = redem->broadcaster_login || redem->broadcaster_user_login;
	mapping people = G->G->giveaway_tickets[chan];
	if (!people) people = G->G->giveaway_tickets[chan] = ([]);
	if (!people[redem->user_id]) people[redem->user_id] = ([
		"name": redem->user_name,
		"position": sizeof(people) + 1, //First person to buy a ticket gets position 1
		"redemptions": ([]), //Map redemption IDs to their info.
		"tickets": 0, //== sum(values[redemptions->reward->id[*]])
	]);
	mapping person = people[redem->user_id];
	if (removal == !person->redemptions[redem->id]) ; //Already (not) there, do nothing.
	else if (removal) {
		m_delete(person->redemptions, redem->id);
		person->tickets -= values[redem->reward->id];
	}
	else {
		int now = person->tickets + values[redem->reward->id];
		if (cfg->giveaway->max_tickets && now > cfg->giveaway->max_tickets) {
			set_redemption_status(redem, "CANCELED")->then(lambda(mixed resp) {write("Cancelled: %O\n", resp);});
		}
		else {person->tickets = now; person->redemptions[redem->id] = redem;}
	}
}

array tickets_in_order(string chan) {
	array tickets = ({ });
	foreach (G->G->giveaway_tickets[chan]; ; mapping person)
		if (person->tickets) tickets += ({person});
	sort(tickets->position, tickets);
	return tickets;
}

//Send an update based on cached data rather than forcing a full recalc every time
void notify_websockets(string chan) {
	if (!websocket_groups[chan]) return;
	mapping status = persist_status->path("giveaways")[chan] || ([]);
	send_updates_all(chan, ([
		"tickets": tickets_in_order(chan),
		"is_open": status->is_open, "end_time": status->end_time,
		"last_winner": status->last_winner,
	]));
}

void points_redeemed(string chan, mapping data, int|void removal)
{
	//write("POINTS %s ON %O: %O\n", removal ? "REFUNDED" : "REDEEMED", chan, data);
	string token = persist_status->path("bcaster_token")[chan];
	mapping cfg = persist_config->path("channels", chan);
	update_ticket_count(cfg, data, removal);

	if (mapping dyn = !removal && cfg->dynamic_rewards && cfg->dynamic_rewards[data->reward->id]) {
		//Up the price every time it's redeemed
		//For this to be viable, the reward needs a global cooldown of
		//at least a few seconds, preferably a few minutes.
		object chan = G->G->irc->channels["#" + chan];
		int newcost = G->G->evaluate_expr(chan->expand_variables(dyn->formula, (["PREV": (string)data->reward->cost])));
		twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id="
				+ data->broadcaster_user_id + "&id=" + data->reward->id,
			(["Authorization": "Bearer " + token]),
			(["method": "PATCH", "json": (["cost": newcost])]),
		);
	}
	notify_websockets(chan);
}
void remove_tickets(string chan, mapping data) {points_redeemed(chan, data, 1);}

void make_hooks(string chan, int broadcaster_id) {
	if (G->G->webhook_active["redemption=" + chan] < 300)
	{
		write("Creating eventsub hook for redemptions %O\n", chan);
		create_eventsubhook(
			"redemption=" + chan,
			"channel.channel_points_custom_reward_redemption.add", "1",
			(["broadcaster_user_id": (string)broadcaster_id]),
		);
	}
	if (G->G->webhook_active["redemptiongone=" + chan] < 300)
	{
		create_eventsubhook(
			"redemptiongone=" + chan,
			"channel.channel_points_custom_reward_redemption.update", "1",
			(["broadcaster_user_id": (string)broadcaster_id]),
		);
	}
}

//List all redemptions for a particular reward ID
Concurrent.Future list_redemptions(int broadcaster_id, string chan, string id) {
	return get_helix_paginated("https://api.twitch.tv/helix/channel_points/custom_rewards/redemptions",
		([
			"broadcaster_id": (string)broadcaster_id,
			"reward_id": id,
			"status": "UNFULFILLED",
			"first": "50",
		]),
		(["Authorization": "Bearer " + persist_status->path("bcaster_token")[chan]]),
	);
}

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	if (mapping resp = ensure_login(req, "channel:manage:redemptions")) return resp;
	mapping cfg = req->misc->channel->config;
	string chan = req->misc->channel->name[1..];
	//TODO: Allow mods to control some things (if the broadcaster's set it up),
	//and allow all users to see status. The OAuth token is retained for good reason.
	if (chan != req->misc->session->user->login)
		return render_template("login.md", req->misc->chaninfo); //TODO: Change the text to say "not the broadcaster" rather than "not a mod"
	int broadcaster_id = req->misc->session->user->id;
	persist_status->path("bcaster_token")[chan] = req->misc->session->token;
	Concurrent.Future call(string method, string query, mixed body) {
		return twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id=" + broadcaster_id + "&" + query,
			(["Authorization": "Bearer " + req->misc->session->token]),
			(["method": method, "json": body, "return_status": !body]),
		);
	}
	if (req->request_type == "PUT") {
		mixed body = Standards.JSON.decode(req->body_raw);
		if (!body || !mappingp(body)) return (["error": 400]);
		write("Got request: %O\n", body);
		if (int cost = (int)body->cost) {
			//Master reconfiguration
			array qty = (array(int))((body->multi || "") / " ") - ({0});
			if (!cfg->giveaway) cfg->giveaway = ([]);
			mapping status = persist_status->path("giveaways", chan);
			cfg->giveaway->max_tickets = (int)body->max;
			cfg->giveaway->desc_template = body->desc;
			cfg->giveaway->cost = cost;
			cfg->giveaway->pausemode = body->pausemode == "pause";
			cfg->giveaway->allow_multiwin = body->allow_multiwin == "yes";
			cfg->giveaway->duration = min(max((int)body->duration, 0), 3600);
			mapping existing = cfg->giveaway->rewards;
			if (!existing) existing = cfg->giveaway->rewards = ([]);
			array reqs = ({ });
			int numcreated = 0, numupdated = 0, numdeleted = 0;
			//Prune any that we no longer need
			foreach (existing; string id; int tickets) {
				if (!has_value(qty, tickets)) {
					m_delete(existing, id);
					++numdeleted;
					reqs += ({call("DELETE", "id=" + id, 0)});
				}
				else {
					++numupdated;
					reqs += ({call("PATCH", "id=" + id, ([
						"title": replace(body->desc || "Buy # tickets", "#", (string)tickets),
						"cost": cost * tickets,
						"is_enabled": status->is_open || cfg->giveaway->pausemode,
						"is_paused": !status->is_open && cfg->giveaway->pausemode,
					]))});
				}
				qty -= ({tickets});
			}
			//Create any that we don't yet have
			Concurrent.Future make_reward(int tickets) {
				return call("POST", "", ([
					"title": replace(body->desc || "Buy # tickets", "#", (string)tickets),
					"cost": cost * tickets,
					"is_enabled": status->is_open || cfg->giveaway->pausemode,
					"is_paused": !status->is_open && cfg->giveaway->pausemode,
				]))->then(lambda(mapping info) {
					existing[info->data[0]->id] = tickets;
					++numcreated;
				});
			}
			reqs += make_reward(qty[*]);
			make_hooks(chan, broadcaster_id);
			persist_config->save();
			return Concurrent.all(reqs)->then(lambda() {
				//TODO: Notify the front end what's been changed, not just counts
				return jsonify((["ok": 1, "created": numcreated, "updated": numupdated, "deleted": numdeleted]));
			});
		}
		if (body->new_dynamic) { //This kinda should be a POST request, but whatever.
			if (!cfg->dynamic_rewards) cfg->dynamic_rewards = ([]);
			mapping copyfrom = body->copy_from || ([]); //Whatever we get from the front end, pass to Twitch. Good idea? Not sure.
			//Titles must be unique (among all rewards). To simplify rapid creation of
			//multiple rewards, add a numeric disambiguator on conflict.
			string deftitle = copyfrom->title || "Example Dynamic Reward";
			mapping rwd = (["basecost": copyfrom->cost || 1000, "formula": "PREV * 2"]);
			array have = filter(values(cfg->dynamic_rewards)->title, has_prefix, deftitle);
			rwd->title = deftitle + " #" + (sizeof(have) + 1);
			copyfrom |= (["title": rwd->title, "cost": rwd->basecost]);
			return twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id=" + broadcaster_id,
				(["Authorization": "Bearer " + req->misc->session->token]),
				(["method": "POST", "json": copyfrom]),
			)->then(lambda(mapping info) {
				string id = info->data[0]->id;
				//write("Created new dynamic: %O\n", info->data[0]);
				cfg->dynamic_rewards[id] = rwd;
				make_hooks(chan, broadcaster_id);
				persist_config->save();
				return jsonify((["ok": 1, "reward": rwd | (["id": id])]));
			});
		}
		if (string id = body->dynamic_id) {
			if (!cfg->dynamic_rewards || !cfg->dynamic_rewards[id]) return (["error": 400]);
			mapping rwd = cfg->dynamic_rewards[id];
			if (body->title) rwd->title = body->title;
			if (body->basecost) rwd->basecost = (int)body->basecost || rwd->basecost;
			if (body->formula) rwd->formula = body->formula;
			if (body->title || body->curcost) {
				//Currently fire-and-forget - there's no feedback if you get something wrong.
				twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id=" + broadcaster_id + "&id=" + id,
					(["Authorization": "Bearer " + req->misc->session->token]),
					(["method": "PATCH", "json": (["title": rwd->title, "cost": (int)body->curcost])]),
				);
			}
			make_hooks(chan, broadcaster_id);
			persist_config->save();
			return jsonify((["ok": 1]));
		}
		return jsonify((["ok": 1]));
	}
	mapping config = ([]);
	mapping g = cfg->giveaway || ([]);
	config->cost = g->cost || 1;
	config->max = g->max_tickets || 1;
	config->desc = g->desc_template || "";
	config->pausemode = g->pausemode ? "pause" : "disable";
	config->allow_multiwin = g->allow_multiwin ? "yes" : "no";
	config->duration = g->duration;
	if (mapping existing = g->rewards)
		config->multi = ((array(string))sort(values(existing))) * " ";
	else config->multi = "";
	return render_template("chan_giveaway.md", (["vars": (["ws_type": "chan_giveaway", "ws_group": chan, "config": config])]));
}

mapping|Concurrent.Future get_state(string|int chan)
{
	mapping cfg = persist_config->path("channels", chan);
	array rewards;
	int broadcaster_id;
	return get_user_id(chan)->then(lambda(int id) {
		make_hooks(chan, broadcaster_id = id);
		return twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?only_manageable_rewards=true&broadcaster_id=" + broadcaster_id,
			(["Authorization": "Bearer " + persist_status->path("bcaster_token")[chan]]));
	})->then(lambda(mapping info) {
		rewards = info->data;
		return Concurrent.all(list_redemptions(broadcaster_id, chan, rewards->id[*]));
	})->then(lambda(array(array) redemptions) {
		//Every time a new websocket is established, fully recalculate. Guarantee fresh data.
		G->G->giveaway_tickets[chan] = ([]);
		mapping status = persist_status->path("giveaways")[chan] || ([]);
		foreach (redemptions * ({ }), mapping redem) update_ticket_count(cfg, redem);
		return ([
			"rewards": rewards, "tickets": tickets_in_order(chan),
			"is_open": status->is_open, "end_time": status->end_time,
			"last_winner": status->last_winner,
		]);
	});
}

void open_close(string chan, int broadcaster_id, string token, int want_open) {
	mapping cfg = persist_config->path("channels", chan);
	if (!cfg->giveaway) return; //No rewards, nothing to open/close
	mapping status = persist_status->path("giveaways", chan);
	status->is_open = want_open;
	if (mixed id = m_delete(status, "autoclose")) remove_call_out(id);
	if (int d = want_open && cfg->giveaway->duration) {
		status->end_time = time() + d;
		status->autoclose = call_out(open_close, d, chan, broadcaster_id, token, 0);
	}
	else m_delete(status, "end_time");
	//Note: Updates reward status in fire and forget mode.
	foreach (cfg->giveaway->rewards || ([]); string id;)
		twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id=" + broadcaster_id + "&id=" + id,
			(["Authorization": "Bearer " + token]),
			(["method": "PATCH", "json": ([
				"is_enabled": want_open || cfg->giveaway->pausemode,
				"is_paused": !want_open && cfg->giveaway->pausemode,
			])]),
		);
	persist_status->save();
	notify_websockets(chan);
}

void websocket_cmd_master(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	string chan = conn->group;
	mapping cfg = persist_config->path("channels", chan);
	if (!cfg->giveaway) return; //No rewards, nothing to activate or anything
	int broadcaster_id = conn->session->user->id;
	switch (msg->action) {
		case "open":
		case "close": {
			int want_open = msg->action == "open";
			mapping status = persist_status->path("giveaways", chan);
			if (want_open == status->is_open) {
				send_update(conn, (["message": "Giveaway is already " + (want_open ? "open" : "closed")]));
				return;
			}
			open_close(chan, broadcaster_id, conn->session->token, want_open);
			break;
		}
		case "pick": {
			//NOTE: This is subject to race conditions if the giveaway is open
			//at the time of drawing. Close the giveaway first.
			array people = (array)(G->G->giveaway_tickets[chan] || ([]));
			int tot = 0;
			array partials = ({ });
			foreach (people, [mixed id, mapping person]) partials += ({tot += person->tickets});
			if (!tot) {
				send_update(conn, (["message": "No tickets bought!"]));
				return;
			}
			int ticket = random(tot);
			//I could binary search but I doubt there'll be enough entrants to make a difference.
			array winner;
			foreach (partials; int i; int last) if (ticket < last) {winner = people[i]; break;}
			mapping status = persist_status->path("giveaways", chan);
			status->last_winner = ({winner[0], winner[1]->name, winner[1]->tickets, tot}); //ID, name, ticket count, out of total
			if (!cfg->giveaway->allow_multiwin)
			{
				foreach (values(winner[1]->redemptions), mapping redem)
					set_redemption_status(redem, "FULFILLED");
				//This will eventually be done by the webhook, but the
				//front end updates faster if we force it immediately.
				winner[1]->redemptions = ([]);
				winner[1]->tickets = 0;
			}
			notify_websockets(chan);
			persist_status->save();
			break;
		}
		case "cancel":
		case "end": {
			mapping existing = cfg->giveaway->rewards;
			if (!existing) break; //No rewards, nothing to cancel
			mapping status = persist_status->path("giveaways", chan);
			m_delete(status, "last_winner");
			notify_websockets(chan);
			persist_status->save();
			Concurrent.all(list_redemptions(broadcaster_id, chan, indices(existing)[*]))
				->then(lambda(array(array) redemptions) {
					foreach (redemptions * ({ }), mapping redem)
						set_redemption_status(redem, msg->action == "cancel" ? "CANCELED" : "FULFILLED");
				});
		}
	}
}

void channel_on_off(string channel, int online)
{
	mapping cfg = persist_config["channels"][channel];
	mapping dyn = cfg->dynamic_rewards || ([]);
	mapping rewards = (cfg->giveaway && cfg->giveaway->rewards) || ([]);
	if (!sizeof(dyn) && !sizeof(rewards)) return; //Nothing to do
	get_user_id(channel)->then(lambda(int broadcaster_id) {
		if (online) make_hooks(channel, broadcaster_id);
		string token = persist_status->path("bcaster_token")[channel];
		if (token) foreach (dyn; string reward_id; mapping info)
			twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id="
					+ broadcaster_id + "&id=" + reward_id,
				(["Authorization": "Bearer " + token]),
				(["method": "PATCH", "json": (["cost": info->basecost, "is_paused": online ? Val.false : Val.true])]),
			);
	});
}
int channel_online(string channel) {channel_on_off(channel, 1);}
int channel_offline(string channel) {channel_on_off(channel, 0);}

protected void create(string name)
{
	::create(name);
	if (!G->G->giveaway_tickets) G->G->giveaway_tickets = ([]);
	G->G->webhook_endpoints->redemption = points_redeemed;
	G->G->webhook_endpoints->redemptiongone = remove_tickets;
	register_hook("channel-online", channel_online);
	register_hook("channel-offline", channel_offline);
}
