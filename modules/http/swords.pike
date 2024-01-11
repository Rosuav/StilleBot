//Quick lookup of where you carry a sword
inherit http_endpoint;
constant markdown = #"# The swords you carry

You carry $$swordcount$$ swords across Twitch.

$$swords$$

<style>
.avatar {max-width: 40px;}
</style>
";

string format_sword(mapping chan, mapping details) {
	details = details[chan->broadcaster_id] || ([]);
	return sprintf("* <a href=\"https://twitch.tv/%s\"><img class=avatar src=\"%s\" alt=\"Channel avatar\"> %s</a>",
		chan->broadcaster_login,
		details->profile_image_url || "",
		chan->broadcaster_name,
	);
}

continue string|mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	if (mapping resp = ensure_login(req, "user:read:moderated_channels")) return resp;
	array channels = yield(get_helix_paginated("https://api.twitch.tv/helix/moderation/channels",
		(["user_id": req->misc->session->user->id]),
		(["Authorization": "Bearer " + req->misc->session->token])));
	array details_raw = yield(get_helix_paginated("https://api.twitch.tv/helix/users", (["id": channels->broadcaster_id])));
	mapping details = mkmapping(details_raw->id, details_raw);
	return render_template(markdown, ([
		"swordcount": (string)sizeof(channels),
		"swords": format_sword(channels[*], details) * "\n",
	]));
}
