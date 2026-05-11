inherit http_endpoint;
constant markdown = #"# Channel points - dynamic rewards

Title | Description | Availability | Cost increment | Current cost | Actions
------|-------------|--------------|----------------|--------------|--------
-     | -           | -            | -              | -            | (loading...)
{: #rewards}

[Save All](:#save_all)

<select id=copyfrom><option value=\"-1\">-- Create new --</option></select> [Add dynamic reward](:#add)

Use [variables](variables) in the title or description to automatically update them
whenever the variable changes.

Note that, due to various delays, it's best to have a cooldown on the reward itself -
at least 30 seconds - to ensure that two people can't claim the reward at the same price.

[Configure reward details here](https://dashboard.twitch.tv/u/$$channel$$/viewer-rewards/channel-points/rewards)

> ### Edit description
>
> <textarea id=editme rows=8 cols=50></textarea>
>
> [Apply](:#editapply) [Cancel](:.dialog_close)
{: tag=formdialog #editdlg}
";

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	if (string scopes = !req->misc->session->fake && ensure_bcaster_token(req, "channel:manage:redemptions"))
		return render_template("login.md", (["scopes": scopes, "msg": "authentication as the broadcaster"]) | req->misc->chaninfo);
	//TODO: Should non-mods be allowed to see the details?
	if (!req->misc->is_mod) return render_template("login.md", (["msg": "moderator privileges"]) | req->misc->chaninfo);
	return render_template(markdown, ([
		"vars": (["ws_type": "chan_rewards", "ws_group": req->misc->channel->name, "ws_code": "chan_dynamics"]),
	]) | req->misc->chaninfo);
}
