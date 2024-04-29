import {choc, set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {} = choc; //autoimport

export function render(data) { }

on("click", "#deactivate", e => {
	document.querySelectorAll("[data-expect]").forEach(inp => inp.value = "");
	DOM("#deactivateaccount").disabled = true;
	DOM("#deactivatedlg").showModal();
});

on("input", "[data-expect]", e => {
	let valid = true;
	document.querySelectorAll("[data-expect]").forEach(inp => {
		if (inp.value !== inp.dataset.expect) valid = false;
	});
	DOM("#deactivateaccount").disabled = !valid;
});

on("click", "#deactivateaccount", e => {
	let valid = true;
	document.querySelectorAll("[data-expect]").forEach(inp => {
		if (inp.value !== inp.dataset.expect) valid = false;
	});
	if (!valid) return; //The button should have been disabled anyway, so don't bother giving feedback
	ws_sync.send({cmd: "deactivate"});
	DOM("#deactivatedlg").close();
});
