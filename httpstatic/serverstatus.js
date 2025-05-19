import {choc, set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {BR, EM, H3, LI, P, SPAN, UL} = choc; //autoimport

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
}
export function render(data) {update(data, "Sikorsky");}
export const ws_host = "sikorsky.mustardmine.com";
export const ws_config = {quiet: {msg: 1}};
ws_sync.send({cmd: "graph"});

function number(n) {
	if (n < 0) return "-" + number(-n);
	if (n === Math.floor(n)) return ""+Math.floor(n);
	//Round non-integers to two decimal places
	return ""+(Math.round(n * 100) / 100);
}

export function sockmsg_graph(msg) {
	const fig = DOM("#graph figcaption"); //Absent in mini-mode
	if (!fig) return;
	set_content(fig, [
		H3("Load peaks (60 sec avg)"),
		UL(msg.defns.map((defn, i) => LI([
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

ws_sync.connect("", {
	ws_config: {quiet: {msg: 1}},
	ws_host: "gideon.mustardmine.com",
	render: data => update(data, "Gideon"),
});
