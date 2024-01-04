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

mapping connect(string host) {
	werror("Connecting to Postgres on %O...\n", host);
	mapping db = connections[host] = (["host": host]); //Not a floop, strings are just strings :)
	string key = Stdio.read_file("privkey.pem");
	string cert = Stdio.read_file("certificate.pem");
	object ctx = SSLContext();
	array(string) root = Standards.PEM.Messages(Stdio.read_file("/etc/ssl/certs/ISRG_Root_X1.pem"))->get_certificates();
	ctx->add_cert(Standards.PEM.simple_decode(key), Standards.PEM.Messages(cert)->get_certificates() + root);
	db->conn = Sql.Sql("pgsql://rosuav@" + host + "/stillebot", ([
		"force_ssl": 1, "ssl_context": ctx, "application_name": "stillebot",
	]));
	db->conn->set_notify_callback("readonly", notify_readonly, 0, host);
	db->conn->query("listen readonly");
	string ro = db->conn->query("show default_transaction_read_only")[0]->default_transaction_read_only;
	werror("Connected to %O - %s.\n", host, ro == "on" ? "r/o" : "r-w");
	if (ro == "on") {
		db->conn->query("set application_name = 'stillebot-ro'");
		db->readonly = 1;
	}
}

void reconnect(int force) {
	if (force) {
		foreach (connections; string host; mapping db) {
			werror("Closing connection to %s.\n", host);
			db->conn->close();
			destruct(db->conn);
		}
		connections = ([]); //TODO: Check if it's okay to rebind like this, otherwise empty the existing mapping instead
	}
	foreach (({"sikorsky.rosuav.com", "ipv4.rosuav.com"}), string host) {
		if (!connections[host]) connect(host);
		if (!connections[host]->readonly) {active = host; return;}
	}
	werror("No active DB, suspending saves\n");
	active = 0;
}

void ping() {
	call_out(ping, 10);
	if (!active) {
		reconnect(0);
		if (!active) {werror("No active connection.\n"); return;}
	}
	werror("Query: %O\n", connections[active]->conn->query("select * from stillebot.user_followed_categories limit 1")[0]);
}

protected void create(string name) {
	::create(name);
	reconnect(1);
	werror("Active: %O\n", active || "None!");
	call_out(ping, 10);
}
