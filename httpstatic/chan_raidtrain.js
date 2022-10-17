import {choc, set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {A, BR, BUTTON, DIV, IMG, INPUT, LABEL, LI, OPTION, SELECT, TD, TEXTAREA, TIME, TR} = choc; //autoimport

const may_request = {
	none: "closed", any: "open",
	//TODO: Have an option for "approved persons" or "team members" or something
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
	console.log("Date:", elem.value + "T" + DOM("#" + elem.id + "_time").value + ":00");
	const date = new Date(elem.value + "T" + DOM("#" + elem.id + "_time").value + ":00");
	return Math.floor((+date)/1000);
}

const cfg_vars = [
	{key: "title", label: "Title", render: val => INPUT({value: val, size: 40})},
	{key: "description", label: "Description\n(Markdown)", render: val => TEXTAREA({rows: 4, cols: 35}, val)},
	{key: "raidcall", label: "Raid call", render: val => TEXTAREA({rows: 4, cols: 35}, val)},
	{key: "startdate", label: "Start date", render: makedate, getvalue: getdate},
	{key: "enddate", label: "End date", render: makedate, getvalue: getdate},
	{key: "may_request", label: "Slot requests", render: val => SELECT(
		{value: val},
		Object.entries(may_request).map(([k,v]) => OPTION({value: k}, v)))},
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
		!timeonly && "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split(" ")[date.getMonth()] + " " + day + ", ",
		pad(date.getHours()) + ":00",
	]);
}

function channel_profile(chan) {
	if (!chan) return "";
	return A({href: "https://twitch.tv/" + chan.login, target: "_blank"}, [
		IMG({className: "avatar", src: chan.profile_image_url}),
		chan.display_name,
	]);
}

let owner_id = { }, slots = [], people = { };
export function render(data) {
	set_content("#configdlg tbody", cfg_vars.map(v => {
		const input = v.render(data.cfg[v.key] || "", "edit_" + v.key);
		if (!Array.isArray(input)) input.id = "edit_" + v.key;
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
	set_content("#cfg_dates", [
		"From ", DATE(data.cfg.startdate),
		" until ", DATE(data.cfg.enddate),
	]);
	set_content("#cfg_slotsize", (data.cfg.slotsize||1) + " hour(s)");
	set_content("#cfg_may_request", may_request[data.cfg.may_request||"none"]);
	people = data.people; owner_id = data.owner_id;
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
	if (slots = data.cfg.slots) set_content("#timeslots tbody", data.cfg.slots.map((slot,i) => TR([
		TD(abbrevdate(slot.start)),
		TD(DATE(slot.end, 1)),
		TD(channel_profile(people[slot.broadcasterid])),
		TD([
			!slot.broadcasterid && slot.claims && DIV(slot.claims.map(id => DIV(channel_profile(people[id])))),
			" ",
			data.is_mod ? BUTTON({class: "streamerslot", "data-slotidx": i}, "Manage")
			: !self ? ""
				//TODO: Handle may_request other than none/any
			: !slot.broadcasterid && data.cfg.may_request === "any" ?
				BUTTON({class: "requestslot", "data-slotidx": i},
					slot.claims && slot.claims.indexOf(self) > -1 ? "Unrequest" : "Request")
			: "",
		]),
		TD(slot.notes || ""),
	])));
}

let selectedslot = { }, slotidx = -1;
on("click", ".streamerslot", e => {
	selectedslot = slots[slotidx = (e.match.dataset.slotidx|0)];
	const seen = { };
	function RB(person) {
		if (!person || seen[person.id]) return "";
		seen[person.id] = 1;
		return LI(LABEL([ //FIXME: Labelling the input with an anchor creates a click conflict.
			INPUT({type: "radio", name: "slotselection", value: person.id, checked: person.id == selectedslot.broadcasterid}),
			channel_profile(person),
		]));
	}
	set_content("#streamerslot_options", [
		RB(people[owner_id]),
		//TODO: This doesn't work if you have no claims. May need an explicit call to get profile for self.
		RB(people[ws_sync.get_userid()]),
		selectedslot.claims && selectedslot.claims.map(id => RB(people[id])),
		LI(LABEL([INPUT({type: "radio", name: "slotselection", value: "0", checked: !selectedslot.broadcasterid}),
			"Nobody (for now)"])),
	]);
	set_content("#streamerslot_start", DATE(selectedslot.start));
	set_content("#streamerslot_end", DATE(selectedslot.end));
	DOM("#streamerslot_dlg").showModal();
});

on("submit", "#streamerslot_dlg form", e => {
	const rb = DOM("#streamerslot_options input[type=radio]:checked");
	const broadcasterid = rb ? rb.value : "0"; //Shouldn't ever be absent but whatever
	ws_sync.send({cmd: "streamerslot", slotidx, broadcasterid});
	selectedslot = { }; slotidx = -1;
});

on("click", ".requestslot", e => ws_sync.send({cmd: "requestslot", slotidx: e.match.dataset.slotidx|0}));

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
