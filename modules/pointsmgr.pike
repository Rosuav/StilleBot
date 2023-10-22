inherit hook;

@create_hook:
constant point_redemption = ({"string chan", "string rewardid", "int(0..1) refund", "mapping data"});

protected void create(string name) {
	::create(name);
	//TODO
}
