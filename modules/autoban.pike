//Somewhat misnamed now, this provides the coded detection of "buy-follows" bots
inherit hook;
inherit annotated;

//Keyword checks to see if someone's trying to sell us followers. Will be
//added to as necessary, and all users of this blacklist will automatically
//start noticing the new ones. Anything that has (at least) one from column
//A and one from column B will be flagged as a follower seller.
constant buyfollows = ({"cheap viewers", "cheap followers", "best viewers", "best followers"});
constant urls = ({".ru", "streamboo"});

@export: int(1bit) is_selling_followers(string msg) {
	//To avoid bots messing with Unicode combining characters, strip 'em before comparing.
	//NFKD normalization should split off any combining characters, and fold all kinds of
	//equivalent characters together. This might still give wrong results though - test.
	msg = lower_case(filter(Unicode.normalize(msg, "NFKD")) {return __ARGS__[0] < 256;});
	int buyingfollows, hasurl;
	foreach (buyfollows, string badword) if (has_value(msg, badword)) buyingfollows = 1;
	foreach (urls, string badword) if (has_value(msg, badword)) hasurl = 1;
	return buyingfollows && hasurl;
}

@hook_allmsgs: int message(object channel, mapping person, string msg) {
	//Detect the follower-selling bots and provide a flag that a trigger can examine.
	person->vars["{@buyfollows}"] = (string)is_selling_followers(msg);
}

protected void create(string name) {::create(name);}
