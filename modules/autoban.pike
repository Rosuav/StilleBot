//Somewhat misnamed now, this provides the coded detection of "buy-follows" bots
inherit hook;

//Keyword checks to see if someone's trying to sell us followers. Will be
//added to as necessary, and all users of this blacklist will automatically
//start noticing the new ones.
constant buyfollows = ({"cheap viewers on", "cheap followers on", "best viewers on", "best followers on"});

@hook_allmsgs:
int message(object channel, mapping person, string msg)
{
	//Detect the follower-selling bots and provide a flag that a trigger can examine.
	person->vars["{@buyfollows}"] = "0";
	//To avoid bots messing with Unicode combining characters, strip 'em before comparing.
	//NFKD normalization should split off any combining characters, and fold all kinds of
	//equivalent characters together. This might still give wrong results though - test.
	msg = lower_case(filter(Unicode.normalize(msg, "NFKD")) {return __ARGS__[0] < 256;});
	foreach (buyfollows, string badword) if (has_value(msg, badword)) person->vars["{@buyfollows}"] = "1";
}
