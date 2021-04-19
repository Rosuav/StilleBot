inherit builtin_command;
constant hidden_command = 1;
constant require_moderator = 1;

constant default_response = ([
	"conditional": "string", "expr1": "qualities",
	"message": "@$$: View this stream in glorious {resolution}!",
	"otherwise": "@$$: View this stream in glorious {resolution}! Or any of its other resolutions: {qualities}",
]);

constant altfmt = ([
	"conditional": "number", "expr1": "{uptime} > 600",
	"message": "<temp test hack, will be silent>",
	"otherwise": ([
		"conditional": "string", "expr1": "qualities",
		"message": "Welcome to the stream! View this stream in glorious {resolution}!",
		"otherwise": "Welcome to the stream! View this stream in glorious {resolution}! Or any of its other resolutions: {qualities}",
	]),
]);

continue Concurrent.Future|mapping message_params(object channel, mapping person, string param) {
	mapping videoinfo = yield(get_video_info(channel->name[1..]));
	mapping res = videoinfo->resolutions;
	if (!res || !sizeof(res)) return ([]); //Shouldn't happen
	//Would it be better to just use time() instead? LUL
	int uptime = Calendar.parse("%Y-%M-%DT%h:%m:%s%z", videoinfo->created_at)->distance(Calendar.now())->how_many(Calendar.Second());
	write("Pinging transcoding status for %s, uptime %ds\n", videoinfo->channel->name, uptime);
	string resolution = m_delete(res, "chunked") || "?? unknown res ??"; //Not sure if "chunked" can ever be missing
	string qualities = "";
	array text = values(res), num = -((array(int))text)[*];
	sort(num, text); //Sort by the intifications, descending
	return ([
		"{resolution}": resolution,
		"{qualities}": text * ", ",
		"{uptime}": (string)uptime,
	]);
}

//TODO: Replace this with a channel-online special that calls on !transcoding
int connected(string channel)
{
	if (persist_config["channels"][channel]->reporttrans)
		process(G->G->irc->channels["#" + channel], (["outputfmt": altfmt]), "");
}

protected void create(string name)
{
	register_hook("channel-online", connected);
	::create(name);
}
