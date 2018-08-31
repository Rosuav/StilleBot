inherit command;
constant hidden_command = 1;
constant require_moderator = 1;

void report_transcoding(object videoinfo, string pfx)
{
	if (!videoinfo) return;
	string channel = videoinfo->channel->name;
	mapping res = videoinfo->resolutions;
	if (!res || !sizeof(res)) return; //Shouldn't happen
	string dflt = m_delete(res, "chunked") || "?? unknown res ??"; //Not sure if "chunked" can ever be missing
	string msg = pfx + " View this stream in glorious " + dflt + "!";
	if (sizeof(res))
	{
		array text = values(res), num = -((array(int))text)[*];
		sort(num, text); //Sort by the intifications, descending
		msg += " Or any of its other resolutions: " + text * ", ";
	}
	send_message("#" + channel, msg);
}

int connected(string channel)
{
	if (persist["channels"][channel]->reporttrans)
		get_video_info(channel, report_transcoding, "Welcome to the stream!");
}

string process(object channel, object person, string param)
{
	get_video_info(channel->name[1..], report_transcoding, "@" + person->user + ":");
}

void create(string name)
{
	register_hook("channel-online", connected);
	::create(name);
}
