class SSLContext {
	inherit SSL.Context;
	array|zero find_cert_issuer(array(string) ders) {
		if (sizeof(cert_chains_issuer)) return values(cert_chains_issuer)[0]; //Return the first available cert
		return ::find_cert_issuer(ders);
	}
}

int ok = 1;
__async__ void hammer(object sql) {
	//await(sql->promise_query("select 1"));
	//werror("CHANGING BACKEND\n");
	//sql->proxy->c->socket->set_backend(Pike.DefaultBackend);
	for (int i = 0;; ++i) {
		array rows = await(sql->promise_query("select table_schema, table_name, column_name from information_schema.columns order by table_schema, table_name, column_name"))->get();
		werror("[%d] Got %d rows from the promise\n", i, sizeof(rows));
		ok = 1;
	}
}

__async__ void watchdog(object sql) {
	while (1) {
		await(Concurrent.resolve(0)->delay(1));
		if (ok) ok = 0;
		else break;
	}
	werror("\n\nWATCHDOG!\n%O\n\n", sql);
	foreach (Thread.all_threads(), object t)
		if (t != Thread.this_thread()) werror("<< %O >>\n%s\n", t, describe_backtrace(t->backtrace()));
	exit(0);
}

int main() {
	string key = Stdio.read_file("privkey.pem");
	string cert = Stdio.read_file("certificate.pem");
	object ctx = SSLContext();
	array(string) root = Standards.PEM.Messages(Stdio.read_file("/etc/ssl/certs/ISRG_Root_X1.pem"))->get_certificates();
	ctx->add_cert(Standards.PEM.simple_decode(key), Standards.PEM.Messages(cert)->get_certificates() + root);
	object sql = Sql.Sql("pgsql://rosuav@sikorsky.rosuav.com/stillebot", ([
		"force_ssl": 1, "ssl_context": ctx, "application_name": "pgssl-test",
	]));
	hammer(sql);
	watchdog(sql);
	return -1;
}
