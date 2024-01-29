//Reformat raw output from psql into a nice database status display
//See: ./dbctl stat
int main() {
	string data = Stdio.stdin->read();
	sscanf(data, "%s\n%s\n%s", string readonly, string replpid, string clients);
	int ro = readonly == "on";
	write("* Database is %s\n", ro ? "\e[1;34mread-only\e[0m" : "\e[1;32mread/write\e[0m");
	write("* Incoming replication %sactive\e[0m\n", (int)replpid ? "" : "\e[34min");
	foreach (clients / "\n", string cli) {
		if (cli == "") continue;
		[string client_addr, string application_name, string xact_start, string state] = cli / "|";
		string lbl = ([
			"multihome": "Outgoing replication",
			"stillebot": ro ? "\e[1;31m!! Active bot !!\e[0m" : "Active bot",
			"stillebot-ro": "Read-only bot",
			"stillebot-stat": "Gathering stats",
		])[application_name] || application_name;
		write("%14s %s [%s] %s\n", client_addr, lbl, state, xact_start);
	}
}
