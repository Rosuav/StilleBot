inherit http_endpoint;
inherit websocket_handler;

void update_ticket_count(mapping cfg, mapping redem, int|void removal) {
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
			//Reject the redemption, refunding the points
			twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards/redemptions"
					+ "?broadcaster_id=" + (redem->broadcaster_id || redem->broadcaster_user_id)
					+ "&reward_id=" + redem->reward->id
					+ "&id=" + redem->id,
				(["Authorization": "Bearer " + persist_status->path("bcaster_token")[chan]]),
				(["method": "PATCH", "json": (["status": "CANCELED"])]),
			)->then(lambda(mixed resp) {write("Cancelled: %O\n", resp);});
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

void points_redeemed(string chan, mapping data, int|void removal)
{
	write("POINTS %s ON %O: %O\n", removal ? "REFUNDED" : "REDEEMED", chan, data);
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

	write("Pinging %d clients for hype train %s\n", sizeof(websocket_groups[chan]), chan);
	(websocket_groups[chan] - ({0}))->send_text(Standards.JSON.encode(([
		"cmd": "update", "tickets": tickets_in_order(chan),
	])));
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

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	if (mapping resp = ensure_login(req, "channel:manage:redemptions")) return resp;
	mapping cfg = req->misc->channel->config;
	string chan = req->misc->channel->name[1..];
	//TODO: Allow mods to control some things (if the broadcaster's set it up),
	//and allow all users to see status. The OAuth token is retained for good reason.
	if (chan != req->misc->session->user->login)
		return render_template("login.md", req->misc->chaninfo); //TODO: Change the text to say "not the broadcaster" rather than "not a mod"
	persist_status->path("bcaster_token")[chan] = req->misc->session->token;
	if (req->request_type == "PUT") {
		mixed body = Standards.JSON.decode(req->body_raw);
		if (!body || !mappingp(body)) return (["error": 400]);
		write("Got request: %O\n", body);
		if (int cost = (int)body->cost) {
			//Master reconfiguration
			array qty = (array(int))((body->multi || "") / " ") - ({0});
			if (!cfg->giveaway) cfg->giveaway = ([]);
			cfg->giveaway->max_tickets = (int)body->max;
			mapping existing = cfg->giveaway->rewards;
			if (!existing) existing = cfg->giveaway->rewards = ([]);
			array reqs = ({ });
			Concurrent.Future call(string method, string query, mixed body) {
				return twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id=" + req->misc->session->user->id + "&" + query,
					(["Authorization": "Bearer " + req->misc->session->token]),
					(["method": method, "json": body, "return_status": !body]),
				);
			}
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
					]))});
				}
				qty -= ({tickets});
			}
			//Create any that we don't yet have
			Concurrent.Future make_reward(int tickets) {
				return call("POST", "", ([
					"title": replace(body->desc || "Buy # tickets", "#", (string)tickets),
					"cost": cost * tickets,
				]))->then(lambda(mapping info) {
					existing[info->data[0]->id] = tickets;
					++numcreated;
				});
			}
			reqs += make_reward(qty[*]);
			make_hooks(chan, req->misc->session->user->id);
			persist_config->save();
			return Concurrent.all(reqs)->then(lambda() {
				//TODO: Notify the front end what's been changed, not just counts
				return jsonify((["ok": 1, "created": numcreated, "updated": numupdated, "deleted": numdeleted]));
			});
		}
		if (body->new_dynamic) { //This kinda should be a POST request, but whatever.
			if (!cfg->dynamic_rewards) cfg->dynamic_rewards = ([]);
			//Titles must be unique (among all rewards). To simplify rapid creation of
			//multiple rewards, add a numeric disambiguator on conflict.
			string deftitle = "Example Dynamic Reward";
			mapping rwd = (["title": deftitle, "basecost": 1000, "formula": "PREV * 2"]);
			array have = filter(values(cfg->dynamic_rewards)->title, has_prefix, deftitle);
			if (has_value(have, deftitle)) rwd->title += " #" + (sizeof(have) + 1);
			return twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id=" + req->misc->session->user->id,
				(["Authorization": "Bearer " + req->misc->session->token]),
				(["method": "POST", "json": (["title": rwd->title, "cost": rwd->basecost])]),
			)->then(lambda(mapping info) {
				string id = info->data[0]->id;
				//write("Created new dynamic: %O\n", info->data[0]);
				cfg->dynamic_rewards[id] = rwd;
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
				twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id=" + req->misc->session->user->id + "&id=" + id,
					(["Authorization": "Bearer " + req->misc->session->token]),
					(["method": "PATCH", "json": (["title": rwd->title, "cost": (int)body->curcost])]),
				);
			}
			return jsonify((["ok": 1]));
		}
		return jsonify((["ok": 1]));
	}
	//TODO: Retain the configs (eg title template) to prepopulate the form
	return render_template("chan_giveaway.md", (["vars": (["channelname": chan])]));
}

void websocket_msg(mapping(string:mixed) conn, mapping(string:mixed) msg)
{
	if (!msg) return;
	write("GIVEAWAY: Got a msg %s from client in group %s\n", msg->cmd, conn->group);
	if (msg->cmd == "init")
	{
		string chan = conn->group;
		mapping cfg = persist_config->path("channels", chan);
		array rewards;
		int broadcaster_id;
		get_user_id(chan)->then(lambda(int id) {
			make_hooks(chan, broadcaster_id = id);
			return twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?only_manageable_rewards=true&broadcaster_id=" + broadcaster_id,
				(["Authorization": "Bearer " + persist_status->path("bcaster_token")[chan]]));
		})->then(lambda(mapping info) {
			rewards = info->data;
			return Concurrent.all(lambda(string id) {return get_helix_paginated("https://api.twitch.tv/helix/channel_points/custom_rewards/redemptions",
				([
					"broadcaster_id": (string)broadcaster_id,
					"reward_id": id,
					"status": "UNFULFILLED",
					"first": "50",
				]),
				(["Authorization": "Bearer " + persist_status->path("bcaster_token")[chan]]),
			);}(rewards->id[*]));
		})->then(lambda(array(array) redemptions) {
			//Every time a new websocket is established, fully recalculate. Guarantee fresh data.
			G->G->giveaway_tickets[chan] = ([]);
			foreach (redemptions * ({ }), mapping redem) update_ticket_count(cfg, redem);
			if (conn->sock) conn->sock->send_text(Standards.JSON.encode(([
				"cmd": "update", "rewards": rewards, "tickets": tickets_in_order(chan),
			])));
		});
	}
}

void channel_on_off(string channel, int online)
{
	mapping cfg = persist_config["channels"][channel];
	mapping dyn = cfg->dynamic_rewards || ([]);
	mapping rewards = cfg->giveaway->rewards || ([]);
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
