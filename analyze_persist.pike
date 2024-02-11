int main() {
	mapping persist_status = Standards.JSON.decode_utf8(Stdio.read_file("twitchbot_status.json"));
	int len = max(@sizeof(indices(persist_status)[*]));
	//In order to know what channel names are, we need them all loaded.
	mapping channel = ([]);
	foreach (get_dir("channels"), string fn) catch {
		mapping chan = Standards.JSON.decode_utf8(Stdio.read_file("channels/" + fn));
		channel[(string)chan->userid] = "User ID";
		channel[chan->login] = "Login";
		channel["#" + chan->login] = "#channelname";
		channel[chan->display_name] = "Display Name";
	};
	persist: foreach (sort(indices(persist_status)), string key) {
		mixed data = persist_status[key];
		key = sprintf("%*s", len, key);
		if (!mappingp(data)) {write("%s: %t\n", key, data); continue;}
		foreach (data; string k;) {
			if (channel[k]) {write("%s: %s\n", key, channel[k]); continue persist;}
		}
		write("%s: Unknown/Other [%d entries]\n", key, sizeof(data));
	}
}
