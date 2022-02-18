inherit command;
inherit hook;
constant featurename = "info";
constant require_moderator = 1;
constant docstring = #"
Keyword-based automatic moderation.

Usage: `!autoban time badword`

If that word is seen by any non-moderator, and if the bot is a mod in your
channel, then the person will be immediately timed out for the specified
number of seconds, or permanently banned if time is the word 'ban'.

Specify a time of 0 to remove the autoban.

Be very careful of false positives, particularly if banning. If there's any
chance the word would be said legitimately, it's safest to just time the
person out (or purge, which is a one-second timeout).

Note that the word (or phrase) will be recognized case insensitively as a
substring within the person's message. It does not actually have to be a
word per se.
";

//Keyword checks to see if someone's trying to sell us followers. Will be
//added to as necessary, and all users of this blacklist will automatically
//start noticing the new ones.
constant buyfollows = ({"addviewers.com", "bigfollows . com", "bigfollows .com", "bigfollows*com", "bigfollow s . com",
	"vk.cc/c7aT0b", "bigfollows-com", "u.to/jazMGw", "clck.ru/ZEWvg", "vk.cc/c8R4EY"});

string process(object channel, object person, string param)
{
	int tm; string badword;
	if (sscanf(param, "ban %s", badword) && badword) tm = -1;
	else if (sscanf(param, "%d %s", int t, badword) && badword) tm = t;
	else return "@$$: Try !autoban 300 some-bad-word";

	badword = lower_case(badword); //TODO: Switch this out for a proper Unicode casefold
	if (badword == "***") return "@$$: It looks like that word is blacklisted on Twitch, so I can't see it to autoban for it.";
	if (!channel->config->autoban) channel->config->autoban = ([]);
	if (!tm)
	{
		int prev = m_delete(channel->config->autoban, badword);
		persist_config->save();
		if (!prev) return "@$$: That word wasn't banned.";
		if (prev == -1) return "@$$: That word will no longer cause an automatic ban.";
		return sprintf("@$$: That word will no longer cause an automatic %d second timeout.", prev);
	}
	channel->config->autoban[badword] = tm;
	persist_config->save();
	if (tm == -1) return "@$$: Done. Next time I see that, I'll automatically ban.";
	return sprintf("@$$: Done. Next time I see that, I'll automatically time out for %d seconds.", tm);
}

@hook_allmsgs:
int message(object channel, mapping person, string msg)
{
	msg = lower_case(msg);
	//Detect the follower-selling bots and provide a flag that a trigger can examine.
	person->vars["{@buyfollows}"] = "0";
	foreach (buyfollows, string badword) if (has_value(msg, badword)) person->vars["{@buyfollows}"] = "1";
	if ((
		has_value(msg, "Want to become famous? Buy followers") ||
		has_value(msg, "Buy followers, primes and viewers on") ||
		has_value(msg, "Buy followers and viewers on")
	) && (
		has_value(msg, " http://") || has_value(msg, " https://") || has_value(msg, " alturl.com") ||
		has_value(msg, " vk.cc/") || has_value(msg, " clck.ru") || has_value(msg, " cutt.ly") ||
		has_value(msg, " u.to/") || has_value(msg, " y.ly/") //These are the URL shorteners they use
	)) person->vars["{@buyfollows}"] = "1";
	mapping autoban = channel->config->autoban;
	if (!autoban) return 0;
	if (person->badges->_mod) return 0; //Don't time out mods. It usually won't work anyway, but don't try.
	foreach (autoban; string badword; int tm) if (has_value(msg, badword))
	{
		if (tm == -1) send_message(channel->name, "/ban " + person->user);
		if (tm > 0) send_message(channel->name, sprintf("/timeout %s %d", person->user, tm));
	}
}

protected void create(string name)
{
	register_hook("all-msgs", Program.defined(this_program));
	::create(name);
}
