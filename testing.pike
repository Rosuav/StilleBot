//Build code into this file to be able to quickly and easily run it using "stillebot --test"
inherit annotated;

protected void create(string name) {
	::create(name);
	object eg = G->bootstrap("modules/http/emotegrid.pike");
	string rosuavEatMe = "emotesv2_b49b91624898460c8cc2f27a4e56178c";
	string rosuavLove = "390023";
	string rosuavAlice = "300031353";
	string devicatTrain1 = "emotesv2_60160470cdc943ecb7521329d4874419";
	spawn_task(eg->make_emote(rosuavEatMe, "rosuav")) {
		Stdio.write_file("emotegrid.json", Standards.JSON.encode(G->G->built_emotes[__ARGS__[0]]));
		exit(0);
	};
}
