inherit http_endpoint;
inherit annotated;
inherit builtin_command;

constant markdown = "# Emote grid\n\n<div id=grid></div>";

@retain: mapping built_emotes = ([]);
@retain: mapping global_emotes = ([]);
@retain: mapping emotes_by_id = ([]); //Map an emote ID to an Image.ANY._decode mapping

continue array|Concurrent.Future fetch_global_emotes() {
	if (global_emotes->fetchtime < time() - 3600) {
		mapping info = yield(twitch_api_request("https://api.twitch.tv/helix/chat/emotes/global"));
		global_emotes->fetchtime = time();
		global_emotes->emotes = info->data;
		global_emotes->template = info->template;
	}
	return global_emotes->emotes;
}

continue mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req) {
	mapping info = built_emotes[req->variables->code];
	if (!info) return 0; //TODO: Better page
	if (!global_emotes->template) {
		//Ensure that we at least have the template. It's not going to change often,
		//so I actually don't care about the precise fetch time.
		mixed _ = yield(fetch_global_emotes());
	}
	return render_template(markdown, ([
		"vars": (["emotedata": info, "emote_template": global_emotes->template]),
		"js": "emotegrid",
	]));
}

continue string|Concurrent.Future fetch_emote(string emoteid) {
	return yield(Protocols.HTTP.Promise.get_url(replace(global_emotes->template, ([
		"{{id}}": emoteid,
		"{{format}}": "static",
		"{{theme_mode}}": "light",
		"{{scale}}": "3.0",
	]))))->get();
}

mapping parse_emote(string imgdata) {
	mapping emote = Image.ANY._decode(imgdata);
	if (!emote->alpha) emote->alpha = Image.Image(emote->xsize, emote->ysize, 255, 255, 255); //Assume full opacity
	emote->image_hsv = emote->image->rgb_to_hsv();
	emote->alpha_hsv = emote->alpha->rgb_to_hsv();
	return emote;
}

continue mapping|Concurrent.Future fetch_all_emotes(array(string) emoteids) {
	mapping emotes_raw = ([]); //Unnecessary once testing is done
	catch {emotes_raw = decode_value(Stdio.read_file("emotedata.cache"));};
	foreach (emoteids, string id) if (!emotes_by_id[id]) {
		if (!emotes_raw[id]) emotes_raw[id] = yield(fetch_emote(id));
		emotes_by_id[id] = parse_emote(emotes_raw[id]);
	}
	Stdio.write_file("emotedata.cache", encode_value(emotes_raw));
	return emotes_by_id;
}

string find_nearest(int h, int s, int v, array(string) emotes) {
	//TODO!
}

continue string|Concurrent.Future make_emote(string emoteid, string|void channel) {
	string code = sprintf("%024x", random(1<<96)); //TODO: check for collisions
	mapping info = built_emotes[code] = (["emoteid": emoteid, "channel": channel || ""]);
	array emotes = yield(fetch_global_emotes())->id;
	if (channel && channel != "") {
		channel = (string)yield(get_user_id(channel));
		emotes += yield(get_helix_paginated("https://api.twitch.tv/helix/chat/emotes", (["broadcaster_id": channel])))->id;
	}
	//Step 1: Fetch the emote we're building from.
	string imgdata = yield(fetch_emote(emoteid));
	mapping basis = parse_emote(imgdata);
	//Note that we won't use the alpha channel in determining the emote to use for a pixel.
	//Instead, AFTER selecting an emote (which might be meaningless if the pixel is fully
	//transparent), we apply the same transparency to the entire emote. This should have the
	//correct effect, albeit with some unnecessary work in some cases. The only exception is
	//completely transparent pixels (alpha == 0), for which the work would be a complete and
	//utter waste, so we just pick the first emote on the list.
	mixed _ = yield(fetch_all_emotes(emotes));
	for (int y = 0; y < basis->ysize; ++y) for (int x = 0; x < basis->xsize; ++x) {
		//For the alpha channel, we don't care about hue or saturation.
		int alpha = basis->alpha_hsv->getpixel(x, y)[2];
		string pixel;
		if (!alpha) pixel = emotes[0];
		else pixel = find_nearest(@basis->image_hsv->getpixel(x, y), emotes);
	}
	return code;
}

constant builtin_name = "Emote grid";
constant builtin_param = ({"Emote", "Channel name"});
constant vars_provided = ([
	"{error}": "Error message, if any",
	"{code}": "Unique code for the generated grid",
	"{url}": "Web address where the grid can be viewed",
]);

continue mapping|Concurrent.Future message_params(object channel, mapping person, string|array param) {
	//PROBLEM: Channel point redemptions don't actually include emote data. So having this
	//as a points reward is actually problematic.
	if (!person->emotes) return (["{error}": "Unfortunately this doesn't work as a channel point redemption (currently)."]);
	if (!sizeof(person->emotes)) return (["{error}": "Please include an emote to build a grid of."]);
	if (stringp(param)) param /= " ";
	string channame = sizeof(param) > 1 && param[1]; //TODO: Support "channelname emoteGoesHere" as well
	string code = yield(make_emote(person->emotes[0][0], channame));
	return (["{code}": code, "{url}": sprintf("%s/emotegrid?code=%s",
		persist_config["ircsettings"]->http_address || "http://BOT_ADDRESS",
		code,
	)]);
}

protected void create(string name) {::create(name);}
