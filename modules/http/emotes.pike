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
</style>
";

//Consistent display order for the well-known groups. Any group not listed here will
//be included at the top of the page where it's easy to spot.
constant order = ({
	"Follower",
	"Tier 1", "Tier 2", "Tier 3",
	"Bits",
	"Subscriber badges", "Bits badges",
});

continue mapping(string:mixed)|Concurrent.Future|int http_request(Protocols.HTTP.Server.Request req)
{
	if (!req->misc->session->fake && req->request_type == "POST" && req->variables->checkfile) {
		if (sizeof(req->body_raw) > 1024*1024*10) return jsonify((["error": "File too large for analysis."]));
		return jsonify(analyze_emote(req->body_raw));
	}
	if (req->variables->cheer) {
		//Show cheeremotes, possibly for a specific broadcaster
		//Nothing to do with the main page, other than that it's all about emotes.
		mapping info = yield(twitch_api_request("https://api.twitch.tv/helix/bits/cheermotes?broadcaster_id={{USER}}",
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
		if ((string)id != req->variables->broadcaster) id = yield(get_user_id(req->variables->broadcaster));
		array emotes = yield(twitch_api_request("https://api.twitch.tv/helix/chat/emotes?broadcaster_id=" + id))->data;
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
		array badges = yield(twitch_api_request("https://api.twitch.tv/helix/chat/badges?broadcaster_id=" + id))->data;
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
			"emotes": "img", "title": "Channel emotes: " + yield(get_user_info(id))->display_name,
			"text": sprintf("%{\n## %s\n%{%s %}\n%}", emotesets),
		]));
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
	//Animating emotes with automated tools (including Twitch's own) doesn't work too well if you
	//have any partial transparency.
	object alpha = emote->alpha->clone();
	int have_partial = 0;
	for (int y = 0; y < alpha->ysize(); ++y) for (int x = 0; x < alpha->xsize(); ++x) {
		int value = `+(@alpha->getpixel(x, y));
		if (value > 0 && value < 255*3) {
			have_partial = 1;
			value = value < 128*3 ? 0 : 255;
			alpha->setpixel(x, y, value, value, value);
		}
	}
	if (have_partial) {
		ret->tips += ({"Image has partial transparency. This works in PNG files but not in GIFs, so this may have trouble with animations. Consider quantizing alpha levels if animating this emote."});
		ret->downloads += ({([
			"label": "Alpha-quantized",
			"image": make_emote(emote->image, alpha),
		])});
	}
	return ret;
}
