inherit http_endpoint;

void points_redeemed(string chan, mapping data)
{
	write("POINTS REDEEMED ON %O: %O\n", chan, data);
	string token = persist_status->path("bcaster_token")[chan];
	//POC: Up the price every time it's redeemed
	//For this to be viable, the reward needs a global cooldown of
	//at least a few seconds, preferably a few minutes.
	twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id="
			+ data->broadcaster_user_id + "&id=" + data->reward->id,
		(["Authorization": "Bearer " + token]),
		(["method": "PATCH", "json": (["cost": data->reward->cost * 2])]),
	);
}

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	if (mapping resp = ensure_login(req, "channel:manage:redemptions")) return resp;
	mapping cfg = req->misc->channel->config;
	//TODO: Allow mods to control some things (if the broadcaster's set it up),
	//and allow all users to see status. This MAY require retaining the OAuth.
	if (req->misc->channel->name[1..] != req->misc->session->user->login)
		return render_template("login.md", req->misc->chaninfo); //TODO: Change the text to say "not the broadcaster" rather than "not a mod"
	persist_status->path("bcaster_token")[req->misc->session->user->login] = req->misc->session->token;
	if (req->request_type == "PUT") {
		mixed body = Standards.JSON.decode(req->body_raw);
		if (!body || !mappingp(body)) return (["error": 400]);
		write("Got request: %O\n", body);
		if (int cost = (int)body->cost) {
			//Master reconfiguration
			array qty = ({1}) + (array(int))((body->multi || "") / " ") - ({0});
			if (!cfg->giveaway) cfg->giveaway = ([]);
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
			return Concurrent.all(reqs)->then(lambda() {
				//TODO: Notify the front end what's been changed, not just counts
				return jsonify((["ok": 1, "created": numcreated, "updated": numupdated, "deleted": numdeleted]));
			});
		}
		return jsonify((["ok": 1]));
	}
	array rewards;
	if (G->G->webhook_active["redemption=" + req->misc->channel->name[1..]] < 300)
	{
		write("Creating eventsub hook for redemptions %O\n", req->misc->channel->name[1..]);
		create_eventsubhook(
			"redemption=" + req->misc->channel->name[1..],
			"channel.channel_points_custom_reward_redemption.add", "1",
			(["broadcaster_user_id": (string)req->misc->session->user->id]),
		);
	}
	return twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?only_manageable_rewards=true&broadcaster_id=" + req->misc->session->user->id,
			(["Authorization": "Bearer " + req->misc->session->token])
		)->then(lambda(mapping info) {
			rewards = info->data;
			return Concurrent.all(lambda(string id) {return get_helix_paginated("https://api.twitch.tv/helix/channel_points/custom_rewards/redemptions",
				([
					"broadcaster_id": req->misc->session->user->id,
					"reward_id": id,
					"status": "UNFULFILLED",
					"first": "50",
				]),
				(["Authorization": "Bearer " + req->misc->session->token]),
			);}(rewards->id[*]));
		})->then(lambda(array(array) redemptions) {
			array tickets = ({ });
			mapping people = ([]);
			mapping values = cfg->giveaway->rewards || ([]);
			foreach (redemptions * ({ }), mapping redem) {
				if (!people[redem->user_id]) tickets += ({people[redem->user_id] = ([
					"name": redem->user_name,
				])});
				people[redem->user_id]->tickets += values[redem->reward->id];
			}
			return render_template("chan_giveaway.md", (["vars": ([
				"rewards": rewards,
				"tickets": tickets,
			])]));
		});
}

protected void create(string name)
{
	::create(name);
	G->G->webhook_endpoints->redemption = points_redeemed;
}
