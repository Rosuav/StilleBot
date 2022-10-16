inherit http_websocket;
constant markdown = #"# Raid train organized by $$channel$$

## Raid train settings
{:#cfg_title}

<div id=cfg_description markdown=1>
$$description||The owner can fill out a description here.$$
</div>

Raid call: <textarea readonly id=cfg_raidcall></textarea>

Schedule:
* <span id=cfg_dates></span>
* Slot size: <span id=cfg_slotsize>1 hour</span>
* Unique streamers: <span id=streamer_count>(unknown)</span>

$$save_or_login$$

## Schedule

This is who's going to be part of the train when. They may be live earlier than this. Slot requesting
is currently <span id=cfg_may_request>closed</span>.

Start   | End | Streamer | Notes
--------|-----|----------|-------
loading | - | - | -
{:#timeslots}

> ### Configuration
> Plan out your raid train!
>
> Configuration | -
> - | -
> loading... | loading...
>
> [Save](:#save type=submit) [Close](:.dialog_close)
{: tag=formdialog #configdlg}

<style>
time {font-weight: bold;}
#cfg_may_request {font-weight: bold;}
.avatar {max-width: 40px; vertical-align: middle; margin: 0 8px;}
#streamerslot_options {list-style-type: none;}
</style>

> ### Select Streamer
> Who should take time slot <span id=streamerslot_start></span> to <span id=streamerslot_end></span>?
>
> * loading...
> {:#streamerslot_options}
>
> [Select](:type=submit) [Close](:.dialog_close)
{: tag=formdialog #streamerslot_dlg}
";

/* Raid train organization
- Everything starts with one Owner/Organizer who must be using this bot.
- Go to https://sikorsky.rosuav.com/channels/demo/raidtrain
- Owner can configure everything:
- Title, description, raid call
- Start/end date and time
- Slot size (eg 1 hour)
- Maximum slots per streamer?
- Requests visible (y/n) - currently has to be Yes as claims are in the public info
- The time period from start to end, divided into slots, is tabulated (with a
  scroll bar if necessary) for everyone, and is shown in both the user's TZ and
  the "canonical" TZ (== the owner's).
- Anyone can request a slot. If requests are visible, they will be able to see
  everyone else who's put in a request.
- Owner can approve any (one) request for a slot. This makes that user name and
  avatar visible to everyone who looks at the tabulated schedule.
  - Back end: Owner and mods may specify any Twitch user ID to be given the slot.
    The server will cache the display name, login, and avatar. (Steal code from
    ghostwriter? It's not like GW needs it any more anyway.)
  - Front end: Owner and mods have a dialog to "assign". It has options for all
    those who've requested, plus "assign broadcaster"; if mod, can also "assign
    self". (Or alternatively: Always have "assign self", and if mod, also b/c.
    Not sure which would be easier. It might not matter, if it just shows the
    options by display name and avatar.)
  - Identify a slot by its start time.
- Owner and slot holder may edit comments shown in one column on the schedule.
- If the current time is within the raid train period, highlight "NOW".
- If the current user is on the schedule, highlight "YOU".

All configuration is stored in persist_status->raidtrain->USERID, with public
info (anything that can be shared with any client regardless of authentication)
in ->cfg; this should include the vast majority of information.

TODO: Make slot width configurable, and test various combinations:
* Two-hour slots, starting on an even hour; starting on an odd hour
* Two-hour slots, 15-hour span
* Change width after schedule established (NOT IMPLEMENTED, schedule will stay)
* Two-hour slots, move start by one hour
* Four-hour slots, shorten span by three hours, change slot size to two hours
* Etc
*/

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	mapping trn = persist_status->path("raidtrain", (string)req->misc->channel->userid);
	req->misc->chaninfo->autoform = req->misc->chaninfo->autoslashform = "";
	return render(req, ([
		"vars": (["ws_group": req->misc->is_mod ? "control" : "view"]),
		"save_or_login": "[Edit](:#editconfig)",
		"description": trn->cfg->?description, //Because it will be parsed as Markdown
	]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return grp == "control";}
mapping get_chan_state(object channel, string grp, string|void id) {
	mapping cfg = persist_status->path("raidtrain", (string)channel->userid, "cfg");
	mapping owner = G->G->user_info[channel->userid] || ([]);
	if (!owner->display_name) get_user_info(channel->userid)->then() {send_updates_all(grp + channel->name);};
	return ([
		"cfg": cfg,
		"owner_info": owner,
		"is_mod": grp == "control",
		"desc_html": Tools.Markdown.parse(cfg->description || "", ([
			"renderer": Renderer, "lexer": Lexer,
		])),
	]);
}

void websocket_cmd_streamerslot(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	sscanf(conn->group, "%s#%s", string grp, string chan);
	//Should streamers be allowed to revoke their own slots??
	object channel = G->G->irc->channels["#" + chan];
	if (grp != "control" || !channel) return;
	if (conn->session->fake) return;
	mapping trn = persist_status->path("raidtrain", (string)channel->userid);
	array slots = trn->cfg->slots || ({ });
	if (!intp(msg->slotidx) || msg->slotidx < 0 || msg->slotidx >= sizeof(slots)) return;
	mapping slot = slots[msg->slotidx];
	slot->broadcasterid = (int)msg->broadcasterid;
	//TODO: Recalculate stats like "number of unique streamers"
	if (slot->broadcasterid) get_user_info(slot->broadcasterid); //Populate cache just in case
	persist_status->save();
	send_updates_all("control#" + chan);
	send_updates_all("view#" + chan);
}

void websocket_cmd_update(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	sscanf(conn->group, "%s#%s", string grp, string chan);
	//TODO: Allow updates of your own slot's comments, if you have a slot
	object channel = G->G->irc->channels["#" + chan];
	if (grp != "control" || !channel) return;
	if (conn->session->fake) return;
	mapping trn = persist_status->path("raidtrain", (string)channel->userid);
	foreach ("title description raidcall may_request" / " ", string str)
		if (msg[str]) trn->cfg[str] = msg[str];
	foreach ("startdate enddate slotsize" / " ", string num)
		if ((int)msg[num]) trn->cfg[num] = (int)msg[num];
	if (!(<"none", "any">)[trn->cfg->may_request]) trn->cfg->may_request = "none";

	if (trn->cfg->startdate && trn->cfg->enddate > trn->cfg->startdate) {
		int tcstart = trn->cfg->startdate, tcend = trn->cfg->enddate;
		int slotwidth = (trn->cfg->slotsize || 1) * 3600;
		array slots = trn->cfg->slots || ({ });
		//Trim the array down to the limits, stopping at any non-empty slot.
		//That way, if someone has claimed a slot, you won't unclaim it for
		//them simply by miskeying something. Or looking at it the other way
		//around: any reduction of the date span can be undone safely.
		//Note that it may be helpful to close slot requests if you need to
		//shift the start date/time by less than the slot width. If that ever
		//happens at all, that is, which it probably won't.
		int trim = 0;
		foreach (slots; int i; mapping s)
			if (s->end <= tcstart && !s->broadcasterid && (!s->claims || !sizeof(s->claims)))
				trim = i;
			else break;
		if (trim) slots = slots[trim..];
		//If the first slot ends after the start date, but starts before it,
		//make it a short slot.
		if (sizeof(slots) && slots[0]->end > tcstart && slots[0]->start < tcstart)
			slots[0]->start = tcstart;
		//Now trim the end, similarly. The check is done in reverse though,
		//and no early break. And yes, that means we're doing less-than
		//comparisons in both - the above is removing anything that ends
		//before we start, this keeps anything that starts before we end.
		trim = -1;
		foreach (slots; int i; mapping s)
			if (s->start < tcend || s->broadcasterid || (s->claims && sizeof(s->claims)))
				trim = i;
		slots = slots[..trim];
		//Another possible short slot.
		if (sizeof(slots) && slots[0]->end > tcend && slots[0]->start < tcend)
			slots[0]->end = tcend;
		//Alright. Now to add slots. First, to properly define "left" and
		//"right", ensure that we have at least one slot.
		if (!sizeof(slots)) slots = ({(["start": tcstart, "end": min(tcstart + slotwidth, tcend)])});
		//Next, widen the first and/or last slots to the slot width. To
		//simplify the arithmetic, keep track of the slot start offset;
		//if all slots start precisely slotwidth apart, starting at the
		//start time, their Unix times will all be congruent modulo the
		//slotwidth.
		int slot_offset = tcstart % slotwidth; //Will often be zero.
		int wid = slots[0]->end - slots[0]->start;
		if (wid < slotwidth && slots[0]->start % slotwidth != slot_offset)
			//Expand the slot, to no more than...
			slots[0]->start -= min(0, //... its current size,
				slotwidth - wid, //... the size of one normal slot,
				slots[0]->start - tcstart, //... and not past the defined start.
			);
		//Same with the last slot.
		wid = slots[-1]->end - slots[-1]->start;
		if (wid < slotwidth && slots[0]->end % slotwidth != slot_offset)
			slots[0]->end += min(0, slotwidth - wid, tcend - slots[0]->end);
		//If the first slot doesn't begin on the slot offset, insert a short slot.
		if (slots[0]->start % slotwidth != slot_offset) {
			//Always subtract a positive number of seconds, regardless of
			//whether the slot_offset is above or below start's offset.
			int delta = (slots[0]->start - slot_offset) % slotwidth;
			slots = ({(["start": slots[0]->start - delta, "end": slots[0]->start])}) + slots;
		}
		//Extend to the right. Each slot begins where the previous one left off,
		//is no more than slotwidth in width, and ends on the slot_offset. If we
		//end up mismatching with the configured end, make a short slot.
		int end = slots[-1]->end - (slots[-1]->end - slot_offset) % slotwidth;
		while (end < tcend) slots += ({([
			"start": slots[-1]->end,
			"end": min(end += slotwidth, tcend),
		])});
		//Rather than extend to the left, we build up a new set of pristine slots
		//from the start point, stopping once we don't need to make more.
		array fresh = ({ });
		for (int tm = tcstart; tm < slots[0]->start; tm += slotwidth) {
			fresh += ({([
				"start": tm, "end": min(tm + slotwidth, slots[0]->start),
			])});
		}
		//Whew. That's a lot of chopping and changing, most of which will probably
		//never happen. Recommendation: Only ever expand/contract in multiples of
		//the slot width, never change the slot width, and all should be easy.
		//Also: most of the above code is probably buggy. I have not tested it at
		//all thoroughly.
		trn->cfg->slots = fresh + slots;
	}
	persist_status->save();
	send_updates_all("control#" + chan);
	send_updates_all("view#" + chan);
}
