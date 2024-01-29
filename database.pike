inherit annotated;

//For each table, we have a set of columns, plus some other info. Any entry
//beginning with a space is included in the CREATE TABLE but will not be added
//subsequently in an ALTER TABLE; any entry ending with a semicolon will also
//be used only on table creation, but will be executed as its own statement in
//the same transaction. Otherwise, any column entry where the first word is not
//found as an existing column will be altered into the table on next check.
//NOTE: We assume that no table will ever exist without columns. I mean, why?!?
//Altering of tables is extremely simplistic and will only ever drop or add a
//column. For more complex changes, devise a system when one becomes needed.
//NOTE: Tables will never be dropped, although columns removed from tables will.
constant tables = ([
	"user_followed_categories": ({
		"twitchid bigint not null",
		"category integer not null",
		" primary key (twitchid, category)",
	}),
	"commands": ({
		"id serial primary key",
		"channel bigint not null",
		"cmdname text not null",
		"active boolean not null",
		"content json not null",
		"created timestamp with time zone not null default now()",
		"create unique index on stillebot.commands (channel, cmdname) where active;",
	}),
	//Generic channel info that stores anything that could be in channels/TWITCHID.json
	//or twitchbot_status.json.
	"config": ({
		"twitchid bigint not null",
		"keyword varchar not null",
		"data json not null",
		" primary key (twitchid, keyword)",
	}),
	//Simple list of the "exportable" configs as stored in stillebot.config above.
	//A user may (when implemented) request their exportable data, as a backup etc.
	//Can be used in an outer join to recognize non-exportable rows.
	"config_exportable": ({
		"keyword varchar primary key",
	}),
	//Single-row table for fundamental bot config. Trust this only if the database is
	//read-write; otherwise, consider it advisory.
	"settings": ({
		"asterisk char primary key", //There's only one row, but give it a PK anyway for the sake of replication.
		"active_bot varchar",
		"insert into stillebot.settings (asterisk) values ('*');",
		//Not tested as part of database recreation, has been done manually.
		//"create or replace function send_settings_notification() returns trigger language plpgsql as $$begin perform pg_notify('stillebot.settings', ''); return null; end$$;",
		//"create trigger settings_update_notify after update on stillebot.settings execute function send_settings_notification();",
	}),
	"http_sessions": ({
		"cookie varchar(14) primary key",
		"active timestamp with time zone default now()",
		"data bytea not null",
	}),
]);

mapping(string:mapping(string:mixed)) connections = ([]);
string active; //Host name only, not the connection object itself

//ALL queries should go through this function.
//Is it more efficient, with queries where we don't care about the result, to avoid calling get()?
//Conversely, does failing to call get() result in risk of problems?
continue Concurrent.Future query(mapping(string:mixed) db, string query, mapping|void bindings) {
	object pending = db->pending;
	object completion = db->pending = Concurrent.Promise();
	if (pending) {werror("... waiting ...\n"); db = yield(pending->future()); werror("Wait done, querying\n");} //If there's a queue, put us at the end of it.
	//The timeout at the moment is crazy long.
	mixed ret;
	while (mixed ex = catch {ret = yield(db->conn->promise_query(query, bindings)->timeout(120))->get();}) {
		if (arrayp(ex) && ex[0] == "Timeout.\n") {
			//TODO: Silently reconnect? For now, just letting this grind until the failure happens.
			werror("Timed out. Ending.\n");
			werror("Connection: %O\n", db->conn->proxy->c);
			foreach (Thread.all_threads(), object t)
				werror("Thread id %d:\n%s\n", t->id_number(), describe_backtrace(t->backtrace()));
			exit(0);
		}
		werror("ERROR IN QUERY:\n%s\n", describe_backtrace(ex));
		object waspending = m_delete(connections, db->host)->pending;
		werror("Reconnecting...\n");
		yield((mixed)reconnect(0));
		werror("Reconnect complete...?\n");
		db = connections[active];
		if (!db) {werror("Unable to reconnect.\n"); error("No database connection\n");}
		werror("Reconnected.\n");
		db->pending = waspending;
	}
	completion->success(db);
	if (db->pending == completion) db->pending = 0;
	return ret;
}

array(array(string|mapping)) waiting_for_active = ({ });
continue Concurrent.Future _got_active(mapping db) {
	//Pull all the pendings and reset the array before actually saving any of them.
	array wfa = waiting_for_active; waiting_for_active = ({ });
	foreach (wfa, [string sql, mapping bindings]) {
		mixed err = catch {yield((mixed)query(db, sql, bindings));};
		if (err) werror("Unable to save pending to database!\n%s\n", describe_backtrace(err));
	}
}
void _have_active(string a) {werror("*** HAVE ACTIVE: %O\n", a); active = a; spawn_task(_got_active(connections[active]));}

class SSLContext {
	inherit SSL.Context;
	array|zero find_cert_issuer(array(string) ders) {
		if (sizeof(cert_chains_issuer)) return values(cert_chains_issuer)[0]; //Return the first available cert
		return ::find_cert_issuer(ders);
	}
}

void notify_readonly(int pid, string cond, string extra, string host) {
	if (function f = bounce(this_function)) {f(pid, cond, extra, host); return;}
	mapping db = connections[host];
	if (extra == "on" && !db->readonly) {
		werror("SWITCHING TO READONLY MODE: %O\n", host);
		db->conn->query(#"select set_config('application_name', 'stillebot-ro', false),
				set_config('default_transaction_read_only', 'on', false)");
		db->readonly = 1;
		if (active == host) {active = 0; spawn_task(reconnect(0));}
	} else if (extra == "off" && db->readonly) {
		werror("SWITCHING TO READ-WRITE MODE: %O\n", host);
		db->conn->query(#"select set_config('application_name', 'stillebot', false),
				set_config('default_transaction_read_only', 'off', false)");
		db->readonly = 0;
		if (!active) _have_active(host);
	}
	//Else we're setting the mode we're already in. This may indicate a minor race
	//condition on startup, but we're already going to be in the right state anyway.
}

void notify_unknown(int pid, string cond, string extra, string host) {
	if (function f = bounce(this_function)) {f(pid, cond, extra, host); return;}
	werror("[%s] Unknown notification %O from pid %O, extra %O\n", host, cond, pid, extra);
}

continue Concurrent.Future fetch_settings(mapping db) {
	G->G->dbsettings = yield((mixed)query(db, "select * from stillebot.settings"))[0];
	werror("Got settings %O\n", G->G->dbsettings);
}

void notify_settings_change(int pid, string cond, string extra, string host) {
	if (function f = bounce(this_function)) {f(pid, cond, extra, host); return;}
	werror("SETTINGS CHANGED\n");
	spawn_task(fetch_settings(connections[host]));
}

continue Concurrent.Future connect(string host) {
	werror("Connecting to Postgres on %O...\n", host);
	mapping db = connections[host] = (["host": host]); //Not a floop, strings are just strings :)
	string key = Stdio.read_file("privkey.pem");
	string cert = Stdio.read_file("certificate.pem");
	object ctx = SSLContext();
	array(string) root = Standards.PEM.Messages(Stdio.read_file("/etc/ssl/certs/ISRG_Root_X1.pem"))->get_certificates();
	ctx->add_cert(Standards.PEM.simple_decode(key), Standards.PEM.Messages(cert)->get_certificates() + root);
	//Establishing the connection is synchronous, might not be ideal.
	db->conn = Sql.Sql("pgsql://rosuav@" + host + "/stillebot", ([
		"force_ssl": 1, "ssl_context": ctx, "application_name": "stillebot",
	]));
	db->conn->set_notify_callback("readonly", notify_readonly, 0, host);
	db->conn->set_notify_callback("stillebot.settings", notify_settings_change, 0, host);
	db->conn->set_notify_callback("", notify_unknown, 0, host);
	yield((mixed)query(db, "listen readonly"));
	yield((mixed)query(db, "listen \"stillebot.settings\""));
	string ro = yield((mixed)query(db, "show default_transaction_read_only"))[0]->default_transaction_read_only;
	werror("Connected to %O - %s.\n", host, ro == "on" ? "r/o" : "r-w");
	if (ro == "on") {
		yield((mixed)query(db, "set application_name = 'stillebot-ro'"));
		db->readonly = 1;
	} else {
		//Any time we have a read-write database connection, update settings.
		//....????? I don't understand why, but if I don't store this in a
		//variable, it results in an error about ?: and void. My best guess is
		//the optimizer has replaced this if/else with a ?: maybe???
		mixed _ = yield((mixed)fetch_settings(db));
	}
	db->connected = 1;
}

@export: continue Concurrent.Future|zero reconnect(int force) {
	if (force) {
		foreach (connections; string host; mapping db) {
			if (!db->connected) {werror("Still connecting to %s...\n", host); continue;} //Will probably need a timeout somewhere
			werror("Closing connection to %s.\n", host);
			db->conn->close();
			destruct(db->conn);
		}
		connections = ([]); //TODO: Ensure that it's okay to rebind like this, otherwise empty the existing mapping instead
	}
	foreach (({"sikorsky.rosuav.com", "ipv4.rosuav.com"}), string host) {
		if (!connections[host]) yield((mixed)connect(host));
		if (!connections[host]->readonly) {_have_active(host); return 0;}
	}
	werror("No active DB, suspending saves\n");
	active = 0;
}

continue Concurrent.Future|string save_to_db(string sql, mapping bindings) {
	if (active) {
		mixed err = catch {yield((mixed)query(connections[active], sql, bindings));};
		if (!err) return "ok"; //All good!
		//Report the error to the console, since the caller isn't hanging around.
		//TODO: If the error is because there's actually no database available,
		//put ourselves in the queue.
		werror("Unable to save to database!\n%s\n", describe_backtrace(err));
		return "fail";
	}
	werror("Save pending! %s\n", sql);
	waiting_for_active += ({({sql, bindings})});
	return "retry";
}

@export: void save_sql(string query, mapping|void bindings) {
	spawn_task(save_to_db(query, bindings));
}

@export: void save_config(string|int twitchid, string kwd, mixed data) {
	data = Standards.JSON.encode(data, 4);
	spawn_task(save_to_db("insert into stillebot.config values (:twitchid, :kwd, :data) on conflict (twitchid, keyword) do update set data=:data",
		(["twitchid": (int)twitchid, "kwd": kwd, "data": data])));
}

@export: continue Concurrent.Future|mapping load_config(string|int twitchid, string kwd) {
	//FIXME: What should happen if there's no DB available? Is it okay to fetch from a read-only database?
	if (!active) error("No database connection, can't load data!\n");
	array rows = yield((mixed)query(connections[active], "select data from stillebot.config where twitchid = :twitchid and keyword = :kwd",
		(["twitchid": (int)twitchid, "kwd": kwd])));
	if (!sizeof(rows)) return ([]);
	return Standards.JSON.decode_utf8(rows[0]->data);
}

//Generic SQL query on the current database. Not recommended; definitely not recommended for
//any mutation; use the proper load_config/save_config/save_sql instead. This is deliberately
//NOT exported, so to use it, write yield(G->G->database->generic_query("...")) - clunky as a
//reminder to avoid doing this where possible.
continue Concurrent.Future|mapping generic_query(string sql, mapping|void bindings) {
	if (!connections[active]) {
		yield((mixed)reconnect(0));
		if (!active) error("No database connection available.\n");
	}
	return yield((mixed)query(connections[active], sql, bindings));
}

//Attempt to create all tables and alter them as needed to have all columns
continue Concurrent.Future create_tables() {
	yield((mixed)reconnect(0)); //Ensure that we have at least one connection
	array(mapping) dbs;
	if (active) {
		//We can't make changes, but can verify and report inconsistencies.
		dbs = ({connections[active]});
	} else if (!sizeof(connections)) {
		//No connections, nothing succeeded
		error("Unable to verify database status, no PostgreSQL connections\n");
	} else {
		//Update all databases. This is what we normally want.
		dbs = values(connections);
	}
	foreach (dbs, mapping db) {
		array cols = yield((mixed)query(db, "select table_name, column_name from information_schema.columns where table_schema = 'stillebot' order by table_name, ordinal_position"));
		array stmts = ({ });
		mapping(string:array(string)) havecols = ([]);
		foreach (cols, mapping col) havecols[col->table_name] += ({col->column_name});
		foreach (tables; string tbname; array cols) {
			if (!havecols[tbname]) {
				//The table doesn't exist. Create it from scratch.
				array extras = filter(cols, has_suffix, ";");
				stmts += ({
					sprintf("create table stillebot.%s (%s)", tbname, (cols - extras) * ", "),
				}) + extras;
				continue;
			}
			//If we have columns that aren't in the table's definition,
			//drop them. If the converse, add them. There is no provision
			//here for altering columns.
			string alter = "";
			multiset sparecols = (multiset)havecols[tbname];
			foreach (cols, string col) {
				if (has_suffix(col, ";") || has_prefix(col, " ")) continue;
				sscanf(col, "%s ", string colname);
				if (sparecols[colname]) sparecols[colname] = 0;
				else alter += ", add " + col;
			}
			//If anything hasn't been removed from havecols, it should be dropped.
			foreach (sparecols; string colname;) alter += ", drop " + colname;
			if (alter != "") stmts += ({"alter table stillebot." + tbname + alter[1..]}); //There'll be a leading comma
			else write("Table %s unchanged\n", tbname);
		}
		if (sizeof(stmts)) {
			if (active) error("Table structure changes needed!\n%O\n", stmts);
			werror("Making changes on %s: %O\n", db->host, stmts);
			yield((mixed)query(db, "begin read write"));
			foreach (stmts, string stmt) yield((mixed)query(db, stmt));
			yield((mixed)query(db, "commit"));
			werror("Be sure to `./dbctl refreshrepl` on both ends!\n");
		}
	}
}

continue Concurrent.Future create_tables_and_stop() {
	yield((mixed)create_tables());
	exit(0);
}

protected void create(string name) {
	::create(name);
	register_bouncer(notify_settings_change);
	register_bouncer(notify_unknown);
	register_bouncer(notify_readonly);
	G->G->database = this;
	#if !constant(INTERACTIVE)
	spawn_task(reconnect(0));
	#endif
}

/* Current problem: connection falling over silently.

It seems to fail in load_config(). Often it's completely silent; other times, the next update
query results in "Invalid number of bindings, expected 1, got 2", which correlates with the
update being:
"update stillebot.user_followed_categories set category = :newval where twitchid = 1"
and the config load being:
"select data from stillebot.config where twitchid = :twitchid and keyword = :kwd"
Which means that what seems to have happened is that the config query is prepared, then the
bindings aren't sent for some reason; and then the update is prepared but that's being
ignored (?? or dropped?? or is erroring out but the error is getting lost??), and the binding
(singular) for the update is being submitted next.

Plan: Wade through pgssl.log. Fracture the file at the watchdog lines. Diff successive minute-long
segments. Figure out which parts are irrelevant and script them away. Then see if the final block,
where the failure happens, actually had some clues prior to that.

This MIGHT now be solved, by the strategy of using synchronous write callbacks inside PG PSQL.
*/

/* Bug notes

Sometimes, connecting doesn't seem to work. Check if it causes the watchdog to stall, or if it
is an asynchronous failure. If the latter, stick a timeout on it and move on.

SQL errors result in retry loops. Why? What's going on? Let SQL errors bubble up. Maybe remove
the timeout or handle timeouts differently?
*/
