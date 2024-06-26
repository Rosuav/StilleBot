inherit http_endpoint;

constant markdown = #"# Who has bits badges?

$$text$$
";

constant levels = ({5000000, 4500000, 4000000, 3500000, 3000000, 2500000, 2000000,
	1750000, 1500000, 1250000, 1000000, 900000, 800000, 700000, 600000, 500000,
	400000, 300000, 200000, 100000, 75000, 50000, 25000, 10000, 5000, 1000});

string header(int level)
{
	foreach (({({1000000, "M"}), ({1000, "K"}), ({1, ""})}), [float scale, string suffix])
		if (level >= scale) return sprintf("\n* %g%s: ", level / (float)scale, suffix);
	return "* 0: "; //Shouldn't happen
}

mapping(int|string:mixed) cache = ([]);

__async__ string|mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	if (mapping resp = ensure_login(req, "bits:read")) return resp;
	mapping info = await(twitch_api_request("https://api.twitch.tv/helix/bits/leaderboard?count=100",
			(["Authorization": "Bearer " + req->misc->session->token])));
	if (!sizeof(info->data)) return render_template("bitsbadges.md", (["text": "No data found."]));
	int lvl = 0;
	while (lvl < sizeof(levels) && levels[lvl] > info->data[0]->score) ++lvl;
	if (lvl >= sizeof(levels)) return render_template("bitsbadges.md", (["text": "Nobody has any badges."]));
	string text = header(levels[lvl]);
	string users = "";
	nomoreusers: foreach (info->data, mapping user)
	{
		while (user->score < levels[lvl])
		{
			//Doesn't clear out the user list. Users are shown against all appropriate ranks.
			text += users[2..];
			if (++lvl >= sizeof(levels)) break nomoreusers;
			text += header(levels[lvl]);
		}
		users += ", " + user->user_name;
	}
	if (sizeof(info->data) == 100) text += "\n\nNOTE: This shows only the top 100 users, and the last tier may have other people in it.";
	return render_template(markdown, (["text": text]));
}
