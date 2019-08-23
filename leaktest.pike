mapping irc = Standards.JSON.decode_utf8(Stdio.read_file("twitchbot_config.json"))["ircsettings"] || ([]);

array channels = "rosuav silentlilac stephenangelico" / " ";

Concurrent.Future request(Protocols.HTTP.Session.URL url, mapping|void headers)
{
	headers = (headers || ([])) + ([]);
	sscanf(irc["pass"] || "", "oauth:%s", string pass);
	headers["Authorization"] = "OAuth " + pass;
	headers["Client-ID"] = irc["clientid"];
	return Protocols.HTTP.Promise.get_url(url, Protocols.HTTP.Promise.Arguments((["headers": headers])))
		->then(lambda(Protocols.HTTP.Promise.Result res) {
			mixed data = Standards.JSON.decode_utf8(res->get());
			if (!mappingp(data)) return Concurrent.reject(({"Unparseable response\n", backtrace()}));
			if (data->error) return Concurrent.reject(({sprintf("%s\nError from Twitch: %O (%O)\n", url, data->error, data->status), backtrace()}));
			return data;
		});
}

Concurrent.Future get_helix_paginated(string url, mapping|void query, mapping|void headers)
{
	array data = ({ });
	Standards.URI uri = Standards.URI(url);
	query = (query || ([])) + ([]);
	//NOTE: uri->set_query_variables() doesn't correctly encode query data.
	uri->query = Protocols.HTTP.http_encode_query(query);
	return request(uri, headers)->then(lambda(mapping raw) {return raw->data;});
}

void streaminfo(array data)
{
	//First, quickly remap the array into a lookup mapping
	//This helps us ensure that we look up those we care about, and no others.
	mapping chaninfo = ([]);
	foreach (data, mapping chan) chaninfo[lower_case(chan->user_name)] = chan; //TODO: Figure out if user_name is login or display name
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
	get_helix_paginated("https://api.twitch.tv/helix/streams", (["user_login": channels]))
		->on_success(streaminfo);
}

int main(int argc, array(string) argv)
{
	write("My PID is: %d\n", getpid());
	poll();
	return -1;
}
