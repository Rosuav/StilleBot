//Build code into this file to be able to quickly and easily run it using "stillebot --test"
inherit annotated;

protected void create(string name) {
	::create(name);
	object eg = G->bootstrap("modules/http/emotegrid.pike");
	spawn_task(eg->make_emote("emotesv2_b49b91624898460c8cc2f27a4e56178c", "rosuav")) //== rosuavEatMe
		{werror("%O\n", G->G->built_emotes[__ARGS__[0]]); exit(0);};
}
