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
		"cookie varchar primary key",
		"active timestamp with time zone default now()",
		"data bytea not null",
	}),
]);

//NOTE: Despite this retention, actual connections are not currently retained across code
//reloads - the old connections will be disposed of and fresh ones acquired. There may be
//some sort of reference loop - it seems that we're not disposing of old versions of this
//module properly - but the connections themselves should be closed by the new module.
@retain: mapping(string:mapping(string:mixed)) connections = ([]);
string active; //Host name only, not the connection object itself
@retain: mapping waiting_for_active = ([ //If active is null, use these to defer database requests.
	"queue": ({ }), //Add a Promise to this to be told when there's an active.
	"saveme": ({ }), //These will be asynchronously saved as soon as there's an active.
]);
array(string) database_ips = ({"sikorsky.rosuav.com", "ipv4.rosuav.com"});

//ALL queries should go through this function.
//Is it more efficient, with queries where we don't care about the result, to avoid calling get()?
//Conversely, does failing to call get() result in risk of problems?
continue Concurrent.Future query(mapping(string:mixed) db, string query, mapping|void bindings) {
	object pending = db->pending;
	object completion = db->pending = Concurrent.Promise();
	if (pending) yield(pending->future()); //If there's a queue, put us at the end of it.
	mixed ret;
	mixed ex = catch {ret = yield(db->conn->promise_query(query, bindings))->get();};
	completion->success(1);
	if (db->pending == completion) db->pending = 0;
	if (ex) throw(ex);
	return ret;
}

continue Concurrent.Future _got_active(mapping db) {
	//Pull all the pendings and reset the array before actually saving any of them.
	array wfa = waiting_for_active->saveme; waiting_for_active->saveme = ({ });
	foreach (wfa, [string sql, mapping bindings]) {
		mixed err = catch {yield((mixed)query(db, sql, bindings));};
		if (err) werror("Unable to save pending to database!\n%s\n", describe_backtrace(err));
	}
}
void _have_active(string a) {
	if (G->G->DB != this) return; //Let the current version of the code handle them
	werror("*** HAVE ACTIVE: %O\n", a);
	active = a;
	array wa = waiting_for_active->queue; waiting_for_active->queue = ({ });
	wa->success(active);
	spawn_task(_got_active(connections[active]));
}
Concurrent.Future await_active() {
	Concurrent.Promise pending = Concurrent.Promise();
	waiting_for_active->queue += ({pending});
	return pending->future();
}

class SSLContext {
	inherit SSL.Context;
	array|zero find_cert_issuer(array(string) ders) {
		if (sizeof(cert_chains_issuer)) return values(cert_chains_issuer)[0]; //Return the first available cert
		return ::find_cert_issuer(ders);
	}
}

void notify_readonly(int pid, string cond, string extra, string host) {
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
	werror("[%s] Unknown notification %O from pid %O, extra %O\n", host, cond, pid, extra);
}

continue Concurrent.Future fetch_settings(mapping db) {
	G->G->dbsettings = yield((mixed)query(db, "select * from stillebot.settings"))[0];
	werror("Got settings %O\n", G->G->dbsettings);
}

void notify_settings_change(int pid, string cond, string extra, string host) {
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
	while (1) {
		//Establishing the connection is synchronous, might not be ideal.
		db->conn = Sql.Sql("pgsql://rosuav@" + host + "/stillebot", ([
			"force_ssl": 1, "ssl_context": ctx, "application_name": "stillebot",
		]));
		db->conn->set_notify_callback("readonly", notify_readonly, 0, host);
		db->conn->set_notify_callback("stillebot.settings", notify_settings_change, 0, host);
		db->conn->set_notify_callback("", notify_unknown, 0, host);
		//Sometimes, the connection fails, but we only notice it here at this point when the
		//first query goes through. It won't necessarily even FAIL fail, it just stalls here.
		//So we limit how long this can take. When working locally, it takes about 100ms or
		//so; talking to a remote server, a couple of seconds. If it's been ten seconds, IMO
		//there must be a problem.
		mixed ex = catch {yield(db->conn->promise_query("listen readonly")->timeout(10));};
		if (ex) {
			werror("Timeout connecting to %s, retrying...\n", host);
			continue;
		}
		break;
	}
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

continue Concurrent.Future|zero reconnect(int force) {
	if (force) {
		foreach (connections; string host; mapping db) {
			if (!db->connected) {werror("Still connecting to %s...\n", host); continue;} //Will probably need a timeout somewhere
			werror("Closing connection to %s.\n", host);
			db->conn->close();
			destruct(db->conn);
		}
		m_delete(connections, indices(connections)[*]); //Mutate the existing mapping so all clones of the module see that there are no connections
	}
	foreach (database_ips, string host) {
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
	waiting_for_active->saveme += ({({sql, bindings})});
	return "retry";
}

void save_sql(string query, mapping|void bindings) {
	spawn_task(save_to_db(query, bindings));
}

void save_config(string|int twitchid, string kwd, mixed data) {
	data = Standards.JSON.encode(data, 4);
	spawn_task(save_to_db("insert into stillebot.config values (:twitchid, :kwd, :data) on conflict (twitchid, keyword) do update set data=:data",
		(["twitchid": (int)twitchid, "kwd": kwd, "data": data])));
}

continue Concurrent.Future|mapping load_config(string|int twitchid, string kwd) {
	//NOTE: If there's no database connection, this will block. For higher speed
	//queries, do we need a try_load_config() that would error out (or return null)?
	if (!active) yield(await_active());
	array rows = yield((mixed)query(connections[active], "select data from stillebot.config where twitchid = :twitchid and keyword = :kwd",
		(["twitchid": (int)twitchid, "kwd": kwd])));
	if (!sizeof(rows)) return ([]);
	return Standards.JSON.decode_utf8(rows[0]->data);
}

//NOTE: In the future, this MAY be changed to require that data be JSON-compatible.
//The mapping MUST include a 'cookie' which is a short string.
void save_session(mapping data) {
	if (!stringp(data->cookie)) return;
	spawn_task(save_to_db("insert into stillebot.http_sessions (cookie, data) values (:cookie, :data) on conflict (cookie) do update set data=:data, active = now()",
		(["cookie": data->cookie, "data": encode_value(data)])));
}

continue Concurrent.Future|mapping load_session(string cookie) {
	if (!active) yield(await_active());
	array rows = yield((mixed)query(connections[active], "select data from stillebot.http_sessions where cookie = :cookie",
		(["cookie": cookie])));
	if (!sizeof(rows)) return (["cookie": cookie]);
	return decode_value(rows[0]->data);
}

//Generate a new session cookie that definitely doesn't exist
continue Concurrent.Future|string generate_session_cookie() {
	if (!active) yield(await_active());
	while (1) {
		string cookie = random(1<<64)->digits(36);
		mixed ex = catch {yield((mixed)query(connections[active], "insert into stillebot.http_sessions (cookie) values(:cookie)",
			(["cookie": cookie])));};
		if (!ex) return cookie;
		//TODO: If it wasn't a PK conflict, let the exception bubble up
	}
}

//Generic SQL query on the current database. Not recommended; definitely not recommended for
//any mutation; use the proper load_config/save_config/save_sql instead. This is deliberately
//NOT exported, so to use it, write yield((mixed)G->G->DB->generic_query("...")) - clunky as a
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
	//For testing, force the opposite connection order
	if (has_value(G->G->argv, "--gideondb")) database_ips = ({"ipv4.rosuav.com", "sikorsky.rosuav.com"});
	G->G->DB = this;
	spawn_task(reconnect(1));
}
