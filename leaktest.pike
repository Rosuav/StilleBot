mapping irc = Standards.JSON.decode_utf8(Stdio.read_file("twitchbot_config.json"))["ircsettings"] || ([]);

array channels = "rosuav silentlilac stephenangelico" / " ";
mapping headers = ([]);

Concurrent.Future request(Protocols.HTTP.Session.URL url)
{
	return Protocols.HTTP.Promise.get_url(url, Protocols.HTTP.Promise.Arguments((["headers": headers])))
		->then(lambda(Protocols.HTTP.Promise.Result res) {
			mixed data = Standards.JSON.decode_utf8(res->get());
			if (!mappingp(data)) return Concurrent.reject(({"Unparseable response\n", backtrace()}));
			if (data->error) return Concurrent.reject(({sprintf("%s\nError from Twitch: %O (%O)\n", url, data->error, data->status), backtrace()}));
			return data;
		});
}

void streaminfo(mapping raw)
{
	mapping chaninfo = ([]);
	foreach (raw->data, mapping chan) chaninfo[lower_case(chan->user_name)] = chan;
	foreach (channels, string name)
		if (mapping info = chaninfo[name])
			write("** Channel %s went online at %s **\n", name, info->started_at);
		else
			write("** Channel %s isn't online **\n", name);
}

void poll()
{
	call_out(poll, 3);
	write("Polling... %d open files\n", sizeof(get_dir("/proc/self/fd")));
	Standards.URI uri = Standards.URI("https://api.twitch.tv/helix/streams");
	uri->query = Protocols.HTTP.http_encode_query((["user_login": channels]));
	request(uri)->on_success(streaminfo);
}

int main(int argc, array(string) argv)
{
	write("My PID is: %d\n", getpid());
	sscanf(irc["pass"] || "", "oauth:%s", string pass);
	headers["Authorization"] = "OAuth " + pass;
	headers["Client-ID"] = irc["clientid"];
	poll();
	return -1;
}
