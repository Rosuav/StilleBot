//This violates the "two letter uniqueness" rule, but Q is *hard* for that.
inherit builtin_command;
inherit http_websocket;

//TODO: Consider an off-platform request option where people can authenticate
//using some other service eg VRChat and contribute requests

constant markdown = #"# Request Queue

<div id=queueinfo>Loading...</div>

<style>
.blank {list-style-type: none; height: 1em;}
.heading {list-style-type: none; font-weight: bold; font-size: larger;}
</style>

> ### Choose on behalf of
>
> <label>Selection: <input readonly id=cf_selection size=40></label><br>
> <label>User name: <input id=cf_username size=20></label><br>
>
> [Choose](:#choosefor .dialog_close) [Cancel](:.dialog_close)
{: tag=formdialog #choosefordlg}
";

void choose(object channel, string selection, string user, mapping|void extra) {
	if (!extra) extra = ([]);
	G->G->DB->mutate_config(channel->userid, "requestqueue") {mapping cfg = __ARGS__[0];
		//First, check the queue: if there are too many from this user, reject.
		if (!cfg->queue_open || !cfg->selections) return; //No selecting at all
		if (int limit = cfg->queuelimit) {
			foreach (cfg->queue || ({ }), mapping q)
				if (q->user == user) --limit;
			if (limit <= 0) return;
		}
		//Okay. So, let's see if we can add this one.
		//Note that we don't deduplicate with existing requests.
		array matches = ({ }), scores = ({ });
		string match = lower_case(selection);
		foreach (cfg->selections, mapping sel) if (sel->title) {
			int score = String.fuzzymatch(lower_case(sel->title), match);
			if (score > 66) {matches += ({sel}); scores += ({score});}
		}
		if (!sizeof(matches)) return; //Nothing was a good enough match
		sort(scores, matches);
		cfg->queue += ({([
			"title": matches[-1]->title,
			"user": user,
		]) | extra});
	}->then() {send_updates_all(channel, "");};
}

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	if (!req->misc->session->user) return render_template("login.md", req->misc->chaninfo);
	return render(req, (["vars": ([
		"ws_group": "",
		"is_mod": await(modprobe(req)), //Show or hide the mod-specific things. If you hack this in the front end, you'll get a bunch of non-functional controls.
		"myname": req->misc->session->user->?display_name || "-",
	])]) | req->misc->chaninfo);
}

__async__ mapping get_chan_state(object channel, string grp, string|void id) {
	return await(G->G->DB->load_config(channel->userid, "requestqueue"));
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
				: (["title": String.trim(sel)])
			});
			//Clean off any blanks at the end
			while (sizeof(cfg->selections) && cfg->selections[-1]->gap)
				cfg->selections = cfg->selections[..<1];
		}
	}->then() {send_updates_all(channel, "");};
}

@"is_mod": __async__ void wscmd_editselection(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	//Edit a selection. This won't change existing queue entries.
	//TODO: Allow extra info to be added than just the title?
}

mapping wscmd_choose(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	//Select something. If you're a mod, you can do an "on behalf of" that changes the source name,
	//though it'll still record the "added by".
	mapping extra = ([]);
	string user = conn->session->user->display_name;
	if (conn->is_mod && msg->added_for) {
		extra->added_by = user;
		user = msg->added_for;
	}
	choose(channel, msg->selection, user, extra);
	//return (["cmd": "choose", "selection": actual selection, "error": blank if okay else reason for rejection]);
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
