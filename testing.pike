//Build code into this file to be able to quickly and easily run it using "stillebot --test"
inherit annotated;

@retain: mapping demo_retention = ([]);

protected void create(string name) {
	::create(name);
	demo_retention[time()] = "Hello, world";
	werror("Retention: %O\n", demo_retention);
}
