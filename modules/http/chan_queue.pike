//This violates the "two letter uniqueness" rule, but Q is *hard* for that.
inherit builtin_command;
inherit http_websocket;

//TODO: Consider an off-platform request option where people can authenticate
//using some other service eg VRChat and contribute requests

constant markdown = #"# Request Queue

<div id=queueinfo>Loading...</div>

<div id=flashed-message></div>

> ### Configure panel view
>
> <div id=panelconfigs></div>
>
> [Apply](:#panelcfgsave .dialog_close) [Cancel](:.dialog_close)
{: tag=formdialog #panelcfgdlg}

<style>
.blank {list-style-type: none; height: 1em;}
.heading {list-style-type: none; font-weight: bold; font-size: larger;}
#flashed-message {
	position: fixed;
	left: 3em;
	top: 1em;
	right: 3em;
	border: 1px solid rebeccapurple;
	background: aliceblue;
	opacity: 0;
	transition: opacity 2s;
}
#flashed-message.visible {
	opacity: 1;
	transition: opacity 0.25s;
}
</style>

> ### Choose on behalf of
>
> <label>Selection: <input readonly id=cf_selection size=40></label><br>
> <label>User name: <input id=cf_username size=20></label><br>
>
> [Choose](:#choosefor .dialog_close) [Cancel](:.dialog_close)
{: tag=formdialog #choosefordlg}
";

//View-only mode that doesn't require any login (eg for embedding in OBS)
constant viewonlymode = #"
<div id=queueinfo></div>

<style>
main {max-width: unset; background: none; padding: 0;}
</style>
";

//Mini-mode that can be used as an OBS panel
constant minimode = #"
<div id=queueinfo>Loading...</div>

<style>
main {
	max-width: unset;
	background: none;
	padding: 0;
}
table {
	width: 100%;
}
td, th {
	border-bottom: 1px solid #2a2a2a;
	text-align: left;
}
th {
	padding: 8px 6px;
}
td {
	padding: 6px;
}
tr:nth-child(even) td {
	background: #1a1a1f;
}
.unchoose {
	background: none;
	border: none;
	color: #cfcfd4;
	font-size: 1em;
	cursor: pointer;
	padding: 0 6px;
	line-height: 1;
	border-radius: 6px;
}

.unchoose:hover {
	background: #3a1f2b;
	color: #ff4d6d;
}

#bottombar {
	position: fixed;
	bottom: 12px;
	left: 0; right: 0;
	display: flex;
	justify-content: space-around;
}
#openqueue, #closequeue {
	/* TODO: Secondary textformatting for these buttons */
	color: white;
	font-size: 13px;
	font-weight: 600;
	border: none;
	border-radius: 8px;
	padding: 8px 18px;
	cursor: pointer;
}
button#openqueue {background: #229922;}
button#closequeue {background: #992222;}
</style>
";

__async__ mapping choose(object channel, string selection, string user, mapping|void extra) {
	if (!extra) extra = ([]);
	mapping ret = ([]);
	await(G->G->DB->mutate_config(channel->userid, "requestqueue") {mapping cfg = __ARGS__[0];
		//First, check the queue: if there are too many from this user, reject.
		if (!cfg->queue_open || !cfg->selections) {ret->error = "Queue is not open."; return;}
		if (int limit = cfg->queuelimit) {
			foreach (cfg->queue || ({ }), mapping q)
				if (q->user == user) --limit;
			if (limit <= 0) {ret->error = "You already have requests pending."; return;}
		}
		//Okay. So, let's see if we can add this one.
		//Note that we don't deduplicate with existing requests.
		array matches = ({ }), scores = ({ });
		string match = lower_case(selection);
		foreach (cfg->selections, mapping sel) if (sel->title) {
			int score = String.fuzzymatch(lower_case(sel->title), match);
			if (sel->shorttitle) score += String.fuzzymatch(lower_case(sel->shorttitle), match) * 2;
			else score *= 3;
			if (score > 100) {matches += ({sel}); scores += ({score});}
		}
		if (!sizeof(matches)) {ret->error = "Couldn't find that song - check the song list"; return;} //Nothing was a good enough match
		sort(scores, matches);
		cfg->queue += ({([
			"title": ret->selection = matches[-1]->title,
			"user": user,
		]) | extra});
	});
	if (ret->selection) send_updates_all(channel, "");
	return ret;
}

__async__ mapping unchoose(object channel, string user) {
	mapping ret = ([]);
	await(G->G->DB->mutate_config(channel->userid, "requestqueue") {mapping cfg = __ARGS__[0];
		if (!cfg->queue) {ret->error = "Queue is not active."; return;}
		int idx = -1;
		foreach (cfg->queue; int i; mapping q) if (q->user == user) idx = i; //Retain the last, not the first, found
		if (idx == -1) {ret->error = "You don't have anything in the queue."; return;}
		ret->selection = cfg->queue[idx]->title;
		cfg->queue[idx] = 0;
		cfg->queue -= ({0});
	});
	if (ret->selection) send_updates_all(channel, "");
	return ret;
}

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	if (req->variables->mini) return render(req, viewonlymode, (["vars": (["ws_group": "", "minimode": 1, "is_mod": 0, "myname": "-"])]));
	if (!req->misc->session->user) return render_template("login.md", req->misc->chaninfo);
	if (req->variables->panel) return render(req, minimode, (["vars": ([
		"ws_group": "",
		"is_mod": await(modprobe(req)), //Show or hide the mod-specific things. If you hack this in the front end, you'll get a bunch of non-functional controls.
		"myname": req->misc->session->user->display_name,
		"minimode": 2,
	])])); //No chaninfo - suppress the sidebar
	return render(req, (["vars": ([
		"ws_group": "",
		"is_mod": await(modprobe(req)), //Show or hide the mod-specific things. If you hack this in the front end, you'll get a bunch of non-functional controls.
		"myname": req->misc->session->user->display_name,
		"minimode": 0,
	])]) | req->misc->chaninfo);
}

__async__ mapping get_chan_state(object channel, string grp, string|void id) {
	return await(G->G->DB->load_config(channel->userid, "requestqueue"));
}

//Shorten a title to the most relevant part, for priority matching
string shorten(string title) {
	if (sscanf(title, "%s(%*s)%s", string before, string after))
		return String.trim(before) + " " + String.trim(after);
	return title;
}

@"is_mod": void wscmd_configure(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	//Configure things. Do we even HAVE a queue? If we do, is it open and accepting requests?
	//Can people request more than one? Etc.
	G->G->DB->mutate_config(channel->userid, "requestqueue") {mapping cfg = __ARGS__[0];
		if (msg->open) cfg->queue_open = 1;
		if (msg->closed) m_delete(cfg, "queue_open");
		if (msg->queuelimit) {
			//Set queuelimit to 1 or "1" to limit to one per person; but to
			//remove the limit, set it to "0". I could use undefinedp() here
			//but with the quirks of JavaScript on the front end, easier to
			//just use a string.
			int limit = (int)msg->queuelimit;
			if (limit <= 0) m_delete(cfg, "queuelimit");
			else cfg->queuelimit = limit;
		}
		if (arrayp(msg->selections)) {
			//TODO: If we add any info other than just the title, do a lookup and locate
			//the previous version of them so they get kept.
			array prev = cfg->selections || ({ });
			cfg->selections = ({ });
			foreach (msg->selections, string sel) cfg->selections += ({
				sel == "" ? (["gap": 1]) //
				: sel[0] == '#' ? (["heading": String.trim(sel[1..])])
				: (["title": String.trim(sel), "shorttitle": shorten(String.trim(sel))])
			});
			//Clean off any blanks at the end
			while (sizeof(cfg->selections) && cfg->selections[-1]->gap)
				cfg->selections = cfg->selections[..<1];
		}
		if (mappingp(msg->panelstyle)) {
			mapping style = ([]);
			foreach (TEXTFORMATTING_ATTRS + ({"itemlbl", "originlbl"}), string attr)
				style[attr] = msg->panelstyle[attr];
			textformatting_validate(style);
			style->css_text = textformatting_css(style),
			cfg->panelstyle = style;
		}
	}->then() {send_updates_all(channel, "");};
}

@"is_mod": __async__ void wscmd_editselection(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	//Edit a selection. This won't change existing queue entries.
	//TODO: Allow extra info to be added than just the title?
}

__async__ mapping wscmd_choose(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	//Select something. If you're a mod, you can do an "on behalf of" that changes the source name,
	//though it'll still record the "added by".
	mapping extra = ([]);
	string user = conn->session->user->display_name;
	if (conn->is_mod && msg->added_for) {
		extra->added_by = user;
		user = msg->added_for;
	}
	mapping ret = await(choose(channel, msg->selection, user, extra));
	return (["cmd": "choose", "selection": ret->selection || "", "error": ret->error || ""]);
}

void wscmd_unchoose(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	//Remove a selection. If you're a mod, you can remove anyone's selections. Currently
	//this is the only way to say "done", though there may need to be a simple "next" button.
	//Non-mods can cancel their own requests.
	if (undefinedp(msg->index) || !intp(msg->index)) return;
	G->G->DB->mutate_config(channel->userid, "requestqueue") {mapping cfg = __ARGS__[0];
		if (!cfg->queue || msg->index >= sizeof(cfg->queue)) return;
		mapping sel = cfg->queue[msg->index];
		if (conn->is_mod || sel->user == conn->session->user->display_name) {
			cfg->queue[msg->index] = 0;
			cfg->queue -= ({0});
		}
	}->then() {send_updates_all(channel, "");};
}

constant builtin_name = "Request Queue";
constant builtin_param = ({"/Action/choose/unchoose", "Selection"});
constant vars_provided = ([
	"{selection}": "The actual selection that was added",
	"{error}": "If nonblank, there was a problem",
]);

__async__ mapping message_params(object channel, mapping person, array param, mapping cfg) {
	//Choose or unchoose something.
	//Start with a fuzzy match of the param against the available selections. If nothing is
	//sufficiently close, fail. If unchoosing, allow a blank to mean "first available", but
	//for choosing, require that it be kinda close. Maybe offer a suggestion if within a
	//further threshold?
	if (sizeof(param) != 2) return ([]);
	switch (param[0]) {
		case "choose": {
			mapping ret = await(choose(channel, param[1], person->displayname));
			return (["{selection}": ret->selection || "", "{error}": ret->error || ""]);
		}
		case "unchoose": {
			mapping ret = await(unchoose(channel, person->displayname));
			return (["{selection}": ret->selection || "", "{error}": ret->error || ""]);
		}
		default: return (["{selection}": "", "{error}": "Bad subcommand"]);
	}
}

protected void create(string name) {::create(name);}
