mapping irc = Standards.JSON.decode_utf8(Stdio.read_file("twitchbot_config.json"))["ircsettings"] || ([]);
mapping headers = (["Authorization": replace(irc["pass"], "oauth:", "OAuth "), "Client-ID": irc["clientid"]]);
string channel = "rosuav";

void poll()
{
	call_out(poll, 3);
	write("Polling... %d open files\n", sizeof(get_dir("/proc/self/fd")));
	Protocols.HTTP.Promise.get_url("https://api.twitch.tv/helix/streams?user_login=" + channel,
		Protocols.HTTP.Promise.Arguments((["headers": headers])))
		->on_success(lambda(Protocols.HTTP.Promise.Result res) {
			mixed raw = Standards.JSON.decode_utf8(res->get());
			if (!sizeof(raw->data)) write("** Channel %s is offline **\n", channel);
			else write("** Channel %s went online at %s **\n", channel, raw->data[0]->started_at);
		});
}

int main() {write("My PID is: %d\n", getpid()); poll(); return -1;}
