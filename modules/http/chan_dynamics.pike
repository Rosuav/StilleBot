inherit http_endpoint;
constant markdown = #"# Channel points - dynamic rewards

Title | Base cost | Activation condition | Growth Formula | Current cost | Actions
------|-----------|----------------------|----------------|--------------|--------
-     | -         | -                    | -              | -            | (loading...)
{: #rewards}

[Add dynamic reward](:#add) Copy from: <select id=copyfrom><option value=\"-1\">(none)</option></select>

Choose how the price grows by setting a formula, for example:
* `PREV * 2` (double the price every time)
* `PREV + 500` (add 500 points per purchase)
* `PREV * 2 + 1500` (double it, then add 1500 points)

Rewards will reset to base price whenever the stream starts, and will be automatically
put on pause when the stream is offline. Note that, due to various delays, it's best to
have a cooldown on the reward itself - at least 30 seconds - to ensure that two people
can't claim the reward at the same price.

To have dynamic pricing carry from one stream to another, set the base cost to zero.

[Configure reward details here](https://dashboard.twitch.tv/viewer-rewards/channel-points/rewards)

<style>
code {background: #ffe;}
</style>
";

/* Each one needs:
- ID, provided by Twitch. Clicking "New" assigns one.
- Base cost. Whenever the stream goes live, it'll be updated to this.
- Formula for calculating the next. Use PREV for the previous cost. Give examples.
- Title, which also serves as the description within the web page
- Other attributes maybe, or let people handle them elsewhere

TODO: Expand on chan_pointsrewards so it can handle most of the work, including the
JSON API for managing the rewards (the HTML page will be different though).
*/

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	if (req->misc->session->fake) 
		return render_template("login.md", (["scopes": "channel:manage:redemptions",
			"msg": "a real channel, not the demo. Feel free to pretend though"]));
	if (string scopes = ensure_bcaster_token(req, "channel:manage:redemptions"))
		return render_template("login.md", (["scopes": scopes, "msg": "authentication as the broadcaster"]));
	//TODO: Should non-mods be allowed to see the details?
	if (!req->misc->is_mod) return render_template("login.md", (["msg": "moderator privileges"]));
	return render_template(markdown, ([
		"vars": (["ws_type": "chan_pointsrewards", "ws_group": req->misc->channel->name, "ws_code": "chan_dynamics"]),
	]) | req->misc->chaninfo);
}
