import {lindt, replace_content, on} from "https://rosuav.github.io/choc/factory.js";
const {} = lindt; //autoimport
import {simpleconfirm} from "$$static||utils.js$$";

export function render(data) {
	replace_content("#queueinfo", [
	]);
}

on("click", ".choose", simpleconfirm("Add this to the queue?", e => {
	ws_sync.send({cmd: "choose", selection: e.match.closest_data("selection")});
}));
