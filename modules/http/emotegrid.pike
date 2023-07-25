inherit http_endpoint;
inherit annotated;
inherit builtin_command;

constant markdown = #"# Emote grid

<style>
#emotegrid td {padding: 0;}
</style>

<div id=grid></div>";

/* Need to play around with the idea of "similarity" a lot more.

Idea: Calculate the distance from an emote to every possible R/G/B and find the
nearest colour to that emote. Might be indicative.

(Rather than actually calculate for every 256**3 possible pixel colour, increase
the red until the distance starts worsening, then increase green, etc.)

*/

@retain: mapping built_emotes = ([]);
@retain: mapping global_emotes = ([]);
@retain: mapping emotes_by_id = ([]); //Map an emote ID to an Image.ANY._decode mapping
@retain: mapping emote_pixel_distance_cache = ([]); //Map "%d:%d:%d:%s" H/S/V/emoteid to the calculated distance

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
	if (!req->variables->code) info = Standards.JSON.decode(Stdio.read_file("emotegrid.json"));
	if (!info) return 0; //TODO: Better page
	if (!global_emotes->template) {
		//Ensure that we at least have the template. It's not going to change often,
		//so I actually don't care about the precise fetch time.
		mixed _ = yield(fetch_global_emotes());
	}
	return render_template(markdown, ([
		"vars": ([
			"emotedata": info,
			"emote_template": global_emotes->template,
		]),
		"js": "emotegrid",
	]));
}

continue string|Concurrent.Future fetch_emote(string emoteid, string scale) {
	return yield(Protocols.HTTP.Promise.get_url(replace(global_emotes->template, ([
		"{{id}}": emoteid,
		"{{format}}": "static",
		"{{theme_mode}}": "light",
		"{{scale}}": scale,
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
		if (!emotes_raw[id]) emotes_raw[id] = yield(fetch_emote(id, "1.0"));
		emotes_by_id[id] = parse_emote(emotes_raw[id]);
	}
	Stdio.write_file("emotedata.cache", encode_value(emotes_raw));
	return emotes_by_id;
}

//Count the pixels in the emote that are within MAX_COLOR_DISTANCE
float count_nearby_pixels(int r, int g, int b, string emoteid, float max_dist) {
	string cachekey = sprintf("%d:%d:%d:%d:%s", r, g, b, (int)max_dist, emoteid);
	if (!undefinedp(emote_pixel_distance_cache[cachekey])) return emote_pixel_distance_cache[cachekey];
	mapping emote = emotes_by_id[emoteid];
	float total_alpha = 0;
	for (int y = 0; y < emote->ysize; ++y) for (int x = 0; x < emote->xsize; ++x) {
		int alpha = emote->alpha_hsv->getpixel(x, y)[2];
		//Shortcut: Fully transparent pixels can't count.
		if (!alpha) continue;
		//Calculate the distance from this pixel on this emote to the target pixel
		[int rr, int gg, int bb] = emote->image->getpixel(x, y);
		//Using the redmean algorithm from https://en.wikipedia.org/wiki/Color_difference
		//(but skipping the square-rooting)
		int avg_red = (r + rr) / 2;
		rr = (rr - r) ** 2;
		gg = (gg - g) ** 2;
		bb = (bb - b) ** 2;
		int distance = rr * (2 + (avg_red >= 128)) + gg * 4 + bb * (2 + (avg_red < 128));
		if (distance > max_dist) continue;
		//Okay, so the pixel counts. However, if it's partly transparent, it only counts partly.
		total_alpha += alpha / 255.0;
	}
	return emote_pixel_distance_cache[cachekey] = total_alpha;
}

array find_nearest(int r, int g, int b, array(string) emotes) {
	mapping(string:float) counts = ([]);
	float max_dist = 1024.0 / 4;
	while (!sizeof(counts)) {
		max_dist *= 4;
		foreach (emotes, string emoteid) {
			float count = count_nearby_pixels(r, g, b, emoteid, max_dist);
			if (count >= 1.0) counts[emoteid] = count; //If there's less than one entire pixel, ignore it.
		}
		if (!sizeof(counts)) continue; //Clearly no successes
		if (max(@values(counts)) < 100) counts = ([]); //No good hits. Spread the net further.
	}
	//Now, pick a suitable emote based on these distances.
	//For now just pick the single nearest. Ultimately a weighted random will be better.
	emotes = indices(counts); sort(values(counts), emotes);
	return ({emotes[-1], sprintf("%O %O", counts[emotes[-1]], max_dist)});
}

continue string|Concurrent.Future make_emote(string emoteid, string|void channel) {
	string code = sprintf("%024x", random(1<<96)); //TODO: check for collisions
	mapping info = built_emotes[code] = (["emoteid": emoteid, "channel": channel || ""]);
	array emotes = yield(fetch_global_emotes());
	//emotes = ({ }); //Optionally hide the global emotes for speed
	if (channel && channel != "") {
		channel = (string)yield(get_user_id(channel));
		emotes += yield(get_helix_paginated("https://api.twitch.tv/helix/chat/emotes", (["broadcaster_id": channel])));
	}
	//Step 1: Fetch the emote we're building from.
	string imgdata = yield(fetch_emote(emoteid, "1.0")); //TODO: Go back to scale 3.0
	mapping basis = parse_emote(imgdata);
	//Note that we won't use the alpha channel in determining the emote to use for a pixel.
	//Instead, AFTER selecting an emote (which might be meaningless if the pixel is fully
	//transparent), we apply the same transparency to the entire emote. This should have the
	//correct effect, albeit with some unnecessary work in some cases. The only exception is
	//completely transparent pixels (alpha == 0), for which the work would be a complete and
	//utter waste, so we just pick the first emote on the list.
	array emoteids = emotes->id; mapping emotenames = mkmapping(emoteids, emotes->name);
	mixed _ = yield(fetch_all_emotes(emoteids));
	info->matrix = allocate(basis->ysize, allocate(basis->xsize));
	info->emote_names = ([]);
	for (int y = 0; y < basis->ysize; ++y) for (int x = 0; x < basis->xsize; ++x) {
		//For the alpha channel, we don't care about hue or saturation.
		int alpha = basis->alpha_hsv->getpixel(x, y)[2];
		string pixel; string meta;
		if (!alpha) pixel = emoteids[0];
		else [pixel, meta] = find_nearest(@basis->image->getpixel(x, y), emoteids);
		info->matrix[y][x] = ({pixel, alpha});
		info->emote_names[pixel] = emotenames[pixel];
		if (alpha) werror("[%d, %d] %d/%d/%d Pixel: %s/%d [%s]\n", x, y, @basis->image->getpixel(x, y), pixel, alpha, meta);
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

	return (["{error}": "Sorry! This is currently disabled pending massive optimization work."]);

	string channame = sizeof(param) > 1 && param[1]; //TODO: Support "channelname emoteGoesHere" as well
	string code = yield(make_emote(person->emotes[0][0], channame));
	return (["{code}": code, "{url}": sprintf("%s/emotegrid?code=%s",
		persist_config["ircsettings"]->http_address || "http://BOT_ADDRESS",
		code,
	)]);
}

protected void create(string name) {::create(name);}
