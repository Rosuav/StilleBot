inherit http_websocket;
inherit hook;
inherit annotated;
constant markdown = #"# Giveaway - $$giveaway_title||win things with channel points$$

<div id=errormessage class=hidden></div>

<div id=master_status>$$error||Loading giveaway status...$$</div>

<ul id=ticketholders></ul>

$$login$$

> <summary>Set up rewards</summary>
>
> <form id=configform>
>
> - | - | -
> --|---|--
> <label for=ga_title>Giveaway title</label> | <input id=ga_title name=title size=40 placeholder=\"an awesome thing\"> | What are people winning?
> <label for=ga_cost>Cost per ticket</label> | <input id=ga_cost name=cost type=number min=1 value=1></label> | Loyal viewers can earn a thousand points in a 2-3 hour stream. [See details.](https://help.twitch.tv/s/article/channel-points-guide)
> <label for=ga_desc>Description</label> | <input id=ga_desc name=desc size=40 maxlength=40 placeholder=\"Buy # tickets\"> | Put a <code>#</code> symbol for multibuy count
> <label for=ga_multi>Multibuy options</label> | <input id=ga_multi name=multi size=40 placeholder=\"1 5 10 25 50\"> | Allow people to buy tickets in these quantities. If omitted, you'll get 1, 10, 100, 1000, etc.
> <label for=ga_max>Max tickets</label> | <input id=ga_max name=max type=number min=0 value=0> | Purchases that would put you over this limit will be cancelled
> <label for=ga_pausemode>Redemption hiding</label> | <select id=ga_pausemode name=pausemode><option value=disable>Disable, hiding them from users</option><option value=pause>Pause and leave visible</option></select> | When there's no current giveaway, should redemptions remain visible (but unpurchaseable), or vanish entirely?
> Multi-win | <label><input type=checkbox name=allow_multiwin value=yes> Allow one person to win multiple times</label> | By default, the winner's tickets will be removed in case of a reroll or second winner.
> <label for=ga_duration>Time before giveaway closes</label> | <input id=ga_duration name=duration type=number min=0 max=3600> (seconds) | How long should the giveaway be open? 0 leaves it until explicitly closed.
> Non-binding purchases | <label><input type=checkbox name=refund_nonwinning value=yes> Refund non-winning tickets at end of giveaway</label> | By default, all ticket purchases are counted as claimed (channel points spent) when the giveaway is ended.
>
> <button>Save/reconfigure</button>
>
> Giveaway notifications are handled through [special triggers](specials#Giveaways) and can be customized there.<br>
> [Create default notifications (replacing existing ones)](: #makenotifs)
>
> To allow users to check and/or refund their tickets via chat, two commands are available.
> [Activate](:#activatecommands) [Deactivate](:#deactivatecommands)
> <code>!tickets</code>, <code>!refund</code>.
>
> </form>
{: tag=details .modonly}

[Master Control](:.opendlg data-dlg=master)
{: .modonly}

> ### Master Control
> * [Open giveaway](:.master #open) and allow people to buy tickets
> * [Close giveaway](:.master #close) so no more tickets will be bought
> * [Rig giveaway](:.master #rig) because everyone knows we always do that
> * [Choose winner](:.master #pick) and remove that person's tickets
> * [Cancel and refund](:.master #cancel) all points spent on tickets
> * [End giveaway](:.master #end) <span id=refund_nonwinning_desc>clearing out</span> tickets
>
{: tag=dialog #master}

<style>
details {border: 1px solid black; padding: 0.5em; margin: 0.5em;}
#master li {
	margin-top: 0.5em;
	margin-right: 40px;
	list-style-type: none;
}
#master li.next {list-style-type: \"=> \";}
#master li.next::marker {font-weight: bold;}
#master_status {
	width: 350px;
	background: aliceblue;
	border: 3px solid blue;
	margin: auto;
	padding: 1em;
	font-size: 125%;
}
#master_status.is_open {
	background: #a0f0c0;
	border-color: green;
}
#master_status h3 {
	font-size: 125%;
	margin: 0 auto 0.5em;
}
.winner_name {
	background-color: #ffe;
	font-weight: bold;
}
.modonly {$$modonly||display: none$$;}
#errormessage {
	background: #fdd;
	border: 3px solid red;
	max-width: fit-content;
	padding: 5px;
	margin: 10px;
}
.hidden {display: none;}
</style>
";

inherit builtin_command;
constant visibility = "hidden";
constant access = "none";
@retain: mapping giveaway_tickets = ([]);
@retain: mapping giveaway_rigged = ([]); //Map a channel ID to its rigged status (if non-null, the giveaway was rigged by that mod)
@retain: multiset giveaway_purchases = (<>);

constant giveaway_started = special_trigger("!giveaway_started", "A giveaway just opened, and people can buy tickets", "The broadcaster", "title, duration, duration_hms, duration_english", "Giveaways");
constant giveaway_ticket = special_trigger("!giveaway_ticket", "Someone bought ticket(s) in the giveaway", "Ticket buyer", "title, tickets_bought, tickets_total, tickets_max", "Giveaways");
constant giveaway_toomany = special_trigger("!giveaway_toomany", "Ticket purchase attempt failed", "Ticket buyer", "title, tickets_bought, tickets_total, tickets_max", "Giveaways");
constant giveaway_closed = special_trigger("!giveaway_closed", "The giveaway just closed; people can no longer buy tickets", "The broadcaster", "title, tickets_total, entries_total", "Giveaways");
constant giveaway_winner = special_trigger("!giveaway_winner", "A giveaway winner has been chosen!", "The broadcaster", "title, winner_name, winner_tickets, tickets_total, entries_total", "Giveaways");
constant giveaway_ended = special_trigger("!giveaway_ended", "The giveaway is fully concluded and all ticket purchases are nonrefundable.", "The broadcaster", "title, tickets_total, entries_total, giveaway_cancelled", "Giveaways");

constant NOTIFICATION_SPECIALS = ([
	"started": "A giveaway for {title} is now open - use your channel points to purchase tickets!",
	"toomany": ([
		"conditional": "string", "expr1": "{tickets_max}", "expr2": "1",
		"message": ([
			"conditional": "string", "expr1": "{tickets_total}", "expr2": "0",
			"message": "$$: You can't buy {tickets_bought} tickets - maximum is 1.",
			"otherwise": "$$: You already have a ticket and your points have been refunded.",
		]),
		"otherwise": ([
			"conditional": "string", "expr1": "{tickets_total}", "expr2": "0",
			"message": "$$: Can't buy {tickets_bought} tickets - the maximum is {tickets_max}",
			"otherwise": "$$: Can't buy {tickets_bought} tickets as you already have {tickets_total} (max {tickets_max})",
		])
	]),
	"winner": "Congratulations to {winner_name} for winning the {title}!",
]);

Concurrent.Future set_redemption_status(mapping redem, string status) {
	return complete_redemption(redem->broadcaster_login || redem->broadcaster_user_login,
		redem->reward->id, redem->id, status);
}

__async__ void update_ticket_count(mapping givcfg, mapping redem, int|void removal) {
	mapping values = givcfg->?rewards || ([]);
	if (!values[redem->reward->id]) return; //No value assigned to this reward, so it's presumably not a giveaway ticket redemption
	string chan = redem->broadcaster_login || redem->broadcaster_user_login;
	mapping people = giveaway_tickets[chan];
	if (!people) people = giveaway_tickets[chan] = ([]);
	if (!people[redem->user_id]) people[redem->user_id] = ([
		"name": redem->user_name,
		"position": sizeof(people) + 1, //First person to buy a ticket gets position 1
		"redemptions": ([]), //Map redemption IDs to their info.
		"tickets": 0, //== sum(values[redemptions->reward->id[*]])
	]);
	mapping person = people[redem->user_id];
	if (removal == !person->redemptions[redem->id]) ; //Already (not) there, do nothing.
	else if (removal) {
		m_delete(person->redemptions, redem->id);
		person->tickets -= values[redem->reward->id];
	}
	else {
		int now = person->tickets + values[redem->reward->id];
		int max = givcfg->max_tickets || (1<<100); //Hack: Max max tickets is a big number, not infinite. Whatever.
		int too_late = 0;
		if (!givcfg->is_open) {
			//If anything snuck in while we were closing the giveaway, refund it as soon as we notice.
			too_late = 1;
			if (givcfg->last_opened < givcfg->last_closed) {
				//It's possible that the giveaway was recently closed, and that you bought tickets
				//while it was open. If so, honour those purchases.
				int redemption_time = time_from_iso(redem->redeemed_at)->unix_time();
				if (givcfg->last_opened <= redemption_time && redemption_time <= givcfg->last_closed)
					too_late = 0;
			}
		}
		if ((too_late || now > max) && !giveaway_purchases[redem->id]) {
			//If we previously saw this as acceptable, don't refund it.
			//This means that if you change the max tickets during a giveaway, any excess will
			//still be kept, unless/until they get explicitly refunded.
			set_redemption_status(redem, "CANCELED")->then(lambda(mixed resp) {
				catch {
					object ts = time_from_iso(redem->redeemed_at);
					int redemption_time = ts->unix_time();
					array timestamps = ({redemption_time, givcfg->last_opened, givcfg->last_closed});
					array ts_labels = ({"Bought", "Opened", "Closed"});
					sort(timestamps, ts_labels);
					foreach (timestamps; int i; int ts)
						write("%s: %d (%+d)\n", ts_labels[i], ts, ts - time());
				};
				write("Cancelled (%d/%d): %O\n", now, max, resp);
				object channel = G->G->irc->channels["#" + chan];
				//If max is zero, you were probably too late. Should there be a different message?
				if (max) channel->trigger_special("!giveaway_toomany", (["user": redem->user_name]), ([
					"{title}": givcfg->title || "",
					"{tickets_bought}": (string)values[redem->reward->id],
					"{tickets_total}": (string)person->tickets,
					"{tickets_max}": (string)givcfg->max_tickets,
				]));
			});
		}
		else {
			person->tickets = now;
			person->redemptions[redem->id] = redem;
			if (!giveaway_purchases[redem->id]) {
				//Only announce a given purchase once, even if we do a full recalc of giveaway_tickets
				giveaway_purchases[redem->id] = 1;
				object channel = G->G->irc->channels["#" + chan];
				write("GIVEAWAY: %s bought %d, now %d/%d\n", redem->user_name,
					values[redem->reward->id], now, givcfg->max_tickets);
				channel->trigger_special("!giveaway_ticket", (["user": redem->user_name]), ([
					"{title}": givcfg->title || "",
					"{tickets_bought}": (string)values[redem->reward->id],
					"{tickets_total}": (string)now,
					"{tickets_max}": (string)givcfg->max_tickets,
				]));
			}
		}
	}
}

array tickets_in_order(string chan) {
	array tickets = ({ });
	foreach (giveaway_tickets[chan] || ([]); ; mapping person)
		if (person->tickets) tickets += ({person});
	sort(tickets->position, tickets);
	return tickets;
}

//Send an update based on cached data rather than forcing a full recalc every time
void notify_websockets(int chan, string channame, mapping givcfg) { //TODO: Drop the second param
	send_updates_all("control#" + chan, ([
		"tickets": tickets_in_order(channame),
		"last_opened": givcfg->last_opened, "last_closed": givcfg->last_closed,
		"is_open": givcfg->is_open, "end_time": givcfg->end_time,
		"last_winner": givcfg->last_winner,
	]));
	send_updates_all("view#" + chan, ([
		"last_opened": givcfg->last_opened, "last_closed": givcfg->last_closed,
		"is_open": givcfg->is_open, "end_time": givcfg->end_time,
		"last_winner": givcfg->last_winner,
	]));
}

@hook_point_redemption:
__async__ void redemption(object channel, string rewardid, int(0..1) refund, mapping data) {
	mapping givcfg = await(G->G->DB->load_config(channel->userid, "giveaways"));
	await(update_ticket_count(givcfg, data, refund));
	notify_websockets(channel->userid, channel->config->login, givcfg);
}

//List all redemptions for a particular reward ID
Concurrent.Future list_redemptions(int broadcaster_id, string chan, string id) {
	return get_helix_paginated("https://api.twitch.tv/helix/channel_points/custom_rewards/redemptions",
		([
			"broadcaster_id": (string)broadcaster_id,
			"reward_id": id,
			"status": "UNFULFILLED",
			"first": "50",
		]),
		(["Authorization": "Bearer " + token_for_user_login(chan)[0]]), //TODO: Switch to user_id once that's the fundamental
	);
}

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	mapping givcfg = await(G->G->DB->load_config(req->misc->channel->userid, "giveaways"));
	mapping cfg = req->misc->channel->config;
	string chan = req->misc->channel->name[1..];
	string login = "[Broadcaster login](:.twitchlogin data-scopes=channel:manage:redemptions)";
	if (string scopes = chan != "!demo" && ensure_bcaster_token(req, "channel:manage:redemptions")) return render(req, ([
		"error": "This page will become available once the broadcaster has logged in and configured redemptions.",
		"login": "[Broadcaster login](:.twitchlogin data-scopes=" + replace(scopes, " ", "%20") + ")",
	]) | req->misc->chaninfo);
	login += " [Mod login](:.twitchlogin)"; //TODO: If logged in as wrong user, allow logout
	mapping config = ([]);
	config->title = givcfg->title || ""; //Give this one even to non-mods
	if (req->misc->is_mod) {
		config->cost = givcfg->cost || 1;
		config->max = givcfg->max_tickets;
		config->desc = givcfg->desc_template || "";
		config->pausemode = givcfg->pausemode ? "pause" : "disable";
		config->allow_multiwin = givcfg->allow_multiwin ? "yes" : "no";
		config->duration = givcfg->duration;
		config->refund_nonwinning = givcfg->refund_nonwinning ? "yes" : "no";
		//TODO: Show the actual existing rewards somewhere?
		//if (mapping existing = g->rewards)
		//	config->multi = ((array(string))sort(values(existing))) * " ";
		//else config->multi = "";
		config->multi = givcfg->multibuy;
	}
	return render(req, ([
		"vars": (["ws_group": req->misc->is_mod ? "control" : "view", "config": config]),
		"giveaway_title": givcfg->title, //Prepopulate the heading and the page title so it doesn't have to load and redraw
		"modonly": req->misc->is_mod && "",
		"login": req->misc->is_mod ? "" : login,
	]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return grp == "control";}
__async__ mapping get_chan_state(object channel, string grp)
{
	string chan = channel->name[1..];
	mapping givcfg = await(G->G->DB->load_config(channel->userid, "giveaways"));
	if (grp == "view") return ([
		"title": givcfg->?title,
		"is_open": givcfg->is_open, "end_time": givcfg->end_time,
		"last_winner": givcfg->last_winner,
	]);
	if (grp != "control") return 0;
	array rewards = ({ });
	if (mixed ex = chan != "!demo" && catch {rewards = await(twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?only_manageable_rewards=true&broadcaster_id=" + channel->userid,
		(["Authorization": "Bearer " + token_for_user_id(channel->userid)[0]])))->data;
	}) {
		if (arrayp(ex) && stringp(ex[0]) && has_value(ex[0], "Error from Twitch") && has_value(ex[0], "401")) {
			return (["error": "Unable to list channel rewards, may need reauthentication"]);
		}
		werror("Unexpected error listing channel rewards: %s\n", describe_backtrace(ex));
		return 0;
	}
	array(array) redemptions = chan == "!demo" ? ({ }) : await(Concurrent.all(list_redemptions(channel->userid, chan, rewards->id[*])));
	//Every time a new websocket is established, fully recalculate. Guarantee fresh data.
	giveaway_tickets[chan] = ([]);
	foreach (redemptions * ({ }), mapping redem) await(update_ticket_count(givcfg, redem));
	return ([
		"title": givcfg->?title,
		"rewards": rewards, "tickets": tickets_in_order(chan),
		"is_open": givcfg->is_open, "end_time": givcfg->end_time,
		"last_winner": givcfg->last_winner,
		"can_activate": !channel->commands->tickets || !channel->commands->refund,
		"can_deactivate": channel->commands->tickets || channel->commands->refund,
	]);
}

@"is_mod": __async__ void wscmd_masterconfig(object channel, mapping(string:mixed) conn, mapping(string:mixed) body) {
	int cost = (int)body->cost; if (cost <= 0) return; //That'd just be silly :)
	mapping givcfg = await(G->G->DB->load_config(channel->userid, "giveaways"));
	array qty = (array(int))(replace(body->multi || "1 10 100 1000 10000 100000 1000000", ",", " ") / " ") - ({0});
	if (!has_value(qty, 1)) qty = ({1}) + qty;
	givcfg->title = body->title;
	if (int max = givcfg->max_tickets = (int)body->max)
		qty = filter(qty) {return __ARGS__[0] <= max;};
	givcfg->desc_template = body->desc;
	givcfg->multibuy = body->multi;
	givcfg->cost = cost;
	givcfg->pausemode = body->pausemode == "pause";
	givcfg->allow_multiwin = body->allow_multiwin == "yes";
	givcfg->duration = min(max((int)body->duration, 0), 3600);
	givcfg->refund_nonwinning = body->refund_nonwinning == "yes";
	mapping existing = givcfg->rewards;
	if (!existing) existing = givcfg->rewards = ([]);
	int numcreated = 0, numupdated = 0, numdeleted = 0;
	Concurrent.Future call(string method, string query, mixed body) {
		return twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id=" + channel->userid + "&" + query,
			(["Authorization": channel->userid]),
			(["method": method, "json": body, "return_status": !body]),
		);
	}
	//Prune any that we no longer need
	foreach (existing; string id; int tickets) {
		if (!has_value(qty, tickets)) {
			m_delete(existing, id);
			++numdeleted;
			await(call("DELETE", "id=" + id, 0));
		}
		else {
			++numupdated;
			if (catch (await(call("PATCH", "id=" + id, ([
				"title": replace(body->desc || "Buy # tickets", "#", (string)tickets),
				"cost": cost * tickets,
				"is_enabled": givcfg->is_open || givcfg->pausemode,
				"is_paused": !givcfg->is_open && givcfg->pausemode,
			]))))) {m_delete(existing, id); continue;} //And let it get recreated
		}
		qty -= ({tickets});
	}
	//Create any that we don't yet have
	foreach (qty, int tickets) {
		mapping info = await(call("POST", "", ([
			"title": replace(body->desc || "Buy # tickets", "#", (string)tickets),
			"cost": cost * tickets,
			"is_enabled": givcfg->is_open || givcfg->pausemode,
			"is_paused": !givcfg->is_open && givcfg->pausemode,
		])));
		existing[info->data[0]->id] = tickets;
		++numcreated;
	}
	await(G->G->DB->save_config(channel->userid, "giveaways", givcfg));
	send_updates_all(channel, "control", (["title": givcfg->title]));
	send_updates_all(channel, "view", (["title": givcfg->title]));
}

mapping(string:mixed) autoclose = ([]);
__async__ void open_close(string chan, int broadcaster_id, int want_open) {
	mapping givcfg = await(G->G->DB->load_config(broadcaster_id, "giveaways", 0));
	if (!givcfg) return; //No rewards, nothing to open/close
	string token = token_for_user_login(chan)[0];
	if (!token) {werror("Can't open/close giveaway w/o bcaster token\n"); return;}
	givcfg->is_open = want_open;
	givcfg[want_open ? "last_opened" : "last_closed"] = time();
	if (mixed id = m_delete(autoclose, chan)) remove_call_out(id);
	if (int d = want_open && givcfg->duration) {
		givcfg->end_time = time() + d;
		autoclose[chan] = call_out(open_close, d, chan, broadcaster_id, 0);
	}
	else m_delete(givcfg, "end_time");
	//Note: Updates reward status in fire and forget mode.
	foreach (givcfg->rewards || ([]); string id;)
		twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id=" + broadcaster_id + "&id=" + id,
			(["Authorization": "Bearer " + token]),
			(["method": "PATCH", "json": ([
				"is_enabled": want_open || givcfg->pausemode,
				"is_paused": !want_open && givcfg->pausemode,
			])]),
		);
	await(G->G->DB->save_config(broadcaster_id, "giveaways", givcfg));
	notify_websockets(broadcaster_id, chan, givcfg);
	object channel = G->G->irc->channels["#" + chan];
	array people = values(giveaway_tickets[chan]);
	int tickets = `+(0, @people->tickets), entrants = sizeof(people->tickets - ({0}));
	if (givcfg->is_open) channel->trigger_special("!giveaway_started", (["user": chan]), ([
		"{title}": givcfg->title || "",
		"{duration}": (string)givcfg->duration,
		"{duration_hms}": describe_time_short(givcfg->duration),
		"{duration_english}": describe_time(givcfg->duration),
	]));
	else channel->trigger_special("!giveaway_closed", (["user": chan]), ([
		"{title}": givcfg->title || "",
		"{tickets_total}": (string)tickets,
		"{entries_total}": (string)entrants,
	]));
}

mapping|zero websocket_cmd_makenotifs(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (conn->session->fake) return (["cmd": "demo"]);
	[object channel, string grp] = split_channel(conn->group);
	if (grp != "control") return 0;
	foreach (NOTIFICATION_SPECIALS; string kwd; mapping resp)
		G->G->cmdmgr->update_command(channel, "!!", "!giveaway_" + kwd, resp);
}

__async__ mapping|zero websocket_cmd_master(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (conn->session->fake) return (["cmd": "demo"]);
	[object channel, string grp] = split_channel(conn->group);
	if (grp != "control") return 0;
	string chan = channel->name[1..];
	int broadcaster_id = channel->userid;
	mapping givcfg = await(G->G->DB->load_config(channel->userid, "giveaways", 0));
	if (!givcfg) return 0; //No rewards, nothing to activate or anything
	switch (msg->action) {
		case "open":
		case "close": {
			int want_open = msg->action == "open";
			if (want_open == givcfg->is_open) {
				send_update(conn, (["message": "Giveaway is already " + (want_open ? "open" : "closed")]));
				return 0;
			}
			open_close(chan, broadcaster_id, want_open);
			break;
		}
		case "rig": {
			giveaway_rigged[broadcaster_id] = conn->session->user->display_name;
			channel->send((["{username}": channel->display_name]), "The giveaway has now been fully rigged, and we can draw a winner!");
			break;
		}
		case "pick": {
			//NOTE: This is subject to race conditions if the giveaway is open
			//at the time of drawing. Close the giveaway first.
			array people = (array)(giveaway_tickets[chan] || ([]));
			int tot = 0;
			array partials = ({ });
			foreach (people, [mixed id, mapping person]) partials += ({tot += person->tickets});
			if (!tot) {
				send_update(conn, (["message": "No tickets bought!"]));
				return 0;
			}
			int ticket = random(tot);
			//I could binary search but I doubt there'll be enough entrants to make a difference.
			array winner;
			foreach (partials; int i; int last) if (ticket < last) {winner = people[i]; break;}
			givcfg->last_winner = ({winner[0], winner[1]->name, winner[1]->tickets, tot}); //ID, name, ticket count, out of total
			if (!givcfg->allow_multiwin)
			{
				foreach (values(winner[1]->redemptions), mapping redem)
					set_redemption_status(redem, "FULFILLED");
				//This will eventually be done by the event hook, but the
				//front end updates faster if we force it immediately.
				winner[1]->redemptions = ([]);
				winner[1]->tickets = 0;
			}
			notify_websockets(broadcaster_id, chan, givcfg);
			await(G->G->DB->save_config(channel->userid, "giveaways", givcfg));
			channel->trigger_special("!giveaway_winner", (["user": chan]), ([
				"{title}": givcfg->title || "",
				"{winner_name}": givcfg->last_winner[1],
				"{winner_tickets}": (string)givcfg->last_winner[2],
				"{tickets_total}": (string)givcfg->last_winner[3],
				"{entries_total}": (string)sizeof(people[*][1]->tickets - ({0})),
				"{rigged}": m_delete(giveaway_rigged, broadcaster_id) || "",
			]));
			break;
		}
		case "cancel":
		case "end": {
			mapping existing = givcfg->rewards;
			if (!existing) break; //No rewards, nothing to cancel
			m_delete(givcfg, "last_winner");
			//Clear out the front end's view of ticket purchases to reduce flicker
			foreach (values(giveaway_tickets[chan] || ([])), mapping p) {
				p->redemptions = ([]);
				p->tickets = 0;
			}
			notify_websockets(broadcaster_id, chan, givcfg);
			await(G->G->DB->save_config(channel->userid, "giveaways", givcfg));
			if (givcfg->refund_nonwinning) msg->action = "cancel";
			array(array) redemptions = await(Concurrent.all(list_redemptions(broadcaster_id, chan, indices(existing)[*])));
			foreach (redemptions * ({ }), mapping redem)
				set_redemption_status(redem, msg->action == "cancel" ? "CANCELED" : "FULFILLED");
			array people = values(giveaway_tickets[chan]);
			int tickets = sizeof(people->tickets) && `+(@people->tickets), entrants = sizeof(people->tickets - ({0}));
			channel->trigger_special("!giveaway_ended", (["user": chan]), ([
				"{title}": givcfg->title || "",
				"{tickets_total}": (string)tickets,
				"{entries_total}": (string)entrants,
				"{giveaway_cancelled}": (string)(msg->action == "cancel"),
			]));
		}
	}
}

@"is_mod": void wscmd_managecommands(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	foreach (({"!tickets", "!refund"}), string id)
		G->G->enableable_modules->chan_commands->enable_feature(channel, id, !!msg->state);
	send_updates_all(channel, "control");
}

//TODO: Migrate the dynamic reward management to pointsrewards, keeping the giveaway management here
__async__ void channel_on_off(string channel, int just_went_online, int broadcaster_id) {
	if (!is_active_bot()) return 0;
	object chan = G->G->irc->id[broadcaster_id]; if (!chan) return;
	mapping dyn = await(G->G->DB->load_config(broadcaster_id, "dynamic_rewards"));
	if (!sizeof(dyn)) return; //Nothing to do
	object ts = G->G->stream_online_since[broadcaster_id] || Calendar.now();
	if (chan->config->timezone && chan->config->timezone != "") ts = ts->set_timezone(chan->config->timezone) || ts;
	string date = sprintf("%d %s %d", ts->month_day(), ts->month_name(), ts->year_no());
	mapping args = ([
		//Is "1" or "0" based on whether you are probably online. It's possible for this to be wrong
		//if you just went live or shut down.
		"{online}": (string)(just_went_online == -1 ? !!G->G->stream_online_since[broadcaster_id] : just_went_online),
		//Date/time info is in your timezone or UTC if not set, and is the time the stream went online
		//or (approximately) offline.
		"{year}": (string)ts->year_no(), "{month}": (string)ts->month_no(), "{day}": (string)ts->month_day(),
		"{hour}": (string)ts->hour_no(), "{min}": (string)ts->minute_no(), "{sec}": (string)ts->second_no(),
		"{dow}": (string)ts->week_day(), //1 = Monday, 7 = Sunday
	]);
	string token = token_for_user_login(channel)[0];
	//TODO: Store the cache keyed by id?
	mapping rewards = ([]);
	foreach (G->G->pointsrewards[broadcaster_id] || ({ }), mapping r) rewards[r->id] = r;
	if (token != "") foreach (dyn; string reward_id; mapping info) {
		int active = 0;
		mapping params = ([]);
		//If we just went online/offline, reset to base cost (if there is one).
		if (just_went_online != -1 && info->basecost) params->cost = info->basecost;
		if (mixed ex = info->availability && catch {
			//write("Evaluating: %O\n", info->availability);
			active = (int)G->G->evaluate_expr(chan->expand_variables(info->availability, args), ({channel, ([])}));
			//write("Result: %O\n", active);
			//Triple negative. We want to know if the enabled state has changed, but
			//some things will use 1 and 0, others will use Val.true and Val.false.
			//So to be safe, we booleanly negate both sides, and THEN see if they
			//differ; if they do, we update using Val.* to ensure the right JSON.
			if (!rewards[reward_id]->?is_enabled != !active)
				params->is_enabled = active ? Val.true : Val.false;
		}) werror("ERROR ACTIVATING REWARD:\n%s\n", describe_backtrace(ex)); //TODO: Report to the streamer
		if (sizeof(params)) twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id="
				+ broadcaster_id + "&id=" + reward_id,
			(["Authorization": "Bearer " + token]),
			(["method": "PATCH", "json": params]),
		);
	}
}
@hook_channel_online: int channel_online(string channel, int uptime, int id) {channel_on_off(channel, 1, id);}
@hook_channel_offline: int channel_offline(string channel, int uptime, int id) {channel_on_off(channel, 0, id);}

constant command_description = "Giveaway tools. Use subcommand 'status' or 'refund'.";
constant builtin_description = "Handle giveaways via channel point redemptions"; //The subcommands are mandated by the parameter type
constant builtin_name = "Giveaway tools";
constant builtin_param = "/Action/refund/status";
constant vars_provided = ([
	"{action}": "Action taken - same as subcommand, or 'none' if there was nothing to do",
	"{tickets}": "Number of tickets you have (or had)",
]);
constant command_suggestions = ([
	"!tickets": ([
		"_description": "Giveaways - show number of tickets you have (any user)", "_hidden": 1,
		"builtin": "chan_giveaway", "builtin_param": ({"status"}),
		"message": "@$$: You have {tickets} tickets.",
	]),
	"!refund": ([
		"_description": "Giveaways - refund all your tickets (any user)", "_hidden": 1,
		"builtin": "chan_giveaway", "builtin_param": ({"refund"}),
		"message": "@$$: All your tickets have been refunded.",
	]),
	//TODO: Mod-only refund command (maybe the same one??) to refund other person's tickets
]);

__async__ mapping message_params(object channel, mapping person, array params, mapping cfg) {
	if (cfg->simulate) {cfg->simulate("Giveaway " + params * " "); return ([]);}
	if (params[0] == "") error("Need a subcommand\n");
	sscanf(params[0], "%[^ ]%*[ ]%s", string cmd, string arg);
	if (cmd != "refund" && cmd != "status") error("Invalid subcommand\n");
	mapping givcfg = await(G->G->DB->load_config(channel->userid, "giveaways", 0));
	if (!givcfg) error("Giveaways not active\n"); //Not the same as "giveaway not open", this one will not normally be seen
	string chan = channel->name[1..];
	mapping people = giveaway_tickets[chan] || ([]);
	mapping you = people[(string)person->uid] || ([]);
	if (cmd == "refund") {
		if (!you->tickets) return (["{action}": "none", "{tickets}": "0"]);
		if (!givcfg->is_open) error("The giveaway is closed and you can't refund tickets, sorry!\n");
		foreach (values(you->redemptions), mapping redem)
			set_redemption_status(redem, "CANCELED");
	}
	return ([
		"{tickets}": (string)you->tickets,
		"{action}": cmd,
	]);
}

protected void create(string name) {::create(name);}
