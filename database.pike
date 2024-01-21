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
	}),
]);

mapping(string:mapping(string:mixed)) connections = ([]);
string active; //Host name only, not the connection object itself

array(array(string|mapping)) waiting_for_active = ({ });
continue Concurrent.Future _got_active(object conn) {
	//Pull all the pendings and reset the array before actually saving any of them.
	array wfa = waiting_for_active; waiting_for_active = ({ });
	foreach (wfa, [string query, mapping bindings]) {
		mixed err = catch {yield(conn->promise_query(query, bindings));};
		if (err) werror("Unable to save pending to database!\n%s\n", describe_backtrace(err));
	}
}
void _have_active(string a) {active = a; spawn_task(_got_active(connections[active]->conn));}

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
	yield(db->conn->promise_query("listen readonly"));
	string ro = yield(db->conn->promise_query("show default_transaction_read_only"))->get()[0]->default_transaction_read_only;
	werror("Connected to %O - %s.\n", host, ro == "on" ? "r/o" : "r-w");
	if (ro == "on") {
		yield(db->conn->promise_query("set application_name = 'stillebot-ro'"));
		db->readonly = 1;
	} else {
		//Any time we have a read-write database connection, update settings.
		//TODO: Set up an update trigger to NOTIFY, then LISTEN for that, and autoupdate
		//Have this trigger only on the active one?
		G->G->dbsettings = yield(db->conn->promise_query("select * from stillebot.settings"))->get()[0];
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

continue Concurrent.Future|string save_to_db(string query, mapping bindings) {
	if (active) {
		mixed err = catch {yield(connections[active]->conn->promise_query(query, bindings));};
		if (!err) return "ok"; //All good!
		//Report the error to the console, since the caller isn't hanging around.
		//TODO: If the error is because there's actually no database available,
		//put ourselves in the queue.
		werror("Unable to save to database!\n%s\n", describe_backtrace(err));
		return "fail";
	}
	werror("Save pending! %s\n", query);
	waiting_for_active += ({({query, bindings})});
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
	array rows = yield(connections[active]->conn->promise_query("select data from stillebot.config where twitchid = :twitchid and keyword = :kwd",
		(["twitchid": (int)twitchid, "kwd": kwd])))->get();
	if (!sizeof(rows)) return ([]);
	return Standards.JSON.decode_utf8(rows[0]->data);
}

//Generic SQL query on the current database. Not recommended; definitely not recommended for
//any mutation; use the proper load_config/save_config/save_sql instead. This is deliberately
//NOT exported, so to use it, write yield(G->G->database->generic_query("...")) - clunky as a
//reminder to avoid doing this where possible.
continue Concurrent.Future|mapping generic_query(string sql) {
	if (!connections[active]) {
		yield((mixed)reconnect(0));
		if (!active) error("No database connection available.\n");
	}
	return yield(connections[active]->conn->promise_query(sql))->get();
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
		array cols = yield(db->conn->promise_query("select table_name, column_name from information_schema.columns where table_schema = 'stillebot' order by table_name, ordinal_position"))->get();
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
			yield(db->conn->promise_query("begin read write"));
			foreach (stmts, string stmt) yield(db->conn->promise_query(stmt));
			yield(db->conn->promise_query("commit"));
		}
	}
}

continue Concurrent.Future create_tables_and_stop() {
	yield((mixed)create_tables());
	exit(0);
}

protected void create(string name) {
	::create(name);
	G->G->database = this;
	#if !constant(INTERACTIVE)
	spawn_task(reconnect(0));
	#endif
}
