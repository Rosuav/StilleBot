//Build code into this file to be able to quickly and easily run it using "stillebot --test"
inherit annotated;

object|zero sikorsky, gideon, active;

class SSLContext {
	inherit SSL.Context;
	array|zero find_cert_issuer(array(string) ders) {
		if (sizeof(cert_chains_issuer)) return values(cert_chains_issuer)[0]; //Return the first available cert
		return ::find_cert_issuer(ders);
	}
}

class DBConnection(string host) {
	Sql.Sql db;
	int readonly;

	void notify_readonly(int pid, string cond, string extra) {
		if (extra == "on" && !readonly) {
			werror("SWITCHING TO READONLY MODE: %O\n", host);
			db->query(#"select set_config('application_name', 'stillebot-ro', false),
					set_config('default_transaction_read_only', 'on', false)");
			readonly = 1;
			if (active && active->host == host) active = 0; //Even if it's not the same object (just in case)
		} else if (extra == "off" && readonly) {
			werror("SWITCHING TO READ-WRITE MODE: %O\n", host);
			db->query(#"select set_config('application_name', 'stillebot', false),
					set_config('default_transaction_read_only', 'off', false)");
			readonly = 0;
			if (!active) active = this;
		}
		//Else we're setting the mode we're already in. This may indicate a minor race
		//condition on startup, but we're already going to be in the right state anyway.
	}

	protected void create() {
		werror("Connecting to Postgres on %O...\n", host);
		string key = Stdio.read_file("privkey.pem");
		string cert = Stdio.read_file("certificate.pem");
		object ctx = SSLContext();
		array(string) root = Standards.PEM.Messages(Stdio.read_file("/etc/ssl/certs/ISRG_Root_X1.pem"))->get_certificates();
		ctx->add_cert(Standards.PEM.simple_decode(key), Standards.PEM.Messages(cert)->get_certificates() + root);
		db = Sql.Sql("pgsql://rosuav@" + host + "/stillebot", ([
			"force_ssl": 1, "ssl_context": ctx, "application_name": "stillebot",
		]));
		db->set_notify_callback("readonly", notify_readonly);
		db->query("listen readonly");
		string ro = db->query("show default_transaction_read_only")[0]->default_transaction_read_only;
		werror("Connected to %O - %s.\n", host, ro == "on" ? "r/o" : "r-w");
		if (ro == "on") {
			db->query("set application_name = 'stillebot-ro'");
			readonly = 1;
		}
	}
}

void reconnect(int force) {
	if (force) {
		foreach (({sikorsky, gideon}), object|zero db) if (db) {
			werror("Closing connection to %s.\n", db->host);
			db->close();
			destruct(db);
		}
		sikorsky = gideon = 0;
	}
	if (!sikorsky) sikorsky = DBConnection("sikorsky.rosuav.com");
	if (sikorsky->readonly) {
		if (!gideon) gideon = DBConnection("ipv4.rosuav.com");
		if (gideon->readonly) {werror("No active DB, suspending saves\n"); active = 0;}
		else active = gideon;
	}
	else active = sikorsky;
}

void ping() {
	call_out(ping, 10);
	if (!active) {
		reconnect(0);
		if (!active) {werror("No active connection.\n"); return;}
	}
	werror("Query: %O\n", active->db->query("select * from stillebot.user_followed_categories limit 1")[0]);
}

protected void create(string name) {
	::create(name);
	reconnect(1);
	werror("Active: %O\n", active && active->host);
	call_out(ping, 10);
}
