import {choc, set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {P, SPAN} = choc; //autoimport

const attrs = {cpu: "CPU", gpu: "GPU", vram: "VRAM", enc: -1, dec: -1, spinner: -1};

set_content("#content", ["Gideon", "Sikorsky"].map(id => P({id}, [
	SPAN({class: "label"}, id + ": "),
	Object.keys(attrs).map(name => attrs[name] !== -1 && [attrs[name] + ": ", SPAN({class: name + " percent"}), " "]),
	"Enc: ", SPAN({class: "enc percent"}), ":", SPAN({class: "dec percent"}), " ",
	SPAN({class: "spinner"}),
])));
function minify() {
	const content = DOM("#content");
	DOM("main").replaceWith(content, DOM("main style"));
	content.style.margin = "0";
}
if (location.hash === "#mini") minify();
on("click", 'a[href="#mini"]', minify);

function update(data, par) {
	Object.keys(data).forEach(name => attrs[name] && set_content(par + " ." + name, ""+data[name]));
}
export function render(data) {update(data, "#Sikorsky");}
export const ws_host = "sikorsky.mustardmine.com";
export const ws_config = {quiet: {msg: 1}};

ws_sync.connect("", {
	ws_config: {quiet: {msg: 1}},
	ws_host: "gideon.mustardmine.com",
	render: data => update(data, "#Gideon"),
});
