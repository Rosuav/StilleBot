import choc, {set_content, DOM, fix_dialogs} from "https://rosuav.github.io/shed/chocfactory.js";
const {A, BUTTON, INPUT, LI, TR, TD} = choc;
fix_dialogs({close_selector: ".dialog_cancel,.dialog_close", click_outside: "formless"});
import {waitlate} from "$$static||utils.js$$";

export const render_parent = DOM("#blocks tbody");
export function render_item(block) {
	return TR({"data-id": block.id}, [
		TD(INPUT({value: block.id, className: "path", size: 80})),
		TD(INPUT({value: block.desc, className: "desc", size: 80})),
		TD([BUTTON({type: "button", className: "save"}, "Save")]),
	]);
}

export function render(data) {
	if (data.recent) { //Won't be present on narrow updates
		set_content("#nowplaying", data.playing ? "Now playing: " + data.current : "Not playing or integration not active");
		set_content("#recent", data.recent.map(track => LI(track)));
	}
}

on("click", "button.save", e => {
	const tr = e.match.closest("tr");
	ws_sync.send({cmd: "update", "id": tr.dataset.id,
		path: tr.querySelector(".path").value,
		desc: tr.querySelector(".desc").value,
	});
});

on("click", "#authreset", waitlate(2000, 10000, "Really reset credentials?", e => ws_sync.send({cmd: "authreset"})));
