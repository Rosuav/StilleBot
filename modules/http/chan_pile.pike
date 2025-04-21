inherit http_websocket;
inherit annotated;
//inherit builtin_command; //Gonna need this
/* The Pile of Stuff

To update the physics engine:
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
	return render(req, ([
		"vars": (["ws_group": ""]),
	]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return grp == "";} //Require mod status for the master socket

__async__ mapping get_chan_state(object channel, string grp) {
	mapping pile = await(G->G->DB->load_config(channel->userid, "pile"));
	return (["items": ({ })]);
}

protected void create(string name) {::create(name);}
