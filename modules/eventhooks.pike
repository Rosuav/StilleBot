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

//The annotation has three parts, the scopes (pipe delimited - any is acceptable),
//the subscription type, and the version.

@({"channel:read:polls|channel:manage:polls", "channel.poll.begin", "1"}):
mapping pollbegin(object channel, mapping info) {
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

@({"channel:read:ads", "channel.ad_break.begin", "1"}):
mapping adbreak(object channel, mapping info) {
	return ([
		"{length}": (string)info->duration_seconds,
		"{is_automatic}": info->is_automatic ? "1" : "0",
		"{started_at_iso}": info->started_at, //TODO
	]);
}

@retain: mapping(int:int) last_seen_hype_level = ([]);
mapping hypetrain(string hook, object channel, mapping info) {
	string levelup = "";
	if (hook == "begin" || (int)info->level != last_seen_hype_level[channel->userid]) {
		if ((int)info->level > 1) levelup = (string)((int)info->level - 1); //The level achieved
		last_seen_hype_level[channel->userid] = (int)info->level;
	}
	return ([
		"{levelup}": levelup,
	]);
}

@({"channel:read:hype_train", "channel.hype_train.begin", "1"}):
mapping hypetrain_begin(object channel, mapping info) {return hypetrain("begin", channel, info);}
@({"channel:read:hype_train", "channel.hype_train.progress", "1"}):
mapping hypetrain_progress(object channel, mapping info) {return hypetrain("progress", channel, info);}
@({"channel:read:hype_train", "channel.hype_train.end", "1"}):
mapping hypetrain_end(object channel, mapping info) {return hypetrain("end", channel, info);}

mapping eventsubs = ([]); //Map the special name (== function name) to the hook type/version for convenience

//Ensure that we have all appropriate hooks for this channel
void specials_check_hooks(object channel) {
	multiset scopes = (multiset)(token_for_user_login(channel->config->login)[1] / " "); //TODO: Switch to user ID to ensure this remains synchronous
	foreach (G->G->SPECIALS_SCOPES; string special; array scopesets) {
		foreach (scopesets, array scopeset) {
			if (!has_value(scopes[scopeset[*]], 0)) { //If there isn't any case of a scope that we don't have... then we have them all!
				if (channel->commands[?"!" + special])
					G->G->establish_hook_notification(channel->userid, eventsubs[special]);
				break;
			}
		}
	}
}

void specials_check_hooks_all_channels(int warn) {
	if (sizeof(G->G->irc->loading)) {
		//We're still loading some or all channels. Give 'em a few seconds.
		if (warn) werror("WARNING: Unable to check for special hooks - still loading: %O\n", G->G->irc->loading);
		call_out(specials_check_hooks_all_channels, 5, 1);
	}
	else specials_check_hooks(values(G->G->irc->id)[*]);
}

function make_eventhook_handler(string hookname) {
	return lambda(object channel, mapping info) {
		mapping params = channel && this[hookname](channel, info);
		if (params) channel->trigger_special("!" + hookname, ([
			"user": channel->login,
			"displayname": channel->config->display_name,
			"uid": channel->userid,
		]), params);
	};
}

protected void create(string name) {
	::create(name);
	G->G->SPECIALS_SCOPES = ([]);
	foreach (Array.transpose(({indices(this), annotations(this)})), [string key, mixed ann]) {
		if (ann) foreach (indices(ann), mixed anno) {
			if (arrayp(anno)) {
				G->G->SPECIALS_SCOPES[key] = (anno[0] / "|")[*] / " ";
				string hook = anno[1] + "=" + anno[2];
				eventsubs[key] = hook;
				if (!G->G->eventhooks[hook]) G->G->eventhooks[hook] = ([]);
				G->G->eventhooks[hook][name] = make_eventhook_handler(key);
			}
		}
	}
	specials_check_hooks_all_channels(0);
	G->G->specials_check_hooks = specials_check_hooks;
}
