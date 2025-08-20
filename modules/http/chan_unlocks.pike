inherit annotated;
inherit hook;
inherit http_websocket;

constant markdown = #"# Unlocks!

* loading...
{:#unlocks}

[Manage unlocks](:.opendlg data-dlg=managedlg .modonly hidden=true)

> ### Manage unlocks
>
> <label>Select variable: <select id=varname></select></label>
>
> * loading...
> {:#allunlocks}
>
> [Add](:#addunlock)
>
> [Close](:.dialog_close)
{: tag=formdialog #managedlg}

<style>
#unlocks {
	list-style-type: none;
	padding: 0;
}
</style>
";

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	return render(req, (["vars": ([
			"ws_group": req->misc->is_mod ? "control" : "",
		]),
	]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return grp == "control";}
__async__ mapping get_chan_state(object channel, string grp, string|void id) {
	mapping cfg = await(G->G->DB->load_config(channel->userid, "unlocks"));
	array unlocks = cfg->unlocks || ({ });
	mapping ret = ([
		"unlocks": filter(unlocks) {return 1;}, //TODO: Check if unlocked
	]);
	if (grp == "control") {
		ret->allunlocks = unlocks;
		ret->varname = cfg->varname;
	}
	return ret;
}

@"is_mod": __async__ mapping wscmd_add_unlock(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	await(G->G->DB->mutate_config(channel->userid, "unlocks") {mapping cfg = __ARGS__[0];
		cfg->unlocks += ({([])});
	});
	send_updates_all(channel, "");
	send_updates_all(channel, "control");
}

@"is_mod": __async__ void wscmd_delete_unlock(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	await(G->G->DB->mutate_config(channel->userid, "unlocks") {mapping cfg = __ARGS__[0];
		//TODO: Delete by index
	});
	send_updates_all(channel, "");
	send_updates_all(channel, "control");
}

@"is_mod": __async__ void wscmd_config(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	await(G->G->DB->mutate_config(channel->userid, "unlocks") {mapping cfg = __ARGS__[0];
		if (msg->varname) cfg->varname = msg->varname;
	});
	send_updates_all(channel, "");
	send_updates_all(channel, "control");
}

@hook_variable_changed: void check_unlocks(object channel, string var, string newval) {
}

protected void create(string name) {::create(name);}
