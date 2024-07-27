//Somewhat misnamed now, this provides the coded detection of "buy-follows" bots
inherit hook;

//Keyword checks to see if someone's trying to sell us followers. Will be
//added to as necessary, and all users of this blacklist will automatically
//start noticing the new ones.
constant buyfollows = ({"dogehype dot com", "Go to streamrise", "StreamBoo", "Cheap viewers on", "Best viewers on", "Best Viewers on", "Cheap Viewers on"});

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
		has_value(msg, "Best followers, primes and viewers on") ||
		has_value(msg, "Get viewers, followers") ||
		has_value(msg, "Buy followers and viewers on")
	) && (
		has_value(msg, " http://") || has_value(msg, " https://") || has_value(msg, " alturl.com") ||
		has_value(msg, " vk.cc/") || has_value(msg, " clck.ru") || has_value(msg, " cutt.ly") ||
		has_value(msg, "mystrm .store") || has_value(msg, "y0urfollowz. com") || has_value(msg, "viewers .shop") ||
		has_value(msg, " u.to/") || has_value(msg, " y.ly/") || has_value(msg, " t.ly/") //These are the URL shorteners they use
	)) person->vars["{@buyfollows}"] = "1";
}
