inherit http_websocket;

constant markdown = #"# Unlocks!

<p id=nextunlock></p>

Click to view these gorgeous pics fullscreen.

* loading...
{:#unlocks}

[Manage unlocks](:.opendlg data-dlg=managedlg .modonly hidden=true)

> ### Manage unlocks
>
> <label>Select variable: <select class=config name=varname></select></label>
> <label>Display format: <select class=config name=format>
> <option value=plain>plain</option>
> <option value=currency>currency eg $27.18</option>
> <option value=subscriptions>subscriptions</option>
> </select></label>
>
> * loading...
> {:#allunlocks}
>
> <div class=uploadtarget></div>
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
</style>
";

array configs = ({"varname", "format"});

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	return render(req, (["vars": ([
			"ws_group": req->misc->is_mod ? "control" : "",
		]),
	]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return grp == "control";}
__async__ mapping get_chan_state(object channel, string grp, string|void id) {
	mapping cfg = await(G->G->DB->load_config(channel->userid, "unlocks"));
	if (!cfg->varname) return ([]);
	array unlocks = cfg->unlocks || ({ });
	sort(-unlocks->threshold[*], unlocks); //Put the newest unlocks at the top
	int curval = (int)channel->expand_variables("$" + cfg->varname + "$");
	mapping ret = ([
		"unlocks": filter(unlocks) {return curval >= __ARGS__[0]->threshold;},
	]);
	int nextval = 0;
	//Find the next unlock. Since they're sorted descending, we just grab any we see, last one wins.
	foreach (unlocks, mapping unl) if (unl->threshold > curval) nextval = unl->threshold;
	ret->nextval = nextval;
	if (grp == "control") {
		ret->allunlocks = unlocks;
		foreach (configs, string c) ret[c] = cfg[c] || "";
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

@"is_mod": __async__ mapping wscmd_add_unlock(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	await(G->G->DB->mutate_config(channel->userid, "unlocks") {mapping cfg = __ARGS__[0];
		cfg->unlocks += ({(["id": ++cfg->nextid, "threshold": 1<<30])});
	});
	send_updates_all(channel, "");
	send_updates_all(channel, "control");
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
			if ((int)msg->threshold) unl->threshold = (int)msg->threshold;
			//NOTE: The file ID currenly cannot be edited. Should it be able to be?
			//Alternatively, should there be a way to select an existing file to make into an unlock?
			if (msg->caption) unl->caption = msg->caption;
		}
	});
	send_updates_all(channel, "");
	send_updates_all(channel, "control");
}

@"is_mod": __async__ void wscmd_config(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	await(G->G->DB->mutate_config(channel->userid, "unlocks") {mapping cfg = __ARGS__[0];
		foreach (configs, string c) if (msg[c]) cfg[c] = msg[c];
	});
	send_updates_all(channel, "");
	send_updates_all(channel, "control");
}

//As with chan_monitors, the functionality for uploads is being lifted from alertbox (which comes
//alphabetically prior to this file). May be of value to refactor this at some point.
@"is_mod": __async__ mapping|zero wscmd_upload(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping|zero resp = await(G->G->websocket_types->chan_alertbox->wscmd_upload(channel, conn, msg));
	if (resp->?cmd == "upload") {
		//Add the unlock immediately, without waiting for completion of the upload
		await(G->G->DB->mutate_config(channel->userid, "unlocks") {mapping cfg = __ARGS__[0];
			cfg->unlocks += ({([
				"id": ++cfg->nextid, "threshold": 1<<30,
				"fileid": resp->id,
			])});
		});
		send_updates_all(channel, "control");
		//Note that we don't bother sending to the view-only group. If this has, in fact, been unlocked,
		//we'll know once the threshold gets updated.
	}
	return resp;
}
