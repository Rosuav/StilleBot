//Calculate off a full matrix of timings for a given origin
//Run this on every available origin to show the timings.
__async__ int main() {
	string origin = gethostname() || "?";
	write("%-8s | %-8s | %-8s | Time  | Time  | Time\n", "Origin", "Bot", "Database");
	foreach (({"sikorsky", "gideon"}), string host) {
		Protocols.HTTP.Promise.Result res = await(Protocols.HTTP.Promise.get_url(sprintf("https://%s.mustardmine.com/serverstatus?which", host)));
		mapping data = Standards.JSON.decode_utf8(res->get());
		sscanf(data->responder, "%s.", string bot);
		sscanf(data->db_fast, "%s.", string fastdb);
		sscanf(data->db_live, "%s.", string livedb);
		foreach (({"pingro", "pingrw"}), string endpoint) { //Add more if needed
			string url = sprintf("https://%s.mustardmine.com/%s", host, endpoint);
			write("%-8s | %-8s | %-8s", origin, bot, endpoint == "pingro" ? fastdb : livedb);
			for (int i = 0; i < 3; ++i) {
				System.Timer tm = System.Timer();
				await(Protocols.HTTP.Promise.get_url(url));
				write(" | %.3f", tm->peek());
			}
			write("\n");
		}
	}
}
