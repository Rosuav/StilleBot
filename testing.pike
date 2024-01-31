//Build code into this file to be able to quickly and easily run it using "stillebot --test"
inherit annotated;

int last_activity = time();
int cur_category;
mapping cfgtest = ([]);
continue Concurrent.Future ping() {
	yield((mixed)G->G->DB->reconnect(1));
	werror("Active: %s\n", G->G->DB->active || "None!");
	for (;;yield(task_sleep(10))) yield(G->G->run_test());
}

continue Concurrent.Future run_test() {
	if (mixed ex = catch {
		mapping ret = yield((mixed)G->G->DB->generic_query("select * from stillebot.user_followed_categories where twitchid = 1"))[0];
		werror("[%d] Current value: %O\n", time() - last_activity, cur_category = ret->category);
		cfgtest = yield((mixed)G->G->DB->load_config(0, "testing"));
		werror("Got: %O\n", cfgtest);
	}) werror("[%d] No active connection - cached value is %d.\n%O\n", time() - last_activity, cur_category, ex);
}

void increment() {
	int newval = ++cur_category;
	werror("Updating value to %d and saving.\n", newval);
	G->G->DB->save_sql("update stillebot.user_followed_categories set category = :newval where twitchid = 1", (["newval": newval]));
}

continue Concurrent.Future increment2() {
	cfgtest = yield((mixed)G->G->DB->load_config(0, "testing"));
	werror("Updating ID to %d and saving.\n", ++cfgtest->nextid);
	G->G->DB->save_config(0, "testing", cfgtest);
}

continue Concurrent.Future get_settings() {
	werror("Settings now: %O\n", G->G->dbsettings);
	mapping settings = yield((mixed)G->G->DB->generic_query("select * from stillebot.settings"))[0];
	werror("Queried settings: %O\n", settings);
}

continue Concurrent.Future session() {
	mapping session = (["cookie": random(1<<64)->digits(36), "user": "don't you wanna know"]);
	G->G->DB->save_session(session);
	mapping readback = yield((mixed)G->G->DB->load_session(session->cookie));
	werror("Queried session: %O\n", readback);
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
	if (!G->G->have_tasks) {
		G->G->have_tasks = 1;
		spawn_task(ping());
		spawn_task(activity());
	} else spawn_task(G->G->DB->reconnect(1));
	G->G->consolecmd->inc = increment;
	G->G->consolecmd->inc2 = lambda() {spawn_task(increment2());};
	G->G->consolecmd->settings = lambda() {spawn_task(get_settings());};
	G->G->consolecmd->sess = lambda() {spawn_task(session());};
	G->G->consolecmd->quit = lambda() {exit(0);};
	G->G->run_test = run_test;
}
