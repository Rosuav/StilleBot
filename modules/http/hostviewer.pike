inherit http_endpoint;

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	if (req->variables->channel)
	{
		//Look up the ID of this channel and redirect to https://rosuav.github.io/LispWhispers/hosts?channelid={{USER}}
		return get_user_id(req->variables->channel)->then(lambda(int userid) {
			return redirect("https://rosuav.github.io/LispWhispers/hosts?channelid=" + userid);
		});
	}
	return render_template("hostviewer.md", ([]));
}
