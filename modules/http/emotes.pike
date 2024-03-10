inherit http_endpoint;

/* TODO: Merge checklist.pike into this file.

* Make checklist redirect to emotes?checklist
* Make checklist?showcase redirect to emotes?showcase
* Merge in all functionality
* Leave checklist.pike doing the redirects if necessary; ultimately remove the file.
  - Would it violate expectations to have /checklist redirection managed by this file?

*/

constant markdown = #"# Emote tools, showcases and checklists

* [Checklist of unlockable emotes](checklist) eg hype trains, special promos
* <form><label>Channel name: <input name=broadcaster size=20></label><input type=submit value=\"Show channel emotes\"></form>
* [View all of your available emotes](emotes?available)
* [Global cheer emotes](emotes?cheer)

## Analysis and tips
<form>Upload an emote for tips: <input type=file accept=\"image/*\"></form>
<div class=filedropzone>Or drop a PNG file here</div>
<div id=emotebg hidden></div>
<div id=emotetips></div>

<style>
.error {
	border: 2px solid red;
	background-color: #fdd;
	padding: 5px;
	margin: 10px;
}
#emotebg label {
	margin: 0 0.5em;
}
.swatch {
	display: inline-block;
	height: 1.2em; width: 1.2em;
	margin: 0 0.2em;
	vertical-align: bottom;
	border: 1px solid rebeccapurple;
}
#img_dl {
	display: flex;
	flex-wrap: wrap;
	gap: 15px;
}
#img_dl image {
	width: 116px;
	height: 116px;
	border: 2px solid rebeccapurple;
}
#img_dl figure {
	margin: 0;
	padding: 0;
}
#img_dl figcaption {
	width: 116px;
	text-align: center;
}
#aqdlg {
	max-width: 800px;
}
.opendlg {
	padding: 0 0.1em;
	margin: 0.3em;
}
</style>

> ### What's alpha quantization?
>
> TLDR: If animations look weird, try alpha quantization.
>
> The [PNG file format](https://en.wikipedia.org/wiki/PNG) supports all kinds of
> features, including gentle edges that fade away to transparent. However, animated
> emotes use the [GIF file format](https://en.wikipedia.org/wiki/GIF), which has a
> number of restrictions; something can be completely transparent, but it can't be
> half transparent. This is called the \"alpha channel\" in a PNG file, and if you
> use an automated tool to animate your emote, there may be issues from partial
> transparency.
>
> After alpha quantization, everything will be either completely transparent, or
> completely opaque (not transparent at all). This may be a little bit ugly, so it
> might be worth manually touching up the file a little afterwards. Three versions
> are provided - the default will look decent on both light and dark modes, but may
> lose some detail; and then one each for light and dark which will look correct in
> that mode, but will look a bit wrong in the other. Use whichever makes the most
> sense for your emotes.
>
> [Close](:.dialog_close)
{: tag=dialog #aqdlg}
";

//Consistent display order for the well-known groups. Any group not listed here will
//be included at the top of the page where it's easy to spot.
constant order = ({
	"Follower",
	"Tier 1", "Tier 2", "Tier 3",
	"Bits",
	"Subscriber badges", "Bits badges",
});

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	if (!req->misc->session->fake && req->request_type == "POST" && req->variables->checkfile) {
		if (sizeof(req->body_raw) > 1024*1024*10) return jsonify((["error": "File too large for analysis."]));
		return jsonify(analyze_emote(req->body_raw));
	}
	if (req->variables->cheer) {
		//Show cheeremotes, possibly for a specific broadcaster
		//Nothing to do with the main page, other than that it's all about emotes.
		mapping info = await(twitch_api_request("https://api.twitch.tv/helix/bits/cheermotes?broadcaster_id={{USER}}",
			0, (["username": req->variables->broadcaster || "twitch"])));
		array emotes = info->data; info->data = "<suppressed>";
		array cheeremotes = ({ });
		foreach (emotes, mapping em) {
			array tiers = ({ });
			multiset(string) flags = (<"Unavailable", "Hidden">);
			foreach (em->tiers || ({ }), mapping tier) {
				tiers += ({
					sprintf("<figure>![%s](%s)"
						"<figcaption style=\"color: %s\">%[0]s</figcaption></figure>",
						em->prefix + tier->id,
						tier->images->light->animated["4"],
						tier->color || "black")
				});
				if (tier->can_cheer) flags->Unavailable = 0;
				if (tier->show_in_bits_card) flags->Hidden = 0;
			}
			if (em->is_charitable) flags->Charitable = 1;
			if (em->type == "display_only") flags["Display-only"] = 1;
			if (em->type == "global_third_party") flags["Third-party"] = 1;
			if (em->type == "channel_custom") flags["Channel-unique"] = 1;
			cheeremotes += ({({em->prefix, sizeof(flags) ? "\n#### " + sort(indices(flags)) * ", " : "", tiers})});
		}
		return render_template("checklist.md", ([
			"login_link": "", "emotes": "img", "title": "Cheer emotes: " + (req->variables->broadcaster || "global"),
			"text": sprintf("%{\n## %s%s\n%{%s %}\n%}", cheeremotes),
			//sprintf("<pre>%O</pre>", cheeremotes),
		]));
	}
	if (req->variables->broadcaster) {
		//Show emotes for a specific broadcaster
		//Nothing to do with the main page, other than that it's all about emotes.
		int id = (int)req->variables->broadcaster;
		//If you pass ?broadcaster=49497888 this will show for that user ID. Otherwise, look up the name and get the ID.
		if ((string)id != req->variables->broadcaster) id = await(get_user_id(req->variables->broadcaster));
		array emotes = await(twitch_api_request("https://api.twitch.tv/helix/chat/emotes?broadcaster_id=" + id))->data;
		mapping sets = ([]);
		mapping setids = (["Subscriber badges": -1, "Bits badges": -2]); //Map description to ID for second pass
		foreach (emotes, mapping em) {
			if (em->emote_type == "bitstier") em->emote_set_id = "Bits"; //Hack - we don't get the bits levels anyway, so just group 'em.
			if (!sets[em->emote_set_id]) {
				string desc = "Unknown";
				switch (em->emote_type) {
					case "subscriptions": desc = "Tier " + em->tier[..0]; break;
					case "follower": desc = "Follower"; break;
					case "bitstier": desc = "Bits"; break; //The actual unlock level is missing.
					default: break;
				}
				//Group animated emotes separately so they all show up at the end of the
				//corresponding block. We'll recombine them later.
				if (has_value(em->format, "animated")) desc += " Animated";
				sets[em->emote_set_id] = ({desc, ({ })});
				setids[desc] = em->emote_set_id;
			}
			sets[em->emote_set_id][1] += ({
				sprintf("<figure>![%s](%s)"
					"<figcaption>%[0]s</figcaption></figure>", em->name,
					replace(em->images->url_4x, "/static/", "/default/")) //Most emotes have the same image for static and default. Anims get a one-frame for static, and the animated for default.
			});
		}
		foreach (setids; string desc; string id) if (has_suffix(desc, " Animated")) {
			if (string other = setids[desc - " Animated"]) {
				//There's both "Tier 1" and "Tier 1 Animated". Fold them together.
				sets[other][1] += sets[id][1];
				m_delete(sets, id);
			} else {
				//There's animated but no static for this group. Just remove the tag.
				sets[id][0] -= " Animated";
			}
		}
		//Also fetch the badges. They're intrinsically at a different size, but they'll be stretched to the same size.
		//If that's a problem, it'll need to be solved in CSS (probably with a classname on the figure here).
		array badges = await(twitch_api_request("https://api.twitch.tv/helix/chat/badges?broadcaster_id=" + id))->data;
		foreach (badges, mapping set) {
			mapping cur = ([]);
			if (set->set_id == "subscriber") cur[1999] = cur[2999] = "<br>";
			foreach (set->versions, mapping badge) {
				string desc = badge->id;
				if (set->set_id == "subscriber") {
					int tier = (int)badge->id / 1000;
					int tenure = (int)badge->id % 1000;
					desc = ({"T1", 0, "T2", "T3"})[tier];
					if (tenure) desc += ", " + tenure + " months";
					else desc += ", base";
				}
				cur[(int)badge->id] = sprintf("<figure>![%s](%s)"
						"<figcaption>%[0]s</figcaption></figure>",
						desc, badge->image_url_4x,
				);
			}
			array b = values(cur); sort(indices(cur), b);
			if (set->set_id == "subscriber") sets[-1] = ({"Subscriber badges", b});
			if (set->set_id == "bits") sets[-2] = ({"Bits badges", b});
		}
		array sorted = ({ });
		foreach (order, string lbl)
			if (array s = m_delete(sets, setids[lbl])) sorted += ({s});
		//Any that weren't found, stick at the beginning so they're obvious
		array emotesets = values(sets); sort((array(int))indices(sets), emotesets);
		emotesets += sorted;
		if (!sizeof(emotesets)) emotesets = ({({"None", ({"No emotes found for this channel. Partnered and affiliated channels have emote slots available; emotes awaiting approval may not show up here."})})});
		return render_template("checklist.md", ([
			"login_link": "<button id=greyscale onclick=\"document.body.classList.toggle('greyscale')\">Toggle Greyscale (value check)</button>",
			"emotes": "img", "title": "Channel emotes: " + await(get_user_info(id))->display_name,
			"text": sprintf("%{\n## %s\n%{%s %}\n%}", emotesets),
		]));
	}
	if (req->variables->available) {
		//Hack for the moment. Not sure what I want for this page. The main reason
		//I want this feature is to allow mods to pick out emotes for any voice.
		if (mapping resp = ensure_login(req, "user:read:emotes")) return resp;
		mapping emotes = await(get_helix_paginated("https://api.twitch.tv/helix/chat/emotes/user", ([
			"user_id": req->misc->session->user->id,
			//"broadcaster_id": channel_id, //optionally include follower emotes from that channel
		]), (["Authorization": "Bearer " + req->misc->session->token])));
		return render_template("checklist.md", (["text": sprintf("<pre>%O</pre>", emotes)]));
	}
	return render_template(markdown, (["js": "emotes.js"]));
}

string make_emote(object image, object alpha) {
	string raw = Image.PNG.encode(image, (["alpha": alpha]));
	return "data:image/png;base64," + MIME.encode_base64(raw, 1);
}

mapping analyze_emote(string raw) {
	if (!has_prefix(raw, "\x89PNG\r\n\x1a\n\0")) return (["error": "Only PNG emotes can be analyzed at this time."]);
	mapping emote = Image.PNG._decode(raw);
	mapping ret = ([]);
	if (emote->xsize != emote->ysize) ret->warnings += ({sprintf("Emote is not square - %dx%d", emote->xsize, emote->ysize)});
	if (emote->xsize != 112 || emote->ysize != 112) {
		ret->tips += ({"Emotes generally work best at 112x112"});
		ret->downloads += ({([
			"label": "Rescaled to 112x112",
			"image": make_emote(emote->image->scale(112, 112), emote->alpha->scale(112, 112)),
		])});
	}
	//Should this be conditional on it, maybe, having colour? For now, just always show it.
	ret->tips += ({
		"How good is the contrast between foreground and background after all the colour is removed? Check the greyscale version to be sure.",
		"Does the emote look correct on a variety of backgrounds?",
	});
	ret->downloads += ({([
		"label": "Greyscale",
		"image": make_emote(emote->image->grey(), emote->alpha),
	])});
	//Animating emotes with automated tools (including Twitch's own) doesn't work too well if you
	//have any partial transparency.
	object alpha, alphahalf, aqlight, aqdark;
	int have_partial = 0;
	for (int y = 0; y < emote->ysize; ++y) for (int x = 0; x < emote->xsize; ++x) {
		int value = emote->alpha->getpixel(x, y)[0]; //Assumes that all three are set to the same value
		if (value > 0 && value < 255) {
			if (!have_partial) {
				have_partial = 1;
				//Copy the emote. The alpha channel gets set to either full or empty,
				//and three versions are created: unchanged, folded towards light, and
				//folded towards dark (where "light" and "dark" are white and #18181B).
				alpha = emote->alpha->clone();
				alphahalf = emote->alpha->clone();
				aqlight = emote->image->clone();
				aqdark = emote->image->clone();
			}
			int half = value < 128 ? 0 : 255;
			int tight = value < 5 ? 0 : 255; //Tighter definition of "transparent" - anything under 2% becomes transparent, else solid
			alphahalf->setpixel(x, y, half, half, half);
			alpha->setpixel(x, y, tight, tight, tight);
			if (tight) { //(otherwise the pixel colour is irrelevant)
				array orig = emote->image->getpixel(x, y)[*] * value;
				array light = ({255, 255, 255})[*] * (256 - value);
				array dark = ({0x18, 0x18, 0x1B})[*] * (256 - value);
				array newlight = light[*] + orig[*];
				array newdark = dark[*] + orig[*];
				if (x > 28 && y > 28 && x < 84 && y < 84)
					werror("[%d,%d] Orig (%d)%{ %d%} Now%{ %d%} or%{ %d%}\n", x, y, value, emote->image->getpixel(x, y), newlight[*] / 256, newdark[*] / 256);
				aqlight->setpixel(x, y, @(newlight[*] / 256));
				aqdark->setpixel(x, y, @(newdark[*] / 256));
			}
		}
	}
	if (have_partial) {
		ret->tips += ({
			"Image has partial transparency. This works in PNG files but not in GIFs, so this may have trouble with animations. Consider ||quantizing alpha levels|| if animating this emote.",
		});
		ret->downloads += ({([
			"label": "Alpha-quantized",
			"image": make_emote(emote->image, alphahalf),
		]), ([
			"label": "AQ Light",
			"image": make_emote(aqlight, alpha),
		]), ([
			"label": "AQ Dark",
			"image": make_emote(aqdark, alpha),
		])});
	}
	return ret;
}
