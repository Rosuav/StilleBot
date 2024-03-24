//Build code into this file to be able to quickly and easily run it using "stillebot --test"
inherit annotated;

int last_activity = time();
int cur_category;
mapping cfgtest = ([]);
__async__ void ping() {
	await(G->G->DB->reconnect(1));
	werror("Active: %s\n", G->G->DB->active || "None!");
	for (;;await(task_sleep(10))) await(G->G->run_test());
}

__async__ void run_test() {
	if (mixed ex = catch {
		mapping ret = await(G->G->DB->generic_query("select * from stillebot.user_followed_categories where twitchid = 1"))[0];
		werror("[%d] Current value: %O\n", time() - last_activity, cur_category = ret->category);
		cfgtest = await(G->G->DB->load_config(0, "testing"));
		werror("Got: %O\n", cfgtest);
	}) werror("[%d] No active connection - cached value is %d.\n%O\n", time() - last_activity, cur_category, ex);
}

void increment() {
	int newval = ++cur_category;
	werror("Updating value to %d and saving.\n", newval);
	G->G->DB->save_sql("update stillebot.user_followed_categories set category = :newval where twitchid = 1", (["newval": newval]));
}

__async__ void increment2() {
	cfgtest = await(G->G->DB->load_config(0, "testing"));
	werror("Updating ID to %d and saving.\n", ++cfgtest->nextid);
	G->G->DB->save_config(0, "testing", cfgtest);
}

__async__ void get_settings() {
	werror("Settings now: %O\n", G->G->dbsettings);
	mapping settings = await(G->G->DB->generic_query("select * from stillebot.settings"))[0];
	werror("Queried settings: %O\n", settings);
}

__async__ void session() {
	mapping session = (["cookie": random(1<<64)->digits(36), "user": "don't you wanna know"]);
	G->G->DB->save_session(session);
	mapping readback = await(G->G->DB->load_session(session->cookie));
	werror("Queried session: %O\n", readback);
}

//Demonstrate if the event loop ever gets stalled out (eg by a blocking operation)
__async__ void activity() {
	while (1) {
		await(task_sleep(60));
		write("%%%% Watchdog %%%% It is now " + ctime(time()));
		last_activity = time();
	}
}

@retain: mapping postgres_log_messages = ([]);

//Collision form: Two simultaneous inserts into the commands table.
int(1bit) handle_command_collision(array(string) errors) {
	int twitchid; string cmdname;
	foreach (errors, string line)
		if (sscanf(line, "DETAIL:  Key (twitchid, cmdname)=(%d, %[^)]) already exists.", twitchid, cmdname)) break;
	if (!twitchid) return 0;
	postgres_log_messages->pause_notifications = 1;
	spawn_task(resolve_command_collision(twitchid, cmdname));
}

__async__ void resolve_command_collision(int twitchid, string cmdname) {
	mixed ex = catch {
		//To resolve this sort of collision, we first mark ALL conflicting commands
		//as inactive. This should get replication working again.
		mapping each = await(G->G->DB->for_each_db(#"update stillebot.commands
			set active = false
			where twitchid = :twitchid and cmdname = :cmdname and active = true
			returning id, created",
			(["twitchid": twitchid, "cmdname": cmdname])));
		//Remap ([host: ({([info...])}), ...]) into ({(["host": host, info...]), ...})
		//array dbs = values(each)[*][0][*] | (["host": indices(each)[*]])[*];
		//Or, since in this case we don't actually care which host it's on:
		array dbs = values(each) * ({ }); //Just flatten them into a simple array.
		sort(dbs->created, dbs);
		//Then, we take the one command that happened the latest, and mark it as active.
		//This can be done on any database and will be replicated out correctly.
		//TODO: Can we wait until replication has indeed happened? For now, just sticking
		//in a nice long delay.
		await(task_sleep(5));
		G->G->DB->generic_query("update stillebot.commands set active = true where id = :id",
			(["id": dbs[-1]->id]));
		Stdio.append_file("postgresql_conflict_resolution.log",
			sprintf("=====\n%sCONFLICT: stillebot.commands\n%O\nResolved.\n",
				ctime(time()), each));
	};
	postgres_log_messages->pause_notifications = 0;
}

void log_readable(string line) {
	if (postgres_log_messages->pause_notifications) return;
	/* Interesting lines:
	%*[-0-9 :.AESDT] [%d] rosuav@stillebot LOG:  starting logical decoding for slot "multihome"
	-- Record the pid, this is the current worker pid
	%*[-0-9 :.AESDT] [%d] ERROR:  duplicate key value violates unique constraint "commands_twitchid_cmdname_idx"
	-- If the PID is the current worker pid, we have a replication failure. The precise error will need
	   specific handling; if it's an unknown error, report loudly (The Kick?).
	%*[-0-9 :.AESDT] [%d] DETAIL:  Key (twitchid, cmdname)=(49497888, fight) already exists.
	-- Further information about the same replication failure, will be important
	%*[-0-9 :.AESDT] [%d] CONTEXT:  processing remote data for replication origin "pg_17593" during message type "INSERT" for replication target relation "stillebot.commands" in transaction 10025, finished at 0/529C778
	%*[-0-9 :.AESDT] [%*d] LOG:  background worker "logical replication worker" (PID %d) exited with exit code 1
	-- This indicates replication failure. Make this the moment to report.
	*/
	//Note: If we get any of the intermediate lines but don't have the worker pid, save them,
	//keyed by pid, and use the closer message to tell us which to retrieve.
	sscanf(line, "%*[-0-9 :.AESDT][%d] %s", int pid, string msg);
	if (!msg) return; //Uninteresting.
	if (msg == "LOG:  starting logical decoding for slot \"multihome\"") {
		werror(">>> PG <<< Worker PID is %d [%O]\n", pid, line);
		G->G->postgres_log_messages = postgres_log_messages = ([]); //No need to retain any old data
		postgres_log_messages->current_worker_pid = pid;
	} else if (sscanf(msg, "LOG:  background worker \"logical replication worker\" (PID %d) exited with exit code %d",
			int workerpid, int exitcode) && exitcode) { //Only report if exitcode parsed and is nonzero
		foreach (postgres_log_messages[workerpid] || ({ }), string line) {
			if (line == "ERROR:  duplicate key value violates unique constraint \"commands_twitchid_cmdname_idx\"")
				if (handle_command_collision(postgres_log_messages[workerpid])) return;
		}
		//If we get here, there was some sort of unknown error. Report loudly.
		//TODO: Fire an audio alert in prod.
		werror(">>> PG <<< Worker PID %d failed\n", workerpid);
		werror("%{%s\n%}", postgres_log_messages[workerpid] || ({ }));
		werror(">>> PG <<< End worker failure\n", workerpid);
	} else if (!postgres_log_messages->current_worker_pid || pid == postgres_log_messages->current_worker_pid) {
		postgres_log_messages[pid] += ({msg});
	}
}

void start_inotify() {
	object inot = G->G->inotify = System.Inotify.Instance();
	inot->set_nonblocking();
	string logfn = "/var/log/postgresql/postgresql-16-main.log";
	Stdio.File log = Stdio.File(logfn);
	log->seek(0, Stdio.SEEK_END);
	log->set_nonblocking();
	string buf = "";
	inot->add_watch(logfn, System.Inotify.IN_MODIFY) {
		[int event, int cookie, string path] = __ARGS__;
		buf += log->read(); //TODO: What if there's too much for a single nonblocking read?
		while (sscanf(buf, "%s\n%s", string line, buf))
			G->G->postgres_log_readable(String.trim(line));
		//Any remaining partial line can be left in buf for next time.
	};
}

__async__ void big_query_test() {
	for (int n = 1000; n < (1<<32); n *= 10) {
		array ret = await(G->G->DB->generic_query(
			"select length(:stuff)",
			(["stuff": "*" * n]),
		));
		write("For n = %d: %O\n", n, ret[0]->length);
	}
	exit(0);
}

__async__ void array_test() {
	//TODO: Come up with a good generic way to encode arrays on the wire protocol
	//The array seems to have an "inner type" (eg type 1007 includes that it's 23,
	//array-of-int4 contains int4) and some dimensions, followed by a series of
	//values, each length-preceded. This would ultimately improve performance of
	//queries such as raidfinder's lookup of raids for all live streamers to/from
	//the one you're raidfinding for; currently each is a separate query.
	if (!G->G->DB->active) await(G->G->DB->await_active());
	/*
	werror("Result: %O\n", await(G->G->DB->generic_query("select '{}'::int[]")));
	werror("Result: %O\n", await(G->G->DB->generic_query("select '{1,2,3}'::int[]")));
	werror("Result: %O\n", await(G->G->DB->generic_query("select string_to_array('1,2,3', ',')")));
	werror("Result: %O\n", await(G->G->DB->generic_query("select '{{{1,2,3,4,5},{3,4,5,6,7}},{{5,6,7,8,9},{7,8,9,0,1}},{{1,3,5,7,9},{2,4,6,8,0}},{{1,4,7,0,2},{3,5,7,9,2}}}'::int[]")));
	werror("Result: %O\n", await(G->G->DB->generic_query("select int4range(10, 20)")));
	werror("Result: %O\n", await(G->G->DB->generic_query("select '{[1,2], (3,10)}'::int4multirange")));
	werror("Result: %O\n", await(G->G->DB->generic_query("select 1.5 a, 0.1 b, 0.2 c, 0.3 d, 0.1 + 0.2 e")));
	werror("Result: %O\n", await(G->G->DB->generic_query("select 1.125::numeric(10, 5) a, 2.25::numeric(10, 5) b, 0.125::numeric(10, 5) c, 4::numeric(10, 5) d, 5::numeric(10, 5) e")));
	werror("Result: %O\n", await(G->G->DB->generic_query("select * from stillebot.config where twitchid = any(:ids)",
		(["ids": ({1, 2, 3})]))));
	werror("Result: %O\n", await(G->G->DB->generic_query("select :ids::int4[]",
		(["ids": ({ })]))));
	werror("Result: %O\n", await(G->G->DB->generic_query("select :ids::int4[]",
		(["ids": ({({1, 2}), ({3, 4}), ({5, 6})})]))));
	werror("Result: %O\n", await(G->G->DB->generic_query("select :ids::int4[]",
		(["ids": ({({1, 2, 3}), ({4, 5, 6})})]))));
	werror("Result: %O\n", await(G->G->DB->generic_query("select :ids::int4[]",
		(["ids": ({({({({({1})})})})})]))));
	*/
	exit(0);
}

__async__ void json_test() {
	if (!G->G->DB->active) await(G->G->DB->await_active());
	werror("Result: %O\n", await(G->G->DB->generic_query("select '[1,2,3]'::json")));
	werror("Result: %O\n", await(G->G->DB->generic_query("select '[1,2,3]'::jsonb as arr, '{\"a\":\"b\"}'::jsonb as obj")));
	exit(0);
}

__async__ void transact_test() {
	await(G->G->DB->mutate_config(1, "test", lambda(mapping data) {
		werror("Mutating!\n");
		data->foo++;
	}));
	if (!G->G->DB->active) await(G->G->DB->await_active());
	await(G->G->DB->pg_connections[G->G->DB->active]->conn->transaction(__async__ lambda(function query) {
		werror("Inside transaction!\n");
		werror("1 + 1 => %O\n", await(query("select 1 + 1")));
		werror("42 => %O\n", await(query("select 42")));
	}));
	werror("Transaction done.\n");
	werror("Double query: %O\n", await(G->G->DB->generic_query(({
		"select 1 + 1", "select 42"
	}))));
	exit(0);
}

__async__ void fix_kofi_name() {
	//TODO: Make an actual UI for this somewhere
	mapping stats = await(G->G->DB->load_config(54212603, "subgiftstats"));
	foreach (stats->allkofi, mapping gift) {
		if (gift->giver->user_id == "email@address.example") {
			gift->giver->user_id = "12345678";
			gift->giver->login = gift->giver->displayname = "some_user_name";
		}
	}
	await(G->G->DB->save_config(54212603, "subgiftstats", stats));
}

/*
1. Get baseline timings
2. Does the existing transaction infrastructure help?
3. Query batching. Pass an array of queries and pipeline the lot. Implicit BEGIN/COMMIT around them.
Batches are all without bindings for simplicity.
*/
__async__ void db_queue() {
	if (!G->G->DB->active) {werror("Waiting for active...\n"); await(G->G->DB->await_active());} //Exclude this from the timings
	object tm = System.Timer();
	werror("[%.3f] Awaiting ten queries...\n", tm->peek());
	for (int i = 0; i < 10; ++i) 
		await(G->G->DB->generic_query("listen channel" + i));
	werror("[%.3f] Awaiting ten more in a batch...\n", tm->peek());
	await(G->G->DB->pg_connections["ipv4.rosuav.com"]->conn->batch(
		"listen channel" + enumerate(10, 1, 10)[*]
	));
	werror("[%.3f] Triggering notifications...\n", tm->peek());
	await(G->G->DB->pg_connections["ipv4.rosuav.com"]->conn->batch(({
		"notify channel9",
		"notify channel10",
		"notify channel11",
	})));
	werror("[%.3f] Waiting one second\n", tm->peek());
	sleep(1);
	exit(0);
}

protected void create(string name) {
	::create(name);
	/*if (!G->G->have_tasks) {
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
	G->G->postgres_log_readable = log_readable;
	if (!G->G->inotify) start_inotify();*/
	//big_query_test();
	//array_test();
	//json_test();
	//transact_test();
	//G->bootstrap("connection.pike")->setup_conduit();
	db_queue();
}
