import {lindt, replace_content as set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {A, BR, BUTTON, DIV, IMG, INPUT, LABEL, LI, OPTION, SELECT, SPAN, TD, TEXTAREA, TIME, TR} = lindt; //autoimport
import {simpleconfirm} from "$$static||utils.js$$";

let day_based = false;

const may_request_options = {
	none: "closed", any: "open",
	//TODO: Have an option for "approved persons" or "team members" or something
	//TODO maybe: Have an option for "streamers", defined by "people with at least one VOD, at least a day old"?
	//That would effectively require 2FA.
};

const pad = n => ("0" + n).slice(-2);
//Note that the user-facing controls show local time, but the server works in UTC.
function makedate(val, id) {
	const opts = [];
	for (let hour = 0; hour < 24; ++hour) opts.push(OPTION(pad(hour)));
	const date = val ? new Date(val * 1000) : new Date();
	return [
		INPUT({id, type: "date", value: date.getFullYear() + "-" + pad(date.getMonth()+1) + "-" + pad(date.getDate())}),
		SELECT({id: id + "_time", value: pad(date.getHours())}, opts),
		":00",
	];
}
function getdate(elem) {
	if (elem.value === "") return 0;
	const date = new Date(elem.value + "T" + DOM("#" + elem.id + "_time").value + ":00");
	return Math.floor((+date)/1000);
}

const cfg_vars = [
	{key: "title", label: "Title", render: (value, id) => INPUT({value, id, size: 40})},
	{key: "description", label: "Description\n(Markdown)", render: (val, id) => TEXTAREA({id, rows: 4, cols: 35}, val)},
	{key: "raidcall", label: "Raid call", render: (val, id) => TEXTAREA({id, rows: 4, cols: 35}, val)},
	{key: "startdate", label: "Start date", render: makedate, getvalue: getdate},
	{key: "enddate", label: "End date", render: makedate, getvalue: getdate},
	{key: "slotsize", label: "Slot size", render: (value, id) => SELECT({value, id}, [
		OPTION({value: "1"}, "One hour"),
		OPTION({value: "2"}, "Two hours"),
		OPTION({value: "3"}, "Three hours"),
		OPTION({value: "4"}, "Four hours"),
		OPTION({value: "8"}, "Eight hours"),
		OPTION({value: "12"}, "Twelve hours"),
		OPTION({value: "24"}, "One day"),
	])},
	{key: "may_request", label: "Slot requests", render: (value, id) => SELECT({value, id},
		Object.entries(may_request_options).map(([k,v]) => OPTION({value: k}, v)))},
];

function DATE(d, timeonly) {
	if (!d) return "(unspecified)";
	const date = new Date(d * 1000);
	let day = date.getDate();
	switch (day) {
		case 1: case 21: day += "st"; break;
		case 2: case 22: day += "nd"; break;
		case 3: case 23: day += "rd"; break;
		default: day += "th";
	}
	return TIME({datetime: date.toISOString(), title: date.toLocaleString()}, [
		//This abbreviated format assumes English. The hover will be in your locale.
		!timeonly && "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split(" ")[date.getMonth()] + " " + day,
		!timeonly && !day_based && ", ",
		!day_based && pad(date.getHours()) + ":00",
	]);
}

function channel_profile(chan) {
	if (!chan) return "";
	return A({href: "https://twitch.tv/" + chan.login, target: "_blank"}, [
		IMG({className: "avatar", src: chan.profile_image_url}),
		chan.display_name,
	]);
}

let owner_id = { }, slots = [], people = { }, is_mod = false, may_request = "none", online_streams = { };
export function render(data) {
	set_content("#configdlg tbody", cfg_vars.map(v => {
		const input = v.render(data.cfg[v.key] || "", "edit_" + v.key);
		//Split the label into lines as required
		const lbl = v.label.split("\n").map((l,i) => i ? [BR(), l] : l);
		return TR([
			TD(LABEL({for: input.id}, lbl)),
			TD(input),
		]);
	}));
	if (data.desc_html) DOM("#cfg_description").innerHTML = data.desc_html;
	set_content("#cfg_title", data.cfg.title || "Raid train settings");
	DOM("#cfg_raidcall").value = data.cfg.raidcall || "";
	day_based = data.cfg.slotsize === 24;
	set_content("#cfg_dates", [
		"From ", DATE(data.cfg.startdate),
		" until ", DATE(data.cfg.enddate),
	]);
	if (day_based) set_content("#cfg_slotsize", "Day");
	else set_content("#cfg_slotsize", (data.cfg.slotsize||1) + " hour(s)");
	set_content("#cfg_may_request", may_request_options[data.cfg.may_request||"none"]);
	people = data.people; owner_id = data.owner_id; is_mod = data.is_mod;
	may_request = data.cfg.may_request; online_streams = data.online_streams;
	if (slots = data.cfg.slots) update_schedule();
	const casters = data.cfg.all_casters || [];
	set_content("#streamer_count", ""+casters.length);
	DOM("#raidfinder_link a").href = "/raidfinder?train=" + data.owner_id; //Might be nice to use the name, but both work
}

function update_schedule() {
	let lastdate = 0;
	function abbrevdate(d) {
		//If the two dates are on the same day (simplified down to just "same
		//day of month" since it'll be progressing sequentially), leave out the
		//date and just show the time. The hover still has everything.
		const date = new Date(d * 1000).getDate();
		const sameday = date === lastdate;
		lastdate = date;
		return DATE(d, sameday);
	}
	const self = ws_sync.get_userid();
	const now = +new Date / 1000;
	set_content("#timeslots tbody", slots.map((slot,i) => TR(
	{class: slot.start <= now && slot.end > now ? "now" :
		slot.broadcasterid === self ? "your_slot" : ""
	}, [
		TD({colspan: day_based ? 2 : 1}, abbrevdate(slot.start)),
		!day_based && TD(DATE(slot.end, 1)),
		TD([
			online_streams[slot.broadcasterid] && online_streams[slot.broadcasterid].online &&
				SPAN({class: "recording", title: "Live now!"}, "⏺"),
			channel_profile(people[slot.broadcasterid]),
		]),
		TD([
			!slot.broadcasterid && slot.claims && DIV(slot.claims.map(id => DIV(channel_profile(people[id])))),
			" ",
			is_mod ? BUTTON({class: "streamerslot", "data-slotidx": i}, "Manage")
			: !self ? ""
				//TODO: Handle may_request other than none/any
			: !slot.broadcasterid && may_request === "any" ?
				BUTTON({class: "requestslot", "data-slotidx": i},
					slot.claims && slot.claims.indexOf(self) > -1 ? "Unrequest" : "Request")
			: "",
		]),
		TD([
			slot.notes || "",
			(is_mod || slot.broadcasterid === self) &&
				BUTTON({class: "slotnotes", "data-slotidx": i, title: "Edit notes"}, "✍"),
		]),
	])));
}
setInterval(update_schedule, 60000); //Repaint every minute to update the "now" marker

let selectedslot = { }, slotidx = -1;
on("click", ".streamerslot", e => {
	selectedslot = slots[slotidx = (e.match.dataset.slotidx|0)];
	const seen = { };
	function RB(person, deletable) {
		if (!person || seen[person.id]) return "";
		seen[person.id] = 1;
		return LI([
			LABEL([ //FIXME: Labelling the input with an anchor creates a click conflict.
				INPUT({type: "radio", name: "slotselection", value: person.id}),
				channel_profile(person),
			]),
			" ",
			deletable && BUTTON({type: "button", class: "revokeclaim", "data-broadcasterid": person.id, title: "Remove request"}, "🗑"),
		]);
	}
	set_content("#streamerslot_options", [
		RB(people[selectedslot.broadcasterid]),
		RB(people[owner_id]),
		//TODO: This doesn't work if you have no claims. May need an explicit call to get profile for self.
		RB(people[ws_sync.get_userid()]),
		selectedslot.claims && selectedslot.claims.map(id => RB(people[id], 1)),
		LI([
			//Note that the checkbox has no label. Clicking the text puts the cursor in the text field.
			INPUT({type: "radio", name: "slotselection", value: "login", id: "streamerslot_loginrb"}),
			LABEL({style: "display: inline-block; vertical-align: top"}, [
				"Enter user name or Twitch link:", BR(),
				INPUT({id: "streamerslot_login", size: 30, autocomplete: "off"}),
			]),
		]),
		LI(LABEL([INPUT({type: "radio", name: "slotselection", value: "0"}),
			"Nobody (for now)"])),
	]);
	set_content("#streamerslot_start", DATE(selectedslot.start));
	set_content("#streamerslot_end", DATE(selectedslot.end));
	DOM("#streamerslot_login").value = "";
	const rb = DOM('[name="slotselection"][value="' + selectedslot.broadcasterid + '"]')
		|| DOM('[name="slotselection"][value="0"]');
	rb.checked = true;
	DOM("#streamerslot_dlg").showModal();
});

on("submit", "#streamerslot_dlg form", e => {
	const rb = DOM("#streamerslot_options input[type=radio]:checked");
	const broadcasterid = rb ? rb.value : "0"; //Shouldn't ever be absent but whatever
	if (broadcasterid === "login") ws_sync.send({cmd: "streamerslot", slotidx, broadcasterlogin: DOM("#streamerslot_login").value});
	else ws_sync.send({cmd: "streamerslot", slotidx, broadcasterid});
	selectedslot = { }; slotidx = -1;
});

on("click", ".revokeclaim", simpleconfirm("Revoke this claim?", e =>
	ws_sync.send({cmd: "revokeclaim", slotidx, broadcasterid: e.match.dataset.broadcasterid})));

on("input", "#streamerslot_login", e => DOM("#streamerslot_loginrb").checked = true);

on("click", ".requestslot", e => ws_sync.send({cmd: "requestslot", slotidx: e.match.dataset.slotidx|0}));

on("click", ".slotnotes", e => {
	selectedslot = slots[slotidx = (e.match.dataset.slotidx|0)];
	DOM("#slotnotes_content").value = selectedslot.notes || "";
	set_content("#slotnotes_start", DATE(selectedslot.start));
	set_content("#slotnotes_end", DATE(selectedslot.end));
	DOM("#slotnotes_dlg").showModal();
});

on("submit", "#slotnotes_dlg form", e => {
	ws_sync.send({cmd: "slotnotes", slotidx, notes: DOM("#slotnotes_content").value});
	selectedslot = { }; slotidx = -1;
});

on("click", "#editconfig", e => DOM("#configdlg").showModal());
on("submit", "#configdlg form", e => {
	const el = e.match.elements;
	const msg = {cmd: "update"};
	cfg_vars.forEach(v => {
		const elem = el["edit_" + v.key];
		msg[v.key] = v.getvalue ? v.getvalue(elem) : elem.value;
	});
	ws_sync.send(msg);
});

on("click", "#reset_schedule", simpleconfirm(
	"Resetting the schedule removes all slots, assignments, requests, notes, etc. This cannot be undone!",
	e => ws_sync.send({cmd: "resetschedule"})));
