import {choc, set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {H3, LI, P, SPAN, UL} = choc; //autoimport

const sharedattrs = {cpu: "CPU", ram: "RAM", spinner: -1};
const attrs = {
	Gideon: {...sharedattrs},
	Sikorsky: {...sharedattrs, gpu: "GPU", vram: "VRAM", enc: -1, dec: -1},
};

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
export function sockmsg_graph(msg) {
	const fig = DOM("#graph"); //Absent in mini-mode
	if (!fig) return;
	DOM("#graph img").src = msg.image;
	set_content("#graph figcaption", [
		H3("Load peaks"),
		UL(msg.defns.map((defn, i) => LI([
			SPAN({style: "color: rgb(" + defn.color.join(",") + ")"}, defn.prefix), " ", ""+msg.peaks[i], " ", defn.unit,
		]))),
	]);
}

ws_sync.connect("", {
	ws_config: {quiet: {msg: 1}},
	ws_host: "gideon.mustardmine.com",
	render: data => update(data, "Gideon"),
});
