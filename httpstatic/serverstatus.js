import {choc, set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {SPAN} = choc; //autoimport

const attrs = {cpu: "CPU", gpu: "GPU", vram: "VRAM", enc: -1, dec: -1, spinner: -1};

set_content("#content", [
	Object.keys(attrs).map(id => attrs[id] !== -1 && [attrs[id] + ": ", SPAN({id, class: "percent"}), " "]),
	"Enc: ", SPAN({id: "enc", class: "percent"}), ":", SPAN({id: "dec", class: "percent"}), " ",
	SPAN({id: "spinner"}),
]);
if (location.hash === "#mini") {
	const content = DOM("#content");
	DOM("main").replaceWith(content, DOM("main style"));
	content.style.margin = "0";
}

export function render(data) {
	Object.keys(data).forEach(id => attrs[id] && set_content("#" + id, ""+data[id]));
}
export const ws_host = "sikorsky.mustardmine.com";

ws_sync.connect("", {
	ws_host: "gideon.mustardmine.com",
	render: data => console.log("Got data from gideon", data),
});
