inherit builtin_command;
constant builtin_name = "Choose from chat";
constant builtin_description = "Pick a random person who has chatted recently";
//TODO maybe: Optional filter to only followers and/or only subs?
constant builtin_param = ({"Time limit", "Number of people"});
constant vars_provided = ([
	"{chat1name}": "Name of first selected chatter",
	"{chat1uid}": "User ID of first selected chatter",
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
	mapping ret = ([]);
	foreach (sel; int i; int uid) {
		ret[sprintf("{chat%dname}", i + 1)] = await(get_user_info(uid))->display_name;
		ret[sprintf("{chat%duid}", i + 1)] = (string)uid;
	}
	return ret;
}
