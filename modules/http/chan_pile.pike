inherit http_websocket;
inherit annotated;
//inherit builtin_command; //Gonna need this
/* The Pile of Stuff

To update the physics engine:
- https://brm.io/matter-js/docs/
- Download the released version of matter-js - currently https://github.com/liabru/matter-js/releases/tag/0.20.0
- Copy build/matter.min.js into .../httpstatic/
It's MIT-licensed so this should be all legal.
*/

constant markdown = #"# Pile of Pics for $$channel$$

<script src=\"$$static||matter.min.js$$\"></script>
<div id=demo></div>

";

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	mapping pile = await(G->G->DB->load_config(req->misc->channel->userid, "pile"));
	if (string|zero nonce = req->variables->view) {
		mapping info = pile[nonce];
		if (!info) nonce = 0;
		return render_template("pile.html", ([
			"vars": (["ws_type": ws_type, "ws_group": nonce + "#" + req->misc->channel->userid, "ws_code": "pile"]),
		]));
	}
	if (!req->misc->is_mod) return render_template("login.md", (["msg": "moderator privileges"]) | req->misc->chaninfo);
	array emotes = await(twitch_api_request("https://api.twitch.tv/helix/chat/emotes?broadcaster_id=" + req->misc->channel->userid))->data;
	emotes = emotes->images->url_2x - ({0}); //Shouldn't normally be any nulls but just in case
	//Grab each image (cached if possible) and calculate the bounding box.
	//Ultimately this will be done on upload and saved.
	foreach (emotes; int i; string fn) {
		object res = await(Protocols.HTTP.Promise.get_url(fn));
		mapping img = Image.PNG._decode(res->get());
		Image.Image searchme = img->alpha->threshold(5);
		[int left, int top, int right, int bottom] = searchme->find_autocrop();
		//If we need to do any more sophisticated hull-finding, here's where to do it. For now, just the box.
		//TODO: Allow the user to choose a circular hull, specifying the size and position.
		//If we're cropping at all, add an extra pixel of room for safety. Note that this
		//also protects against entirely transparent images, as it'll make a tiny box in
		//the middle instead of a degenerate non-box.
		if (left > 0) left--;
		if (top > 0) top--;
		if (right < img->xsize - 1) right++;
		if (bottom < img->ysize - 1) bottom++;
		int wid = right - left, hgh = bottom - top;
		emotes[i] = ([
			"fn": fn,
			"xsize": wid, "ysize": hgh,
			"xoffset": -left / (float)wid,
			"yoffset": -top / (float)hgh,
		]);
	}
	return render(req, ([
		"vars": (["ws_group": "", "emotes": emotes]),
	]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return grp == "";} //Require mod status for the master socket

__async__ mapping get_chan_state(object channel, string grp) {
	mapping pile = await(G->G->DB->load_config(channel->userid, "pile"));
	return (["items": ({ })]);
}

protected void create(string name) {::create(name);}
