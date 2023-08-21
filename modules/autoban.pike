//Somewhat misnamed now, this provides the coded detection of "buy-follows" bots
inherit command;
inherit hook;
constant active_channels = ({""}); //Deprecated, slated for removal.

//Keyword checks to see if someone's trying to sell us followers. Will be
//added to as necessary, and all users of this blacklist will automatically
//start noticing the new ones.
constant buyfollows = ({"addviewers.com", "bigfollows . com", "bigfollows .com", "bigfollows*com", "bigfollow s . com",
	"vk.cc/c7aT0b", "bigfollows-com", "u.to/jazMGw", "clck.ru/ZEWvg", "vk.cc/c8R4EY", "dogehype dot com"});

string process(object channel, object person, string param) {return "Command disabled, create a trigger instead.";}

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

protected void create(string name) {
	::create(name);
	//Clean out legacy configs
	foreach (list_channel_configs(), mapping cfg) if (m_delete(cfg, "autoban")) persist_config->save();
}
