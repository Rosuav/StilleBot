//Build code into this file to be able to quickly and easily run it using "stillebot --test"
inherit irc_callback;
constant channels = ({"#rosuav", "#stephenangelico", "#loudlotus", "#mustardmine"});

continue Concurrent.Future do_stuff() {
	werror("loudlotus: %O\n", persist_status->path("bcaster_token_scopes")["loudlotus"]);
	werror("mustardmine: %O\n", persist_status->path("bcaster_token_scopes")["mustardmine"]);
	object irc1 = yield(irc_connect((["user": "loudlotus"])));
	object irc2 = yield(irc_connect((["user": "mustardmine"])));
	irc1->send(channels[*], "Hello, world!");
	irc2->send(channels[*], "Mustard isn't a bird.");
	werror("QUEUE 1 [%O]: %O\nQUEUE 2 [%O]: %O\n", hash_value(irc1), irc1->queue, hash_value(irc2), irc2->queue);
	mixed _ = yield(Concurrent.all(irc1->promise(), irc2->promise()));
	werror("All done\n");
	exit(0);
}

protected void create(string name) {
	::create(name);
	spawn_task(do_stuff());
}

/* Global token bucket for Twitch message sending
G->G->irc_token_bucket[]
Bucket key: user "#" channel, eg MM talking in my channel is "mustardmine#rosuav"
Bucket is array of ({last-msg, half-minute-count});
G->G->user_mod_status[key] gets set to 1 if and only if we know for sure that we're a mod.
Check that if not your own channel. Limit is 20 per half minute if not mod, 100 if mod.

Additional special buckets:
"user#!login" - auth attempts for that user
"user#!join" - channel join attempts for that user
These use per-ten-second counts instead of per-half-minute.
*/
