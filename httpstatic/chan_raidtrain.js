import choc, {set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {INPUT, LABEL, OPTION, SELECT, TD, TEXTAREA, TIME, TR} = choc; //autoimport

const may_request = {
	none: "closed", any: "open",
	//TODO: Have an option for "approved persons" or "team members" or something
};

//Note that the user-facing controls show local time, but the server works in UTC.
function makedate(val, id) {
	const opts = [];
	for (let hour = 0; hour < 24; ++hour) opts.push(OPTION(("0" + hour).slice(-2)));
	const date = val ? new Date(val * 1000) : new Date();
	return [
		INPUT({id, type: "date", value: date.getFullYear() + "-" + (date.getMonth()+1) + "-" + date.getDate()}),
		SELECT({id: id + "_time", value: ("0" + date.getHours()).slice(-2)}, opts),
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
	{key: "description", label: "Description", render: val => TEXTAREA({rows: 4, cols: 35}, val)},
	{key: "raidcall", label: "Raid call", render: val => TEXTAREA({rows: 4, cols: 35}, val)},
	{key: "startdate", label: "Start date", render: makedate, getvalue: getdate},
	{key: "enddate", label: "End date", render: makedate, getvalue: getdate},
	{key: "may_request", label: "Slot requests", render: val => SELECT(
		Object.entries(may_request).map(([k,v]) => OPTION({value: k}, v)))},
];

function DATE(d) {
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
		"Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split(" ")[date.getMonth()],
		" " + day + ", ",
		("0" + date.getHours()).slice(-2) + ":00",
	]);
}

export function render(data) {
	set_content("#configdlg tbody", cfg_vars.map(v => {
		const input = v.render(data.cfg[v.key] || "", "edit_" + v.key);
		if (!Array.isArray(input)) input.id = "edit_" + v.key;
		return TR([
			TD(LABEL({for: input.id}, v.label)),
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
}

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
