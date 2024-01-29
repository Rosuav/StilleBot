//Build code into this file to be able to quickly and easily run it using "stillebot --test"
inherit annotated;

int last_activity = time();
int cur_category;
mapping cfgtest = ([]);
continue Concurrent.Future ping() {
	yield((mixed)reconnect(1));
	werror("Active: %s\n", G->G->database->active || "None!");
	for (;;yield(task_sleep(10))) {
		if (mixed ex = catch {
			mapping ret = yield(G->G->database->generic_query("select * from stillebot.user_followed_categories where twitchid = 1"))[0];
			werror("[%d] Current value: %O\n", time() - last_activity, cur_category = ret->category);
			cfgtest = yield((mixed)load_config(0, "testing"));
			werror("Got: %O\n", cfgtest);
		}) werror("[%d] No active connection - cached value is %d.\n%O\n", time() - last_activity, cur_category, ex);
	}
}

void increment() {
	int newval = ++cur_category;
	werror("Updating value to %d and saving.\n", newval);
	save_sql("update stillebot.user_followed_categories set category = :newval where twitchid = 1", (["newval": newval]));
}

void increment2() {
	werror("Updating ID to %d and saving.\n", ++cfgtest->nextid);
	save_config(0, "testing", cfgtest);
}

continue Concurrent.Future get_settings() {
	werror("Settings now: %O\n", G->G->dbsettings);
	mapping settings = yield(G->G->database->generic_query("select * from stillebot.settings"))[0];
	werror("Queried settings: %O\n", settings);
}

continue Concurrent.Future session() {
	mapping session = (["cookie": random(1<<64)->digits(36), "user": "don't you wanna know"]);
	yield(G->G->database->generic_query("insert into stillebot.http_sessions (cookie, data) values (:cookie, :data)",
		(["cookie": session->cookie, "data": encode_value(session)])));
	mapping readback = yield(G->G->database->generic_query("select * from stillebot.http_sessions where cookie = :cookie",
		(["cookie": session->cookie])))[0];
	werror("Queried session: %O\n", readback);
	werror("Decoded session: %O\n", decode_value(readback->data));
}

//Demonstrate if the event loop ever gets stalled out (eg by a blocking operation)
continue Concurrent.Future activity() {
	while (1) {
		yield(task_sleep(60));
		write("%%%% Watchdog %%%% It is now " + ctime(time()));
		last_activity = time();
	}
}

protected void create(string name) {
	::create(name);
	spawn_task(ping());
	spawn_task(activity());
	G->G->consolecmd->inc = increment;
	G->G->consolecmd->inc2 = increment2;
	G->G->consolecmd->settings = lambda() {spawn_task(get_settings());};
	G->G->consolecmd->sess = lambda() {spawn_task(session());};
	G->G->consolecmd->quit = lambda() {exit(0);};
}
