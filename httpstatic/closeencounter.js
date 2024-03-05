//Need a clean way to have this file come from zz_local. It doesn't belong in repo.
import {lindt, replace_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {BUTTON, FIELDSET, IMG, INPUT, LEGEND, TABLE, TD, TR} = lindt; //autoimport

export function render(data) {
	if (data.boardsizes) return replace_content("#display", [
		FIELDSET({class: "startnew"}, [
			LEGEND("Start new exploration!"),
			data.boardsizes.map(sz => BUTTON({class: "start", "data-size": sz}, sz + " x " + sz)),
		]),
	]);
	return replace_content("#display", [
		FIELDSET([
			LEGEND("Your instruments have constructed the following image..."),
			IMG({src: data.display || ""}),
		]),
		FIELDSET([
			LEGEND("Adjust your alignment angles here:"),
			TABLE({border: 1}, data.selections.map((row, r) => TR(
				row.map((sel, c) => TD(
					INPUT({type: "number", value: ""+sel, min: "0", class: "selection", "data-r": r, "data-c": c})
				))
			))),
		]),
	]);
}

on("click", ".start", e => ws_sync.send({cmd: "start", size: e.match.dataset.size}));
export function sockmsg_redirect(msg) {location.href = msg.href;}

on("change", ".selection", e => ws_sync.send({cmd: "select", r: e.match.dataset.r, c: e.match.dataset.c, setting: e.match.value}));
