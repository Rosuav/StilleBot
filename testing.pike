//Build code into this file to be able to quickly and easily run it using "stillebot --test"
inherit irc_callback;

object done = Concurrent.Promise();

constant messagetypes = ({"USERSTATE"});
void irc_message(string type, string chan, string msg, mapping attrs) {
	done->success(attrs->emote_sets / ",");
}

continue Concurrent.Future do_stuff() {
	object irc = yield(irc_connect((["join": "#twitch", "capabilities": "tags commands" / " "])));
	array sets = yield(done);
	//werror("Emote sets: %O\n", sets);
	array emotes = yield(Concurrent.all(map(sets / 25.0) {return
		get_helix_paginated("https://api.twitch.tv/helix/chat/emotes/set", (["emote_set_id": __ARGS__[0]]));
	}));
	emotes *= ({ });
	werror("Got %d emotes.\n", sizeof(emotes));
	mapping types = ([]);
	foreach (emotes, mapping e) types[e->emote_type]++;
	werror("Emote types: %O\n", types);
	array bits = filter(emotes) {return __ARGS__[0]->emote_type == "bitstier";};
	sort(bits->name, bits);
	sort((array(int))bits->emote_set_id, bits);
	sort((array(int))bits->owner_id, bits);
	//foreach (bits, mapping e) write("\t%O -> %O -> %O\n", e->name, e->emote_set_id, yield(get_user_info(e->owner_id))->display_name);
	mapping emo = yield(twitch_api_request("https://api.twitch.tv/helix/chat/emotes/global"));
	mapping emoteset = ([]);
	foreach (emotes, mapping e) emoteset[e->name] = e->emote_set_id;
	mapping counts = ([]);
	foreach (emo->data, mapping e) counts[emoteset[e->name]]++;
	werror("Emote counts: %O\n", counts);
	werror("All done\n");
	exit(0);
}

protected void create(string name) {
	::create(name);
	spawn_task(do_stuff());
}

/*
It's possible to query a channel's emotes, but not a user's.
It's also not possible currently to find out exactly how an emote was unlocked (eg bits - how many?).
Is there any way to find out what set an emote belongs to, if it wasn't listed in USERSTATE?
Would like to see the emote set(s) that contain, for instance, hype train emotes.
GQL can get this info, but even then, querying the emote sets in question does not yield useful results,
so there's no point hard-coding a bunch of emote set IDs.
*/
