inherit builtin_command;
constant builtin_name = "Choose from chat";
constant builtin_description = "Pick a random person who has chatted recently";
//TODO maybe: Optional filter to only followers and/or only subs?
constant builtin_param = ({"#Time limit", "#Number of people"});
constant vars_provided = ([
	"{chat}": "Array of chatters with their name and uid",
	"{chat1name}": "Name of first selected chatter - same as {chat.1.name}",
	"{chat1uid}": "User ID of first selected chatter - same as {chat.1.uid}",
	"{chat2name}": "Name of second selected chatter, etc",
	"{chat2uid}": "User ID of second selected chatter, etc",
]);

__async__ mapping message_params(object channel, mapping person, array param) {
	if (!sizeof(param)) param = ({"300"});
	if (sizeof(param) < 2) param = ({"1"});
	int limit = time() - (int)param[0];
	array users = ({ });
	foreach (G_G_("participants", channel->name[1..]); string name; mapping info)
		if (info->lastnotice >= limit) users += ({info->userid});
	if (!sizeof(users)) return (["{chat1name}": "", "{chat1uid}": "0"]); //Unlike $participant$, this will not fall back on self.
	int n = (int)param[1];
	array sel;
	if (n < 2) sel = ({random(users)});
	else sel = Array.shuffle(users)[..n - 1];
	mapping ret = (["{chat}": ({ })]);
	array userinfo = await(get_users_info(sel));
	mapping display_name = mkmapping(userinfo->id, userinfo->display_name);
	foreach (sel; int i; int uid) {
		mapping user = (["name": display_name[(string)uid] || (string)uid, "uid": (string)uid]);
		ret["{chat}"] += ({user});
		ret[sprintf("{chat%dname}", i + 1)] = user->name;
		ret[sprintf("{chat%duid}", i + 1)] = user->uid;
	}
	return ret;
}
