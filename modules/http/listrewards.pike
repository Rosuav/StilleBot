inherit http_endpoint;

string custom_reward(mapping rew)
{
	return sprintf(
#"<li%s>
	<a href=\"https://rosuav.github.io/OSDRewards/?channel=%s&rewardid=%s\">%s</a>
	Cost: %d
	%s
	<img src=\"%s\" alt=\"(redemption image)\">
</li>",
		rew->background_color ? " style=\"background-color: " + rew->background_color + "\"" : "",
		rew->broadcaster_name, rew->id, replace(rew->title, (["<": "&lt;", "&": "&amp;"])),
		(int)rew->cost,
		rew->is_user_input_required ? "" : "<span> - No input required; may not function correctly - </span>",
		rew->default_image->url_1x,
	);
}

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	if (mapping resp = ensure_login(req, "channel:read:redemptions")) return resp;
	object user = user_text();
	return twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id=" + req->misc->session->user->id,
			(["Authorization": "Bearer " + req->misc->session->token])
		)->then(lambda(mapping info) {
			return render_template("listrewards.md", ([
				"rewards": req->variables->raw ? "<pre>" + Standards.JSON.encode(info->data, 7) + "</pre>" :
					sizeof(info->data) ? custom_reward(info->data[*]) * "" :
					"<li>No custom rewards found</li>",
			]));
		});
}
