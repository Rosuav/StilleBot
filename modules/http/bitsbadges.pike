inherit http_endpoint;
inherit irc_callback;

/* Bits VIP leaderboard: bitsbadges?period=month

* TODO: Support other periods - currently it assumes months in some places
* Highlight any that currently have VIP badges. May need a /vip command and its associated response.
* May need a record of who has permanent badges and should therefore be immune to the "remove" button
* Check formatting/layout and make sure it's still practical when there are lots of cheerers
* Highlight only the first ten eligible names
*/

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

continue mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	if (mapping resp = ensure_login(req, "bits:read")) return resp;
	if ((<"year", "month", "week", "day">)[req->variables->period]) {
		//This is a bit of a mess, but it kinda works. Would be nice to tidy it up a bit though.
		if (mapping resp = ensure_login(req, "bits:read moderation:read channel:moderate chat_login chat:edit")) return resp;
		string period = req->variables->period;
		if (string start = req->variables->vip || req->variables->unvip) {
			sscanf(start, "%d-%d-%dT%d:%d:%dZ", int year, int month, int day, int hour, int min, int sec);
			start = sprintf("%04d-%02d-%02dT%02d:%02d:%02dZ", year, month, day, hour, min, sec);
			mapping info = yield(twitch_api_request("https://api.twitch.tv/helix/bits/leaderboard?count=25&period=" + period
				+ "&started_at=" + start,
				(["Authorization": "Bearer " + req->misc->session->token])));
			int limit = 10; //TODO: Make configurable
			mapping mods = yield(twitch_api_request("https://api.twitch.tv/helix/moderation/moderators?broadcaster_id="
				+ req->misc->session->user->id,
				(["Authorization": "Bearer " + req->misc->session->token])));
			multiset is_mod = (multiset)mods->data->user_id;
			string cmd = req->variables->vip ? "/vip" : "/unvip";
			array(string) cmds = ({ });
			array(string) people = ({ });
			foreach (info->data, mapping person) {
				if (is_mod[person->user_id]) continue;
				cmds += ({cmd + " " + person->user_login});
				people += ({person->user_name});
				if (!--limit) break;
			}
			if (!sizeof(cmd)) cmds = ({"No non-mods to manage VIP badges for"}); //Highly unlikely in practice :)
			else cmds = ({(req->variables->vip ? "Adding VIP status to: " : "Removing VIP status from: ") + people * ", "})
				+ cmds + ({req->variables->vip ? "Done adding VIPs." : "Done removing VIPs."});
			irc_connect(([
				"user": req->misc->session->user->login,
				"pass": "oauth:" + req->misc->session->token,
			]))->then() {[object irc] = __ARGS__;
				irc->send("#" + req->misc->session->user->login, cmds[*]);
				irc->quit();
			};
			return "OK";
		}
		if (mixed vars = cache[req->misc->session->user->id]) //Hack
			return render_template("bitsbadges.md", ([
				"vars": vars,
				"text": sprintf("<div id=leaders></div><script type=module src=%q></script>", G->G->template_defaults["static"]("bitsbadges.js")),
			]));
		mapping info = yield(twitch_api_request("https://api.twitch.tv/helix/bits/leaderboard?count=25&period=" + period,
				(["Authorization": "Bearer " + req->misc->session->token])));
		sscanf(info->date_range->started_at, "%d-%d-%*dT%*d:%*d:%*dZ", int year, int month);
		array periodicdata = ({({"Current", info->data, ""})});
		array(string) months = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec" / " ";
		for (int i = 0; i < 6; ++i) {
			//Get stats for a previous month. TODO: Make this work with any period, not just month
			//Will need to worry about timezones. Maybe don't support day??
			if (!--month) {--year; month = 12;}
			mapping info = yield(twitch_api_request("https://api.twitch.tv/helix/bits/leaderboard?count=25&period=" + period
					+ sprintf("&started_at=%d-%02d-02T00:00:00Z", year, month),
					(["Authorization": "Bearer " + req->misc->session->token])));
			periodicdata += ({({sprintf("%s %d", months[month - 1], year), info->data, info->date_range->started_at})});
		}
		mapping mods = yield(twitch_api_request("https://api.twitch.tv/helix/moderation/moderators?broadcaster_id="
				+ req->misc->session->user->id,
				(["Authorization": "Bearer " + req->misc->session->token])));
		return render_template("bitsbadges.md", ([
			"vars": cache[req->misc->session->user->id] = ([
				"period": period,
				"periodicdata": periodicdata,
				"mods": mods->data,
			]),
			"text": sprintf("<div id=leaders></div><script type=module src=%q></script>", G->G->template_defaults["static"]("bitsbadges.js")),
		]));
	}
	mapping info = yield(twitch_api_request("https://api.twitch.tv/helix/bits/leaderboard?count=100",
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
	return render_template("bitsbadges.md", (["text": text]));
}

protected void create(string name) {::create(name);}
