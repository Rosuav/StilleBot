import {choc, set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {DIV, IMG, LABEL, STYLE} = choc; //autoimport
import {ensure_font} from "$$static||utils.js$$";

const TRANSPARENT_IMAGE = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNgAAIAAAUAAen63NgAAAAASUVORK5CYII=";

let state = { }; //The variable group from the server, with the name prefixes removed
function update_display() {
	document.querySelectorAll(".box").forEach(box => {
		const slot = box.dataset.slot;
		//HACK: Seize the Crown uses "crownholder:name"/"crownholder:avatar" rather than "crown:holder"/"crown:holder:avatar"
		const name = slot === "-" ? "name" : slot;
		const av = slot === "-" ? "avatar" : slot + ":avatar";
		box.querySelector(".profile-pic img").src = state[av] || TRANSPARENT_IMAGE;
		let mode = state[slot + ":mode"];
		set_content(box.querySelector(".name"), state[name]).className = mode ? "name mode-" + mode : "name";
	});
}

export function render(data) {
	if (data.data) {
		//Primary reconfiguration
		set_content("#display", [
			STYLE(".text {" + (data.data.text_css||"") + "}"),
			data.data.slots.map(slot => DIV({class: "box", "data-slot": slot.id}, [
				DIV({class: "profile-pic"}, IMG({src: TRANSPARENT_IMAGE})),
				DIV({class: "text"}, [
					DIV({class: "title"}, slot.label),
					DIV({class: "name"}),
				]),
			])),
		]);
		ensure_font(data.data.font);
		ensure_font('"Noto Color Emoji"'); //Hack - ensure that emojis work
		state = data.data.vars;
		update_display();
	}
	if (data.groupvar) {
		state[data.groupvar] = data.value;
		update_display();
	}
}
