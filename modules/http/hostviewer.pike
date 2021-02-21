inherit http_endpoint;

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	if (req->variables->channel)
	{
		//Look up the ID of this channel and redirect to https://rosuav.github.io/LispWhispers/hosts?channelid={{USER}}
		return get_user_info(req->variables->channel, "login")->then(lambda(mapping info) {
			return redirect("https://rosuav.github.io/LispWhispers/hosts?" +
				Protocols.HTTP.http_encode_query(([
					"channelid": (string)info->id,
					"channelname": info->display_name,
				])), 301);
		});
	}
	if (req->variables->target)
	{
		//Twitch's servers don't support CORS.
		return Protocols.HTTP.Promise.get_url("https://tmi.twitch.tv/hosts",
				Protocols.HTTP.Promise.Arguments((["variables": (["include_logins": "1", "target": req->variables->target])])))
			->then(lambda(Protocols.HTTP.Promise.Result res) {
				return ([
					"error": res->status,
					"type": res->content_type,
					"data": res->get(),
					"extra_heads": (["Access-Control-Allow-Origin": "*"]),
				]);
			});
	}
	return render_template("hostviewer.md", ([]));
}
