int main() {
	object sql = Sql.Sql("pgsql://rosuav@sikorsky.rosuav.com/rosuav", ([
		"use_ssl": 1, "force_ssl": 1,
		"sslcert": "certificate.pem", "sslkey": "privkey.pem",
		"sslrootcert": "/etc/ssl/certs/ISRG_Root_X1.pem",
	]));
	werror("Query result: %O\n", sql->big_query("table asdf"));
}
