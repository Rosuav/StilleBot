void data_available(object q, function cbdata) {cbdata(q->unicode_data());}
void request_ok(object q, function cbdata) {q->async_fetch(data_available, cbdata);}
void request_fail(object q) { } //If a poll request fails, just ignore it and let the next poll pick it up.
void make_request(string url, function cbdata)
{
	Protocols.HTTP.do_async_method("GET",url,0,0,
		Protocols.HTTP.Query()->set_callbacks(request_ok,request_fail,cbdata));
}

void streaminfo(string data)
{
	mapping info = Standards.JSON.decode(data);
	sscanf(info->_links->self, "https://api.twitch.tv/kraken/streams/%s", string name);
	if (!info->stream) m_delete(G->G->stream_online_since, name);
	else G->G->stream_online_since[name] = Calendar.parse("%Y-%M-%DT%h:%m:%s%z", info->stream->created_at);
	//write("%O\n", G->G->stream_online_since);
	//write("%s: %O\n", name, info->stream);
}

void poll()
{
	G->G->poll_call_out = call_out(poll, 60); //TODO: Make the poll interval customizable
	foreach (G->channels, string chan)
		make_request("https://api.twitch.tv/kraken/streams/"+chan[1..], streaminfo);
}

void create()
{
	if (!G->G->stream_online_since) G->G->stream_online_since = ([]);
	remove_call_out(G->G->poll_call_out);
	poll();
}
