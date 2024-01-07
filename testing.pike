//Build code into this file to be able to quickly and easily run it using "stillebot --test"
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
]);

mapping(string:mapping(string:mixed)) connections = ([]);
string active; //Host name only, not the connection object itself

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
		if (active == host) active = 0;
	} else if (extra == "off" && db->readonly) {
		werror("SWITCHING TO READ-WRITE MODE: %O\n", host);
		db->conn->query(#"select set_config('application_name', 'stillebot', false),
				set_config('default_transaction_read_only', 'off', false)");
		db->readonly = 0;
		if (!active) active = host;
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
		connections = ([]); //TODO: Ensure that it's okay to rebind like this, otherwise empty the existing mapping instead
	}
	foreach (({"sikorsky.rosuav.com", "ipv4.rosuav.com"}), string host) {
		if (!connections[host]) yield((mixed)connect(host));
		if (!connections[host]->readonly) {active = host; return 0;}
	}
	werror("No active DB, suspending saves\n");
	active = 0;
}

continue Concurrent.Future ping() {
	yield((mixed)reconnect(1));
	werror("Active: %s\n", active || "None!");
	while (1) {
		yield(task_sleep(10));
		if (!active) {
			yield((mixed)reconnect(0));
			if (!active) {werror("No active connection.\n"); continue;}
		}
		werror("Query: %O\n", yield(connections[active]->conn->promise_query("select * from stillebot.user_followed_categories limit 1"))->get()[0]);
	}
}

continue Concurrent.Future increment() {
	werror("Increment unimplemented\n"); //stub
}

//Attempt to create all tables and alter them as needed to have all columns
continue Concurrent.Future create_tables() {
	yield((mixed)reconnect(0)); //Ensure that we have at least one connection
	array(object) dbs;
	if (active) {
		//We can't make changes, but can verify and report inconsistencies.
		dbs = ({connections[active]->conn});
	} else if (!sizeof(connections)) {
		//No connections, nothing succeeded
		error("Unable to verify database status, no PostgreSQL connections\n");
	} else {
		//Update all databases. This is what we normally want.
		dbs = values(connections)->conn;
	}
	foreach (dbs, object db) {
		array cols = yield(db->promise_query("select table_name, column_name from information_schema.columns where table_schema = 'stillebot' order by table_name, ordinal_position"))->get();
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
		}
		if (sizeof(stmts)) {
			if (active) error("Table structure changes needed!\n%O\n", stmts);
			werror("Making changes: %O\n", stmts);
			yield(db->promise_query("begin read write"));
			foreach (stmts, string stmt) yield(db->promise_query(stmt));
			yield(db->promise_query("commit"));
		}
	}
}

continue Concurrent.Future create_tables_and_stop() {
	yield((mixed)create_tables());
	exit(0);
}

protected void create(string name) {
	::create(name);
	if (has_value(G->G->argv, "--update")) {
		spawn_task(create_tables_and_stop());
		return;
	}
	spawn_task(ping());
	G->G->consolecmd->inc = lambda() {spawn_task(increment());};
	G->G->consolecmd->quit = lambda() {exit(0);};
}
