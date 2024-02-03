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

continue Concurrent.Future resolve_command_collision(int twitchid, string cmdname) {
	mixed ex = catch {
		//To resolve this sort of collision, we first mark ALL conflicting commands
		//as inactive. This should get replication working again.
		mapping each = yield(G->G->DB->for_each_db(#"update stillebot.commands
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
		yield(task_sleep(5));
		spawn_task(G->G->DB->generic_query("update stillebot.commands set active = true where id = :id",
			(["id": dbs[-1]->id])));
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
	G->G->postgres_log_readable = log_readable;
	if (!G->G->inotify) start_inotify();
}
