inherit http_endpoint;

constant markdown = #"# Top clips finder

<form><label>Channel: <input name=channel value=\"$$channel||$$\"></label>
<label>Start date: <input name=startdate type=date value=\"$$startdate||$$\"></label>
<button type=submit>Find clips</button></form>

$$result||$$
<style>
ul {list-style-type: none;}
</style>
";

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	string channel = req->variables->channel, startdate = req->variables->startdate;
	if (!channel) return render_template(markdown, ([]));
	int uid = await(get_user_id(channel));
	if (!uid) return render_template(markdown, (["channel": channel, "startdate": startdate, "result": "## Invalid channel name"]));
	array clips = await(get_helix_paginated("https://api.twitch.tv/helix/clips", (["broadcaster_id": (string)uid])));
	string result = sprintf("## Total clips: %d\n", sizeof(clips));
	clips = filter(clips) {return __ARGS__[0]->created_at >= startdate;};
	result += sprintf("## Recent clips: %d\n", sizeof(clips));
	sort(clips->view_count, clips);
	int limit = (int)req->variables->limit || 5;
	if (limit > sizeof(clips)) limit = sizeof(clips);
	for (int i = 0; i < limit; ++i) {
		mapping clip = clips[i];
		result += sprintf("### %d: %s\n", i + 1, clip->title);
		if (clip->featured) result += "#### Featured clip!\n";
		result += sprintf("* Created %s, viewed %d times\n", clip->created_at, clip->view_count);
		result += sprintf("* Clipped by [%s](https://twitch.tv/%<s)\n", clip->creator_name);
		result += sprintf("* [![Clip thumbnail](%s)](%s)\n", clip->thumbnail_url, clip->url);
	}
	return render_template(markdown, ([
		"channel": channel, "startdate": startdate,
		"result": result,
	]));
}
