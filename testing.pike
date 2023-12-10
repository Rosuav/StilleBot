//Build code into this file to be able to quickly and easily run it using "stillebot --test"
inherit annotated;
@export: mapping get_channel_config(string|int chan) {error("Channel configuration unavailable.\n");}
//Rather than actually load up all the builtins, just make sure the names can be validated.
//List is correct as of 20231210.
constant builtin_names = ({"chan_share", "chan_giveaway", "shoutout", "cmdmgr", "hypetrain", "chan_mpn", "tz", "chan_alertbox", "raidfinder", "uptime", "renamed", "log", "quote", "nowlive", "calc", "chan_monitors", "chan_errors", "argsplit", "chan_pointsrewards", "chan_labels", "uservars"});

protected void create(string name) {
	::create(name);
	G->G->builtins = mkmapping(builtin_names, allocate(sizeof(builtin_names), 1));
	G->bootstrap("modules/cmdmgr.pike");
	object mustard = G->bootstrap("mustard.pike");
	G->G->argv -= ({"--test"});
	mustard->main(sizeof(G->G->argv), G->G->argv);
	exit(0);
}
