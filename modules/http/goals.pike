inherit http_endpoint;

constant markdown = #"# Creator goals

<pre>$$goals$$</pre>
";

__async__ string|mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	if (mapping resp = ensure_login(req, "channel:read:goals")) return resp;
	mapping info = await(twitch_api_request("https://api.twitch.tv/helix/goals?broadcaster_id=" + req->misc->session->user->id,
		(["Authorization": "Bearer " + req->misc->session->token])));
	return render_template(markdown, (["goals": sprintf("%O\n", info)]));
}
