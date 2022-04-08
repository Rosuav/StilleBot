//Build code into this file to be able to quickly and easily run it using "stillebot --test"
inherit irc_callback;

protected void create(string name) {
	::create(name);
	call_out(werror, 1, "Testing\n");
	call_out(exit, 1.1, 0);
}
