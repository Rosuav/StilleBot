inherit http_websocket;
inherit hook;

constant markdown = #"# Unlocks!

<p id=nextunlock></p>

Click to view these gorgeous pics fullscreen.

* loading...
{:#unlocks}

[Manage unlocks](:.opendlg data-dlg=managedlg .modonly hidden=true)

> ### Manage unlocks
>
> <div><label>Select variable: <select class=config name=varname></select></label><br>
> <div><label>Unlock cost: <input class=config name=unlockcost type=number> <span id=unlockcostdisplay></span> per pic</label><br>
> <label>Display format: <select class=config name=format>
> <option value=plain>plain</option>
> <option value=currency>currency eg $27.18</option>
> <option value=subscriptions>subscriptions</option>
> </select></label></div>
>
> <div class=uploadtarget></div>
>
> [Shuffle not-yet-unlocked pics](:#shuffle) [Chop off the ones already seen](:#truncate)
>
> * loading...
> {:#allunlocks}
>
> [Close](:.dialog_close)
{: tag=formdialog #managedlg}

<style>
#unlocks {
	list-style-type: none;
	padding: 0;
}
input[type=number] {width: 7.5em;} /* Widen the inputs a bit */
.preview {max-width: 200px; cursor: pointer;}
.preview.small {max-width: 75px;}
figure {width: fit-content;}
figure figcaption {max-width: unset; text-align: center;}
.twocol {
	display: flex;
	justify-content: space-between;
}
#allunlocks li {
	background: #dff;
	margin-bottom: 0.75em;
}
#allunlocks li:nth-child(even) {background: #fdf;}
.unlocked {opacity: 0.6;}
</style>
";

array strconfigs = ({"varname", "format"});
array intconfigs = ({"unlockcost"});

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	return render(req, (["vars": ([
			"ws_group": req->misc->is_mod ? "control" : "",
		]),
	]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return grp == "control";}
__async__ mapping get_chan_state(object channel, string grp, string|void id) {
	mapping cfg = await(G->G->DB->load_config(channel->userid, "unlocks"));
	if (!cfg->varname && grp != "control") return ([]);
	array unlocks = cfg->unlocks || ({ });
	int curval = (int)channel->expand_variables("$" + cfg->varname + "$");
	int unlocked = cfg->unlockcost && curval / cfg->unlockcost; //If you haven't set the unlock cost, nothing has been unlocked.
	mapping ret = ([
		"unlocks": unlocks[..unlocked - 1],
	]);
	ret->curval = curval;
	//If all have been unlocked, there is nothing more to unlock (though more could be added).
	ret->nextval = unlocked < sizeof(unlocks) && cfg->unlockcost * (unlocked + 1);
	ret->unlockcost = cfg->unlockcost;
	ret->format = cfg->format || "plain";
	if (grp == "control") {
		ret->allunlocks = unlocks;
		foreach (strconfigs, string c) ret[c] = cfg[c] || "";
		foreach (intconfigs, string c) ret[c] = cfg[c] || 0;
		mapping vars = G->G->DB->load_cached_config(channel->userid, "variables");
		multiset(string) varnames = (<>);
		foreach (vars; string name;) {
			if (name == "*") continue; //Ignore the collection of user vars
			if (sscanf(name, "%s:%*s", string base)) ; //Ignore user vars for the moment
			else varnames[name - "$"] = 1;
		}
		array variables = sort(indices(varnames));
		ret->varnames = (["id": variables[*]]); //Do we need any other info? Current value?
	}
	return ret;
}

@"is_mod": __async__ void wscmd_delete_unlock(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	await(G->G->DB->mutate_config(channel->userid, "unlocks") {mapping cfg = __ARGS__[0];
		cfg->unlocks = filter(cfg->unlocks || ({ })) {return __ARGS__[0]->id != (int)msg->id;};
	});
	send_updates_all(channel, "");
	send_updates_all(channel, "control");
}

@"is_mod": __async__ void wscmd_update_unlock(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	await(G->G->DB->mutate_config(channel->userid, "unlocks") {mapping cfg = __ARGS__[0];
		if (!cfg->unlocks) return;
		int idx = search(cfg->unlocks->id, (int)msg->id);
		if (idx != -1) {
			mapping unl = cfg->unlocks[idx];
			if (msg->caption) unl->caption = msg->caption;
		}
	});
	send_updates_all(channel, "");
	send_updates_all(channel, "control");
}

@"is_mod": __async__ void wscmd_config(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	await(G->G->DB->mutate_config(channel->userid, "unlocks") {mapping cfg = __ARGS__[0];
		foreach (strconfigs, string c) if (msg[c]) cfg[c] = msg[c];
		foreach (intconfigs, string c) if (!undefinedp(msg[c])) cfg[c] = (int)msg[c];
	});
	send_updates_all(channel, "");
	send_updates_all(channel, "control");
}

@"is_mod": __async__ void wscmd_shuffle(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	await(G->G->DB->mutate_config(channel->userid, "unlocks") {mapping cfg = __ARGS__[0];
		if (!cfg->unlocks || !cfg->unlockcost) return;
		int curval = (int)channel->expand_variables("$" + cfg->varname + "$");
		//Shuffle only those that are still ahead of us, and not the immediate next (in case it's been teased).
		int unlocked = curval / cfg->unlockcost; //Number of pics unlocked so far
		array visible = cfg->unlocks[..unlocked]; //This will include one extra (since the array counts from zero), thus incorporating the potentially-teased.
		array invisible = cfg->unlocks[unlocked+1..];
		//Note that, with 27 images unlocked, we need at least 30 total images to be worth shuffling.
		//Image #28 may have already been teased, so it doesn't get reordered; and if there are only
		//29 total images, there's nothing to shuffle.
		if (sizeof(invisible) < 2) return;
		Array.shuffle(invisible);
		cfg->unlocks = visible + invisible;
	});
	send_updates_all(channel, ""); //Shouldn't be necessary since we don't shuffle the sighted ones
	send_updates_all(channel, "control");
}

@"is_mod": __async__ void wscmd_truncate(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	await(G->G->DB->mutate_config(channel->userid, "unlocks") {mapping cfg = __ARGS__[0];
		if (!cfg->unlocks || !cfg->unlockcost) return;
		int curval = (int)channel->expand_variables("$" + cfg->varname + "$");
		int unlocked = curval / cfg->unlockcost;
		//Retain only those that are still ahead of us
		//TODO: Remove the files corresponding to the unlocks being removed
		cfg->unlocks = cfg->unlocks[unlocked..];
		channel->set_variable(cfg->varname, (string)(curval % cfg->unlockcost), "set");
	});
	send_updates_all(channel, "");
	send_updates_all(channel, "control");
}

//As with chan_monitors, the functionality for uploads is being lifted from alertbox (which comes
//alphabetically prior to this file). May be of value to refactor this at some point.
@"is_mod": __async__ mapping|zero wscmd_upload(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	msg->owner = "unlocks";
	mapping file = await(G->G->DB->prepare_file(channel->userid, conn->session->user->id, msg, 0));
	if (file->error) return (["cmd": "uploaderror", "name": msg->name, "error": file->error]);
	//Add the unlock immediately, without waiting for completion of the upload
	await(G->G->DB->mutate_config(channel->userid, "unlocks") {mapping cfg = __ARGS__[0];
		cfg->unlocks += ({([
			"id": ++cfg->nextid,
			"fileid": file->id,
			"caption": msg->name || "",
		])});
	});
	send_updates_all(channel, ""); //Only necessary if we were out of unlocks previously, but may as well push the update regardless.
	send_updates_all(channel, "control");
	return (["cmd": "upload", "name": msg->name, "id": file->id]);
}

@hook_variable_changed: __async__ void check_unlocks(object channel, string varname, string newval) {
	mapping cfg = await(G->G->DB->load_config(channel->userid, "unlocks"));
	if (varname != "$" + cfg->varname + "$") return;
	send_updates_all(channel, "");
	send_updates_all(channel, "control");
}

protected void create(string name) {::create(name);}
