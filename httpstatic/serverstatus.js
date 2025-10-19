import {choc, set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {BR, BUTTON, DIV, EM, FIELDSET, H3, LEGEND, LI, P, SPAN, UL} = choc; //autoimport

const sharedattrs = {cpu: "CPU", ram: "RAM", spinner: -1};
const attrs = {
	Gideon: {...sharedattrs},
	Sikorsky: {...sharedattrs, gpu: "GPU", vram: "VRAM", enc: -1, dec: -1},
};
let chart;

set_content("#content", ["Gideon", "Sikorsky"].map(id => {
	return P({id}, [
		SPAN({class: "label"}, id + ": "),
		Object.keys(attrs[id]).map(name => attrs[id][name] !== -1 && [attrs[id][name] + ": ", SPAN({class: name + " percent"}), " "]),
		attrs[id].enc && ["Enc: ", SPAN({class: "enc percent"}), ":", SPAN({class: "dec percent"}), " "],
		SPAN({class: "db"}),
		SPAN({class: "sockets"}),
		SPAN({class: "spinner"}),
	]);
}));
function minify() {
	if (chart) {chart.destroy(); chart = null;}
	const content = DOM("#content");
	DOM("main").replaceWith(content, DOM("main style"));
	content.style.margin = "0";
}
if (location.hash === "#mini") minify();
on("click", 'a[href="#mini"]', minify);

let active_bot = null;
function update(data, par) {
	Object.keys(data).forEach(name => attrs[par][name] && set_content("#" + par + " ." + name, ""+data[name]));
	set_content("#" + par + " .db", [
		data.livedb?.host && ["DB: ", data.livedb.host, " (" + Math.floor(data.livedb.ping * 1000) + " ms)"],
		data.fastdb?.host && [" Alt DB: ", data.fastdb.host, " (" + Math.floor(data.fastdb.ping * 1000) + " ms)"],
	]);
	//Can't shortcut sockets b/c it's not a percentage
	set_content("#" + par + " .sockets", [
		"Users: ", data.socket_count,
		" ",
	]);
	//Note that data.readonly is either "on" or "off", it's not a truthy value. Absence means that we don't have that data at all.
	if (data.readonly) set_content("#admin-" + par + " .status", [
		data.readonly === "on"
			? DIV({style: "color: #008; font-weight: bold"}, "Read only")
			: DIV({style: "color: #090; font-weight: bold"}, "Read/write"),
		//TODO.
	]);
	if (data.active_bot) {
		//The two bots should agree on which one is active. If they don't, there is likely to be a crisis
		//brewing. Currently we don't report such a discrepancy.
		active_bot = data.active_bot;
		set_content("#admin-General .status", [
			DIV(["Active: ", SPAN({style: "color: rebeccapurple; font-weight: bold"}, active_bot.replace(".mustardmine.com", ""))]),
		]);
	}
}
export function render(data) {update(data, "Sikorsky");}
export const ws_host = "sikorsky.mustardmine.com";
export const ws_config = {quiet: {msg: 1}};
ws_sync.send({cmd: "graph"});

if (ws_group === "control") { //Don't bother doing this on the default connection - the dialog will never be opened and has no useful functionality.
	const actions = ["DB down", "DB up"];
	const general_actions = ["IRC reconnect"];
	set_content("#servers", ["Sikorsky", "General", "Gideon"].map(srv => FIELDSET({id: "admin-" + srv, "data-sendid": srv}, [
		LEGEND(srv),
		(srv === "General" ? general_actions : actions).map(ac => BUTTON(
			{class: "dbctl", "data-action": ac.toLowerCase().replace(/ /g, "_")},
			ac,
		)),
		DIV({class: "status"}),
	])));
	on("click", ".dbctl", e => {
		let sendid = e.match.closest_data("sendid");
		if (sendid === "General") {
			//General requests get sent to the active bot, whichever it is at the time.
			//Kinda hacky to look at it this way but whatever.
			if (active_bot === "gideon.mustardmine.com") sendid = "Gideon";
			else sendid = "Sikorsky";
		}
		ws_sync.send({cmd: e.match.dataset.action}, sendid);
	});
}

function number(n) {
	if (n < 0) return "-" + number(-n);
	if (n === Math.floor(n)) return ""+Math.floor(n);
	//Round non-integers to two decimal places
	return ""+(Math.round(n * 100) / 100);
}

let current_highlight = -1;
function highlight(idx) {
	if (!chart || idx === current_highlight) return;
	current_highlight = idx;
	chart.data.datasets.forEach((ds, i) => {
		const col = ds.borderColor.slice(0, 7) //Remove any current alpha value
			+ (i === current_highlight || current_highlight === -1 ? "" : "30"); //Add alpha to the ones NOT highlighted.
		ds.borderColor = ds.backgroundColor = col;
	});
	chart.update();
}

export function sockmsg_graph(msg) {
	if (!msg.active) return; //TODO: If we haven't heard from an active bot in a while, render even from an inactive.
	const fig = DOM("#graph figcaption"); //Absent in mini-mode
	if (!fig) return;
	set_content(fig, [
		H3("Load peaks (60 sec avg)"),
		UL({onmouseleave: e => highlight(-1)}, msg.defns.map((defn, i) => LI({onmouseenter: e => highlight(i)}, [
			SPAN({style: "color: rgb(" + defn.color.join(",") + ")"}, defn.prefix), " ", number(msg.peaks[i]), " ", defn.unit,
			BR(), EM(["(", defn.desc, ")"]),
		]))),
	]);
	if (!chart) chart = new Chart(DOM("canvas"), {
		type: "line",
		data: {
			labels: msg.times,
			datasets: msg.defns.map((ld, i) => ({
				label: ld.prefix, //TODO: Use desc instead?
				data: msg.plots[i].map((val, pos) => [pos + 1, val]),
				borderColor: ld.hexcolor, backgroundColor: ld.hexcolor,
				yAxisID: ld.prefix,
			})),
		},
		options: {
			responsive: true,
			interaction: {mode: "index", intersect: false},
			stacked: false,
			scales: Object.fromEntries(msg.defns.map((ld, i) => [ld.prefix, {
				type: "linear",
				display: i < 2,
				position: i % 2 ? "right" : "left",
				grid: i ? {drawOnChartArea: false} : { },
			}])),
		}
	});
	else {
		//TODO: This is a bit noisy; it thinks that everything moved vertically, when
		//actually they all moved horizontally. I can't be the first person to have a
		//real-time update like this; what's the best way to do it?
		//Maybe I should just disable the animation.
		chart.data.datasets.forEach((ds, i) => {
			ds.data = msg.plots[i].map((val, pos) => [pos + 1, val]);
		});
		chart.data.labels = msg.times;
		chart.update();
	}
}

ws_sync.connect(ws_group, {
	ws_config: {quiet: {msg: 1}},
	ws_host: "gideon.mustardmine.com",
	ws_sendid: "Gideon",
	render: data => update(data, "Gideon"),
	sockmsg_graph, //Send the graphs through just the same.
});
