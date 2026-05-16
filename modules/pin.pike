//This is a bit hard to explain, but it can be used in two ways
//Either pass it a message ID and (optional) duration, and that message will get pinned;
//or leave the message ID blank and have a message inside the builtin, which will then
//be sent and pinned. Note that sending multiple chat messages will probably break things,
//but you can have anything else in there.
//Duration is an integer seconds, or the strings "stream" or "unpin" for till EOS or no pin.
//NOTE: Due to a quirk of message ID capture, the message inside the builtin needs to be
//sent via the API, not legacy IRC chat.
inherit builtin_command;

constant builtin_description = "Manage pinned messages";
constant builtin_name = "Pin Message";
constant builtin_param = ({"Message ID", "Duration"});
constant vars_provided = ([]);

void pin(object channel, string|int mod, string msgid, string|int duration) {
	string method = "PUT";
	if (duration == "unpin") {
		duration = "";
		method = "DELETE";
	}
	else if (duration == "stream") duration = ""; //Omitting the duration will pin till end of stream
	else duration = "&duration_seconds=" + (int)duration;
	twitch_api_request("https://api.twitch.tv/helix/chat/pins?broadcaster_id=" + channel->userid
		+ "&moderator_id=" + mod + "&message_id=" + msgid + duration,
		(["Authorization": (int)mod]), (["method": method]),
	);
}

__async__ mapping message_params(object channel, mapping person, array param, mapping cfg) {
	//FIXME: Need to know which voice triggered the builtin, which would be the moderator.
	//This should not be duplicated like this.
	string|zero voice = (cfg->voice && cfg->voice != "") ? cfg->voice : channel->config->defvoice;
	if (!G->G->DB->load_cached_config(channel->userid, "voices")[voice]) voice = 0;
	if (!voice) voice = G->G->irc->id[0]->?config->?defvoice;
	//End duplication from connection.pike
	if (!voice) voice = channel->userid;
	if (param[0] == "")
		cfg->callback = lambda(mapping vars, mapping result) {pin(channel, voice, result->message_id, param[1]);};
	else
		pin(channel, voice, param[0], param[1]);
	return ([]);
}
