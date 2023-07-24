inherit http_endpoint;
inherit annotated;
inherit builtin_command;

//How (relatively) important are the hue, saturation, and value components
//in determining the similarity of colours?
constant HUE_WEIGHT = 1;
constant SAT_WEIGHT = 1;
constant VAL_WEIGHT = 1;

constant markdown = #"# Emote grid

<style>
#emotegrid td {padding: 0;}
</style>

<div id=grid></div>";

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
	if (req->variables->code == "json") built_emotes->json = Standards.JSON.decode(Stdio.read_file("emotegrid.json"));
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

string find_nearest(int h, int s, int v, array(string) emotes) {
	mapping(string:int) distances = ([]);
	foreach (emotes, string emoteid) {
		mapping emote = emotes_by_id[emoteid];
		if (!emote) continue; //Shouldn't happen (the emotes should have been precached)
		string cachekey = sprintf("%d:%d:%d:%s", h, s, v, emoteid);
		if (undefinedp(emote_pixel_distance_cache[cachekey])) {
			int total_distance = 0;
			for (int y = 0; y < emote->ysize; ++y) for (int x = 0; x < emote->xsize; ++x) {
				//Calculate the distance from this pixel on this emote to the target pixel
				[int hh, int ss, int vv] = emote->image_hsv->getpixel(x, y);
				//Calculate by distance-squared
				hh = (hh - h) ** 2;
				ss = (ss - s) ** 2;
				vv = (vv - v) ** 2;
				int distance = hh * HUE_WEIGHT + ss * SAT_WEIGHT + vv * VAL_WEIGHT;
				//The more transparent a pixel is, the more distant it is from everything.
				//This will tend to produce mosaics with "full" emotes rather than those
				//with some transparency to them. Need to tweak this algorithm.
				distance *= 256 - emote->alpha_hsv->getpixel(x, y)[2];
				total_distance += distance; //Is simply summing the distances correct?
			}
			emote_pixel_distance_cache[cachekey] = total_distance;
		}
		distances[emoteid] = emote_pixel_distance_cache[cachekey];
	}
	//Now, pick a suitable emote based on these distances.
	//For now just pick the single nearest. Ultimately a weighted random will be better.
	emotes = indices(distances); sort(values(distances), emotes);
	return emotes[0];
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
	string imgdata = yield(fetch_emote(emoteid, "1.0")); //TODO: Go back to scale 3.0
	mapping basis = parse_emote(imgdata);
	//Note that we won't use the alpha channel in determining the emote to use for a pixel.
	//Instead, AFTER selecting an emote (which might be meaningless if the pixel is fully
	//transparent), we apply the same transparency to the entire emote. This should have the
	//correct effect, albeit with some unnecessary work in some cases. The only exception is
	//completely transparent pixels (alpha == 0), for which the work would be a complete and
	//utter waste, so we just pick the first emote on the list.
	mixed _ = yield(fetch_all_emotes(emotes));
	info->matrix = allocate(basis->ysize, allocate(basis->xsize));
	for (int y = 0; y < basis->ysize; ++y) for (int x = 0; x < basis->xsize; ++x) {
		//For the alpha channel, we don't care about hue or saturation.
		int alpha = basis->alpha_hsv->getpixel(x, y)[2];
		string pixel;
		if (!alpha) pixel = emotes[0];
		else pixel = find_nearest(@basis->image_hsv->getpixel(x, y), emotes);
		info->matrix[y][x] = ({pixel, alpha});
		werror("[%d, %d] %d/%d/%d Pixel: %s/%d\n", x, y, @basis->image_hsv->getpixel(x, y), pixel, alpha);
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
