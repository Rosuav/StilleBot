//Build code into this file to be able to quickly and easily run it using "stillebot --test"
inherit annotated;
@export: mapping get_channel_config(string|int chan) {error("Channel configuration unavailable.\n");}

protected void create(string name) {
	::create(name);
	object mustard = G->bootstrap("mustard.pike");
	G->G->argv -= ({"--test"});
	mustard->main(sizeof(G->G->argv), G->G->argv);
	exit(0);
}
