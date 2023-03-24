inherit http_endpoint;

constant markdown = #"# Twitch Login scope trimmer

Is a site asking more permissions (scopes) that you think it should get? It's YOUR choice what you permit,
so don't be afraid to remove some of the scopes before authenticating!

Paste the login URL here: <input id=original_url size=120>

Scopes requested:
{:#origin}

* (paste a Twitch login URL in the above field to start trimming)
{:#scopelist}

Use this link instead: <a id=resultant_url href=\"waiting...\" target=_blank>Log in with Twitch</a>

None of this information is sent to my server or anywhere else; your preferences are saved here in your
browser's local storage and that's all.

<script type=module src=\"$$static||scopetrim.js$$\"></script>
";

continue mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	return render_template(markdown, ([
		"vars": (["all_twitch_scopes": all_twitch_scopes]),
	]));
}
