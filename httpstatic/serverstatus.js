import {choc, set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {P, SPAN} = choc; //autoimport

const sharedattrs = {cpu: "CPU", spinner: -1};
const attrs = {
	Gideon: {...sharedattrs},
	Sikorsky: {...sharedattrs, gpu: "GPU", vram: "VRAM", enc: -1, dec: -1},
};

set_content("#content", ["Gideon", "Sikorsky"].map(id => {
	return P({id}, [
		SPAN({class: "label"}, id + ": "),
		Object.keys(attrs[id]).map(name => attrs[id][name] !== -1 && [attrs[id][name] + ": ", SPAN({class: name + " percent"}), " "]),
		attrs[id].enc && ["Enc: ", SPAN({class: "enc percent"}), ":", SPAN({class: "dec percent"}), " "],
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
}
export function render(data) {update(data, "Sikorsky");}
export const ws_host = "sikorsky.mustardmine.com";
export const ws_config = {quiet: {msg: 1}};

ws_sync.connect("", {
	ws_config: {quiet: {msg: 1}},
	ws_host: "gideon.mustardmine.com",
	render: data => update(data, "Gideon"),
});
