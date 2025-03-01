//Build code into this file to be able to quickly and easily run it using "stillebot --exec=fn"
inherit annotated;

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
		G->G->DB->query_rw("update stillebot.commands set active = true where id = :id",
			(["id": dbs[-1]->id]));
		Stdio.append_file("postgresql_conflict_resolution.log",
			sprintf("=====\n%sCONFLICT: stillebot.commands\n%O\nResolved.\n",
				ctime(time()), each));
	};
	postgres_log_messages->pause_notifications = 0;
}

//Collision form: Two reports of the same user id / login sighting
int(1bit) handle_sighting_collision(array(string) errors) {
	int twitchid; string login;
	foreach (errors, string line)
		if (sscanf(line, "DETAIL:  Key (twitchid, login)=(%d, %[^)]) already exists.", twitchid, login)) break;
	if (!twitchid) return 0;
	werror("RESOLVING %O %O\n", twitchid, login);
	//We resolve this on the fast DB, but read-write. Maybe this should go inside database.pike?
	G->G->DB->pg_connections[G->G->DB->fastdb]->conn->transaction(__async__ lambda(function query) {
		await(query("delete from stillebot.user_login_sightings where twitchid = :id and login = :login",
			(["id": twitchid, "login": login])));
	});
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
			if (line == "ERROR:  duplicate key value violates unique constraint \"user_login_sightings_pkey\"")
				if (handle_sighting_collision(postgres_log_messages[workerpid])) return;
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

@"Monitor the PostgreSQL log for evidence of conflicts":
int pgmonitor() {
	G->G->postgres_log_readable = log_readable;
	if (!G->G->inotify) start_inotify();
	return -1;
}

@"Fix someone's Ko-fi donation name on the leaderboard":
__async__ void fix_kofi_name() {
	//TODO: Control this with args, don't just hard-code stuff
	mapping stats = await(G->G->DB->load_config(54212603, "subgiftstats"));
	foreach (stats->allkofi, mapping gift) {
		if (gift->giver->user_id == "email@address.example") {
			write("Found %O\n", gift);
			mapping user = await(get_user_info("actualusername", "login"));
			gift->giver->user_id = user->id;
			gift->giver->login = gift->giver->displayname = user->display_name;
		}
	}
	await(G->G->DB->save_config(54212603, "subgiftstats", stats));
}

@"Update the database schema":
Concurrent.Future dbupdate() {return G->G->DB->create_tables();}

@"Look up someone's previous names":
__async__ void lookup() {
	array(string) names = G->G->args[Arg.REST];
	foreach (names, string name) {
		int uid = await(get_user_id(name));
		if (!uid) {write(name + ": Not found\n"); continue;}
		array times = await(G->G->DB->query_ro("select login, min(sighted) from stillebot.user_login_sightings where twitchid = :id group by login order by 2",
			(["id": uid])));
		if (G->G->args->times) foreach (times, mapping t) write("[%s] %s\n", t->sighted, t->login);
		else write(name + ": " + times->login * ", " + "\n");
	}
}

@"Watch a channel for setup changes (currently just cat/title)":
__async__ void watch() {
	array(string) names = G->G->args[Arg.REST];
	if (!sizeof(names)) {werror("Need a username\n"); return;}
	array ids = await(Concurrent.all(get_user_id(names[*])));
	array prev = allocate(sizeof(ids));
	while (1) {
		foreach (ids; int i; int id) {
			mapping data = await(twitch_api_request("https://api.twitch.tv/helix/channels?broadcaster_id=" + id));
			mapping setup = data->data[0];
			string cur = setup->game_name + ": " + setup->title;
			if (cur != prev[i]) {
				write(names[i] + ": " + string_to_utf8(cur) + "\n");
				if (prev[i]) Process.create_process(({"vlc", "/home/rosuav/Music/The Kick-Q3Kvu6Kgp88.webm"}));
				prev[i] = cur;
			}
		}
		sleep(60);
	}
}

@"Test MustardScript parsing and reconstitution":
__async__ void script() {
	//Rather than actually load up all the builtins, just make sure the names can be validated.
	//List is correct as of 20231210.
	constant builtin_names = ({"chan_share", "chan_giveaway", "shoutout", "cmdmgr", "hypetrain", "chan_mpn", "tz", "chan_alertbox", "raidfinder", "uptime", "renamed", "log", "quote", "nowlive", "calc", "chan_monitors", "chan_errors", "argsplit", "chan_pointsrewards", "chan_labels", "uservars"});
	G->G->builtins = mkmapping(builtin_names, allocate(sizeof(builtin_names), 1));
	G->bootstrap("modules/cmdmgr.pike");
	object mustard = G->bootstrap("modules/mustard.pike");
	foreach (G->G->args[Arg.REST], string arg) await(mustard->run_test(arg, G->G->args->q));
}

__async__ void sublist() {
	int uid = (int)await(get_user_id("profoundrice"));
	array subs = await(get_helix_paginated("https://api.twitch.tv/helix/subscriptions",
		(["broadcaster_id": (string)uid]),
		(["Authorization": uid])));
	array follows = await(get_helix_paginated("https://api.twitch.tv/helix/channels/followers",
		(["broadcaster_id": (string)uid]),
		(["Authorization": uid])));
	werror("Total: %d subs, %d followers\n", sizeof(subs), sizeof(follows));
	multiset following = (multiset)follows->user_id;
	array foll = ({ }), nonfoll = ({ });
	foreach (subs, mapping user) {
		if (following[user->user_id]) foll += ({user->user_name});
		else nonfoll += ({user->user_name});
	}
	werror("Search complete. %d following, %d not following.\n", sizeof(foll), sizeof(nonfoll));
	Stdio.write_file("following.txt", string_to_utf8(foll * "\n"));
	Stdio.write_file("notfollowing.txt", string_to_utf8(nonfoll * "\n"));
	following = (multiset)follows->user_login;
	array lines = Stdio.read_file("../Downloads/subscriber-list.csv") / "\n";
	int nfoll, nnotfoll;
	foreach (lines; int i; string l) {
		if (!i) {lines[i] += ",Following"; continue;}
		if (l == "") continue;
		sscanf(l, "%[^,],", string user);
		if (following[user]) {nfoll++; lines[i] += ",true";}
		else {nnotfoll++; lines[i] += ",false";}
	}
	Stdio.write_file("subscriber-list-annotated.csv", lines * "\n");
	write("Foll %d, not foll %d\n", nfoll, nnotfoll);
}

@"This help information":
void help() {
	write("\nUSAGE: pike stillebot --exec=ACTION\nwhere ACTION is one of the following:\n");
	array names = indices(this), annot = annotations(this);
	sort(names, annot);
	foreach (annot; int i; multiset|zero annot)
		foreach (annot || (<>); mixed anno;)
			if (stringp(anno)) write("%-15s: %s\n", names[i], anno);
}

protected void create(string name) {
	::create(name);
	G->G->utils = this;
}
