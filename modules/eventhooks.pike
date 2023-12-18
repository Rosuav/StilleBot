//Twitch's EventSub chaining into special triggers
inherit annotated;

//For each special, list the scopesets it requires, separated with pipes.
//If any listed scopeset is present, the special is considered available. If none are,
//the first scopeset will be used for the authenticate button. Note that this does not
//support "moderator auth", which can be used for follower lookups; as a simplification,
//we support either "broadcaster auth" or "bot intrinsic mod auth" but no other mods.
//A "scopeset" is a blank-delimited set of scopes which must ALL be present. Most often,
//a single scope will be sufficient. Question: Should there be support for *optional*
//scopesets, which could be granted in order to enhance functionality in some way?

//NOTE: To actually add the special triggers, update modules/addcmd.pike and ensure that
//the parameters are all listed correctly. The scopes are automatically provided by this
//file but the special and its description come from addcmd.

//The annotation has three required parts, the scopes (pipe delimited - any is acceptable),
//the subscription type, and the version. An optional fourth parameter provides some blank
//delimited flags, which have the following meanings:
//always  - Create this hook even if the corresponding special does not exist. Useful if the
//          hook provides other functionality than simply executing the special.
//modular - This hook, possibly as part of a set of hooks, can be activated by some other
//          module, even with the bot not being active in the channel. See details in
//          specials_check_modular_hooks. Hooks are identified by name, or by group, with
//          the latter being identified by an additional flag (not listed in this table).
//uid     - Use the broadcaster user ID as the hook parameter
//login   - Use the broadcaster login as the hook parameter (currently the default)

@({"channel:read:polls|channel:manage:polls", "channel.poll.begin", "1"}):
mapping pollbegin(object channel, mapping info) {
	if (mapping cfg = info->__condition) return (["broadcaster_user_id": (string)cfg->userid]);
	mapping params = ([
		"{title}": info->title,
		"{choices}": (string)sizeof(info->choices),
		"{points_per_vote}": (string)(info->channel_points_voting->enabled && info->channel_points_voting->amount_per_vote),
	]);
	foreach (info->choices; int i; mapping ch)
		params["{choice_" + (i+1) + "_title}"] = ch->title;
	return params;
}

@retain: multiset polls_ended = (<>); //Twitch sends me double notifications. Suppress the duplicates.
@({"channel:read:polls|channel:manage:polls", "channel.poll.end", "1"}):
mapping pollended(object channel, mapping info) {
	if (mapping cfg = info->__condition) return (["broadcaster_user_id": (string)cfg->userid]);
	if (polls_ended[info->id]) return 0;
	polls_ended[info->id] = 1;
	mapping params = pollbegin(channel, info);
	int top = 0;
	foreach (info->choices; int i; mapping ch) {
		string pfx = "{choice_" + (i+1) + "_";
		params[pfx + "votes}"] = (string)ch->votes;
		params[pfx + "pointsvotes}"] = (string)ch->channel_points_votes;
		if (ch->votes > info->choices[top]->votes) top = i;
	}
	params["{winner_title}"] = info->choices[top]->title;
	return params;
}

@({"channel:read:predictions|channel:manage:predictions", "channel.prediction.lock", "1"}):
mapping predictionlocked(object channel, mapping info) {
	if (mapping cfg = info->__condition) return (["broadcaster_user_id": (string)cfg->userid]);
	mapping params = ([
		"{title}": info->title,
		"{choices}": (string)sizeof(info->outcomes),
		"{status}": info->status, //"resolved" or "canceled"
	]);
	foreach (info->outcomes; int i; mapping ch) {
		string pfx = "{choice_" + (i+1) + "_";
		params[pfx + "title}"] = ch->title;
		params[pfx + "users}"] = (string)ch->users;
		params[pfx + "points}"] = (string)ch->channel_points;
		foreach (ch->top_predictors; int j; mapping person) {
			string pfx = pfx + "top_" + (j+1) + "_";
			params[pfx + "user}"] = person->user_name;
			params[pfx + "userid}"] = person->user_id;
			params[pfx + "points_used}"] = (string)person->channel_points_used;
			params[pfx + "points_won}"] = (string)person->channel_points_won; //0 if you were on the losing side
		}
	}
	return params;
}

@({"channel:read:predictions|channel:manage:predictions", "channel.prediction.end", "1"}):
mapping predictionended(object channel, mapping info) {
	if (mapping cfg = info->__condition) return (["broadcaster_user_id": (string)cfg->userid]);
	mapping params = predictionlocked(channel, info);
	params["{status}"] = info->status; //"resolved" or "canceled"
	string winner_pfx, loser_pfx;
	foreach (info->outcomes; int i; mapping ch) {
		string pfx = "{choice_" + (i+1) + "_";
		if (ch->id == info->winning_outcome_id) winner_pfx = pfx;
		else if (sizeof(info->outcomes) == 2) loser_pfx = pfx;
	}
	if (winner_pfx) foreach (params; string kwd; string val)
		if (has_prefix(kwd, winner_pfx)) params["{winner_" + kwd - winner_pfx] = val;
	if (loser_pfx) foreach (params; string kwd; string val)
		if (has_prefix(kwd, loser_pfx)) params["{loser_" + kwd - loser_pfx] = val;
	return params;
}

@({"channel:read:ads", "channel.ad_break.begin", "1", "always"}):
mapping adbreak(object channel, mapping info) {
	if (mapping cfg = info->__condition) return (["broadcaster_user_id": (string)cfg->userid]);
	spawn_task(G->G->websocket_types->chan_snoozeads->check_stats(channel));
	return ([
		"{length}": (string)info->duration_seconds,
		"{is_automatic}": info->is_automatic ? "1" : "0",
		"{started_at_iso}": info->started_at, //TODO
	]);
}

mapping hypetrain(string hook, object channel, mapping info) {
	if (mapping cfg = info->__condition) return (["broadcaster_user_id": (string)cfg->userid]);
	G->G->websocket_types->hypetrain->hypetrain_progression(hook, "", info);
	return ([]); //TODO: Provide information. For now, just use the builtin.
}

@({"channel:read:hype_train", "channel.hype_train.begin", "1", "uid modular hypetrain"}):
mapping hypetrain_begin(object channel, mapping info) {return hypetrain("begin", channel, info);}
@({"channel:read:hype_train", "channel.hype_train.progress", "1", "uid modular hypetrain"}):
mapping hypetrain_progress(object channel, mapping info) {return hypetrain("progress", channel, info);}
@({"channel:read:hype_train", "channel.hype_train.end", "1", "uid modular hypetrain"}):
mapping hypetrain_end(object channel, mapping info) {return hypetrain("end", channel, info);}

mapping eventsubs = ([]);

//Ensure that we have all appropriate hooks for this channel (provide channel->config or equivalent)
void specials_check_hooks(mapping cfg) {
	string chan = cfg->login;
	multiset scopes = (multiset)(token_for_user_login(chan)[1] / " "); //TODO: Switch to user ID to ensure this remains synchronous
	foreach (G->G->SPECIALS_SCOPES; string special; array scopesets) {
		foreach (scopesets, array scopeset) {
			if (!has_value(scopes[scopeset[*]], 0)) { //If there isn't any case of a scope that we don't have... then we have them all!
				multiset flg = eventsubs[special]->flags;
				if (cfg->commands[?"!" + special] //If there's a special of this name, we need the hook.
						|| flg->always) //If the eventsub has other functionality, we need the hook.
					eventsubs[special](flg->uid ? (string)cfg->userid : chan, this[special](0, (["__condition": cfg])));
				break;
			}
		}
	}
}

//Check for the specific modular hooks needed. Specify the group either as a hook name, or
//a flag that all the interesting hooks will have. The given config mapping MUST have a
//userid attribute; anything else is not guaranteed and is negotiated by the caller and
//hook function. If the hook has the 'login' flag (and not the 'uid' flag), cfg must also
//include a login. (For now, ALWAYS include login, but that will become optional once
//tokens are tied to IDs instead of logins.)
void specials_check_modular_hooks(mapping cfg, string group) {
	string login = cfg->login, uid = (string)cfg->userid;
	multiset scopes = (multiset)(token_for_user_login(cfg->login)[1] / " "); //TODO: Switch to user ID to ensure this remains synchronous
	foreach (G->G->SPECIALS_SCOPES; string special; array scopesets) {
		multiset flg = eventsubs[special]->flags;
		if (!flg->modular) continue;
		foreach (scopesets, array scopeset) {
			if (!has_value(scopes[scopeset[*]], 0)) { //If there isn't any case of a scope that we don't have... then we have them all!
				if (special == group || flg[group])
					eventsubs[special](flg->uid ? uid : login, this[special](0, (["__condition": cfg])));
				break;
			}
		}
	}
}

class EventSubSpecial(function get_params) {
	inherit EventSub;
	multiset flags = (<>);
	protected void create(string hookname, string type, string version, string|void flg) {
		::create(hookname, type, version, send_special);
		if (flg) foreach (flg / " ", string f) flags[f] = 1;
	}
	void send_special(string chan, mapping info) {
		object channel = G->G->irc->channels["#" + chan];
		if (!channel) return;
		mapping params = get_params(channel, info);
		if (params) channel->trigger_special("!" + hookname, ([
			"user": chan,
			"displayname": channel->config->display_name,
			"uid": channel->userid,
		]), params);
	}
}

protected void create(string name) {
	::create(name);
	G->G->SPECIALS_SCOPES = ([]);
	foreach (Array.transpose(({indices(this), annotations(this)})), [string key, mixed ann]) {
		if (ann) foreach (indices(ann), mixed anno) {
			if (arrayp(anno)) {
				G->G->SPECIALS_SCOPES[key] = (anno[0] / "|")[*] / " ";
				eventsubs[key] = EventSubSpecial(this[key], key, @anno[1..]);
			}
		}
	}
	specials_check_hooks(list_channel_configs()[*]);
	G->G->specials_check_hooks = specials_check_hooks;
	G->G->specials_check_modular_hooks = specials_check_modular_hooks;
}
