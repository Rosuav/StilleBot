import choc, {set_content, DOM, fix_dialogs} from "https://rosuav.github.io/shed/chocfactory.js";
const {A, BR, BUTTON, INPUT, DIV, DETAILS, LABEL, SUMMARY, TABLE, TR, TH, TD, SELECT, OPTION, FIELDSET, LEGEND, CODE} = choc;
fix_dialogs({close_selector: ".dialog_cancel,.dialog_close", click_outside: true});

on("input", "#content", e => {
	console.log("Change!");
	ws_sync.send({cmd: "update", id: "0", content: e.match.value});
});

export function render(data) {
	if (data.id) {
		console.log("Partial update");
	}
	else {
		console.log("Full/initial update");
		DOM("#content").value = data.items.map(item => item.content).join("\n");
	}
}
