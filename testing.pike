//Build code into this file to be able to quickly and easily run it using "stillebot --test"
inherit annotated;

protected void create(string name) {
	::create(name);
	G->G->irc = (["channels": ([])]); //Hack: Prevent follower hook from doing anything
	string endpoint = "follower", arg = "rosuav";
	object handler = G->G->eventhook_types[endpoint];
	handler->callback(arg, (["test": 1]));
	exit(0);
}
