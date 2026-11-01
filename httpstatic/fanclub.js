import {lindt, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {} = lindt; //autoimport
import {simpleconfirm, form_values} from "$$static||utils.js$$";

export function render(data) {
	if (data.title) replace_content("#clubtitle", data.title);
}

on("submit", "#managedlg form", e => ws_sync.send(form_values(e.match, {cmd: "configure"})));
