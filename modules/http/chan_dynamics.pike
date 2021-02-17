inherit http_endpoint;

/* Each one needs:
- ID, provided by Twitch. Clicking "New" assigns one.
- Base cost. Whenever the stream goes live, it'll be updated to this.
- Formula for calculating the next. Use PREV for the previous cost. Give examples.
- Title, which also serves as the description within the web page
- Other attributes maybe, or let people handle them elsewhere

TODO: Expand on chan_giveaway so it can handle most of the work, including the
JSON API for managing the rewards (the HTML page will be different though).
*/

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	if (mapping resp = ensure_login(req, "channel:manage:redemptions")) return resp;
	mapping cfg = req->misc->channel->config;
	string chan = req->misc->channel->name[1..];
	if (chan != req->misc->session->user->login)
		return render_template("login.md", req->misc->chaninfo); //As with chan_giveaway, would be nice to reword that
	persist_status->path("bcaster_token")[chan] = req->misc->session->token;
	persist_status->save();
	//If there are no rewards currently, save some trouble.
	if (!cfg->dynamic_rewards || !sizeof(cfg->dynamic_rewards))
		return render_template("chan_dynamics.md", (["vars": (["rewards": ({ })])]));
	//Prune the list of any deleted ones, and get titles for the others
	return twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?only_manageable_rewards=true&broadcaster_id=" + req->misc->session->user->id,
			(["Authorization": "Bearer " + req->misc->session->token]))
		->then(lambda(mapping info) {
			array rewards = ({ });
			multiset unseen = (multiset)indices(cfg->dynamic_rewards);
			foreach (info->data, mapping rew) {
				unseen[rew->id] = 0;
				mapping r = cfg->dynamic_rewards[rew->id];
				if (r) rewards += ({r | (["id": rew->id, "title": r->title = rew->title, "curcost": rew->cost])});
			}
			m_delete(cfg->dynamic_rewards, ((array)unseen)[*]);
			persist_config->save();
			return render_template("chan_dynamics.md", (["vars": (["rewards": rewards])]));
		});
}
