//Build code into this file to be able to quickly and easily run it using "stillebot --test"
inherit annotated;

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

protected void create(string name) {
	::create(name);
	spawn_task(ping());
}
