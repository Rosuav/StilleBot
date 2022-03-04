#if 0
//Currently utterly and totally broken. If ever this can be revived, maybe it's worth looking into.
inherit builtin_command;
constant featurename = "info";
constant hidden_command = 1;
constant require_moderator = 1;

constant command_description = "Report on which video resolutions (quality options) the stream is available in";
constant builtin_description = "Query the video resolutions (quality options) the stream is available in";
constant builtin_name = "Transcoding";
constant default_response = ([
	"conditional": "string", "expr1": "qualities",
	"message": "@$$: View this stream in glorious {resolution}!",
	"otherwise": "@$$: View this stream in glorious {resolution}! Or any of its other resolutions: {qualities}",
]);
constant vars_provided = ([
	"{resolution}": "Source resolution eg 1920x1080",
	"{qualities}": "Comma-separated list of additional qualities - if blank, no transcoding",
	"{uptime}": "Time the channel's been online (deprecated)",
]);

continue Concurrent.Future|mapping message_params(object channel, mapping person, string param) {
	mapping videoinfo = yield(G->G->external_api_lookups->get_video_info(channel->name[1..]));
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
#endif
