inherit http_endpoint;

constant markdown = #"# Creator goals

<pre>$$goals$$</pre>
";

continue string|mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	if (mapping resp = ensure_login(req, "channel:read:goals")) return resp;
	mapping info = yield(twitch_api_request("https://api.twitch.tv/helix/goals?broadcaster_id=" + req->misc->session->user->id,
		(["Authorization": "Bearer " + req->misc->session->token])));
	return render_template(markdown, (["goals": sprintf("%O\n", info)]));
}
