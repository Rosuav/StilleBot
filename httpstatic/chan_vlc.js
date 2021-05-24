import choc, {set_content, DOM, fix_dialogs} from "https://rosuav.github.io/shed/chocfactory.js";
const {A, BUTTON, INPUT, LI, TR, TD} = choc;
fix_dialogs({close_selector: ".dialog_cancel,.dialog_close", click_outside: true});

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

function waitlate(wait_time, late_time, confirmdesc, callback) {
	//Assumes that this is attached to a button click. Other objects
	//and other events may work but are not guaranteed.
	let wait = 0, late = 0, timeout = 0, btn, orig;
	function reset() {
		clearTimeout(timeout);
		set_content(btn, orig).disabled = false;
		wait = late = timeout = 0;
	}
	return e => {
		const t = +new Date;
		if (t > wait && t < late) {
			reset();
			callback(e);
			return;
		}
		wait = t + wait_time; late = t + late_time;
		btn = e.match; orig = btn.innerText;
		setTimeout(() => btn.disabled = false, wait_time);
		timeout = setTimeout(reset, late_time);
		set_content(btn, confirmdesc).disabled = true;
	};
}
on("click", "#authreset", waitlate(2000, 10000, "Really reset credentials?", e => ws_sync.send({cmd: "authreset"})));
