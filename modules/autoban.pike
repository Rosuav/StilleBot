//Somewhat misnamed now, this provides the coded detection of "buy-follows" bots
//and management of automod-held messages.
inherit hook;
inherit annotated;
inherit builtin_command;

//Keyword checks to see if someone's trying to sell us followers. Will be
//added to as necessary, and all users of this blacklist will automatically
//start noticing the new ones. Anything that has (at least) one from column
//A and one from column B will be flagged as a follower seller.
constant buyfollows = ({"viewers", "cheap followers", "best followers", "become popular with", "streaming zero", "best promotion"});
constant urls = ({".ru", "streamboo", ".online", "s t r e a m b o o", "Stream_Promotion_bot", "promotion. ru", "twitchmax .com", "streamerbeat com", "twitch .ad", "twitchstar .com"});

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

constant builtin_description = "Manage held messages";
constant builtin_name = "Automod Message";
constant builtin_param = ({"Message ID", "/Action/ALLOW/DENY"});
constant vars_provided = ([]);

__async__ mapping message_params(object channel, mapping person, array param, mapping cfg) {
	twitch_api_request("https://api.twitch.tv/helix/moderation/automod/message",
		(["Authorization": (int)cfg->speaker]),
		(["json": (["user_id": (string)cfg->speaker, "msg_id": param[0], "action": param[1]])]),
	);
	return ([]);
}

protected void create(string name) {::create(name);}
