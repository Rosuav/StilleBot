//This violates the "two letter uniqueness" rule, but Q is *hard* for that.
inherit builtin_command;
inherit http_websocket;

//TODO: Consider an off-platform request option where people can authenticate
//using some other service eg VRChat and contribute requests

constant markdown = #"# Request Queue

<div id=queueinfo>Loading...</div>
";

@retain: mapping(int:array) request_queue = ([]);

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	return render(req, (["vars": ([
		"ws_group": "",
		"is_mod": await(modprobe(req)), //Show or hide the mod-specific things. If you hack this in the front end, you'll get a bunch of non-functional controls.
	])]) | req->misc->chaninfo);
}

__async__ mapping get_chan_state(object channel, string grp, string|void id) {
	return ([
		"config": await(G->G->DB->load_config(channel->userid, "requestqueue")),
		"queue": request_queue[channel->userid] || ({ }),
	]);
}

@"is_mod": __async__ void wscmd_configure(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	//Configure things. Do we even HAVE a queue? If we do, is it open and accepting requests?
	//Can people request more than one? Etc.
}

@"is_mod": __async__ void wscmd_newselection(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	//Mods can add a new thing to the selections. Or multiple, offer an MLE.
}

@"is_mod": __async__ void wscmd_editselection(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	//Edit a selection. This won't change existing queue entries.
}

void wscmd_choose(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	//Select something. If you're a mod, you can do an "on behalf of" that changes the source name,
	//though it'll still record the "added by".
}

void wscmd_unchoose(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	//Remove a selection. If you're a mod, you can remove anyone's selections. Currently
	//this is the only way to say "done", though there may need to be a simple "next" button.
	//Non-mods can cancel their own requests.
}

constant builtin_name = "Request Queue";
constant builtin_param = ({"/Action/choose/unchoose", "Selection"});
constant vars_provided = ([
	"{selection}": "The actual selection, or blank if not found",
]);

__async__ mapping message_params(object channel, mapping person, array param, mapping cfg) {
	//Choose or unchoose something.
	//Start with a fuzzy match of the param against the available selections. If nothing is
	//sufficiently close, fail. If unchoosing, allow a blank to mean "first available", but
	//for choosing, require that it be kinda close. Maybe offer a suggestion if within a
	//further threshold?
	return ([]);
}

protected void create(string name) {::create(name);}
