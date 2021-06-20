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
	if (mapping resp = ensure_bcaster_login(req, "channel:manage:redemptions")) return resp;
	mapping cfg = req->misc->channel->config;
	//Prune the list of any deleted ones, and get titles for the others
	return twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id=" + req->misc->session->user->id,
			(["Authorization": "Bearer " + req->misc->session->token]))
		->then(lambda(mapping info) {
			array rewards = ({ });
			mapping current = cfg->dynamic_rewards || ([]);
			multiset unseen = (multiset)indices(current);
			foreach (info->data, mapping rew) {
				unseen[rew->id] = 0;
				mapping r = current[rew->id];
				if (r) rewards += ({r | (["id": rew->id, "title": r->title = rew->title, "curcost": rew->cost])});
			}
			if (cfg->dynamic_rewards) m_delete(cfg->dynamic_rewards, ((array)unseen)[*]);
			persist_config->save();
			return render_template("chan_dynamics.md", (["vars": (["rewards": rewards, "allrewards": info->data])]));
		});
}
