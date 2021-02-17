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
	return render_template("chan_giveaway.md", (["vars": (["rewards": cfg->dynamic_rewards || ([])])]));
}
