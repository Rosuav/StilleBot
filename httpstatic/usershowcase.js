import {choc, set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {DIV, IMG, LABEL, STYLE} = choc; //autoimport
import {ensure_font} from "$$static||utils.js$$";

export function render(data) {
	if (data.data) {
		//Primary reconfiguration
		set_content("#display", [
			STYLE("label {" + (data.data.text_css||"") + "}"),
			data.data.slots.split(" ").map(slot => DIV({class: "box", id: "slot-" + slot}, [
				DIV({class: "profile-pic"}, IMG({src: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNgAAIAAAUAAen63NgAAAAASUVORK5CYII="})),
				//Not really sure why this is a label but I'll keep it for now
				LABEL([
					DIV({class: "title"}, slot), //TODO: Allow the slots to be labelled nicely
					DIV({class: "name"}),
				]),
			])),
		]);
		ensure_font(data.data.font);
		ensure_font('"Noto Color Emoji"'); //Hack - ensure that emojis work
	}
}
