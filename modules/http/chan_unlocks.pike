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
	if (!cfg->varname) return ([]);
	array unlocks = cfg->unlocks || ({ });
	int curval = (int)channel->expand_variables("$" + cfg->varname + "$");
	mapping ret = ([
		"unlocks": filter(unlocks) {return curval >= __ARGS__[0]->threshold;},
	]);
	if (grp == "control") {
		ret->allunlocks = unlocks;
		ret->varname = cfg->varname;
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
		cfg->unlocks += ({([])});
	});
	send_updates_all(channel, "");
	send_updates_all(channel, "control");
}

@"is_mod": __async__ void wscmd_delete_unlock(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	await(G->G->DB->mutate_config(channel->userid, "unlocks") {mapping cfg = __ARGS__[0];
		//TODO: Delete by index
		cfg->unlocks = ({});
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
