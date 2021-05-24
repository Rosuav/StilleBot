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

//Can I turn this wait/late system into a library function somewhere?
let confirm_authreset_wait = 0, confirm_authreset_late = 0, confirm_authreset_timeout = 0;
function reset_confirm_authreset() {
	clearTimeout(confirm_authreset_timeout);
	set_content("#authreset", "Reset credentials").disabled = false;
	confirm_authreset_wait = confirm_authreset_late = confirm_authreset_timeout = 0;
}
on("click", "#authreset", e => {
	const t = +new Date;
	if (t > confirm_authreset_wait && t < confirm_authreset_late) {
		reset_confirm_authreset();
		ws_sync.send({cmd: "authreset"});
		return;
	}
	const WAIT_TIME = 2000, LATE_TIME = 10000;
	confirm_authreset_wait = t + WAIT_TIME;
	confirm_authreset_late = t + LATE_TIME;
	const btn = e.match;
	setTimeout(() => btn.disabled = false, WAIT_TIME);
	confirm_authreset_timeout = setTimeout(reset_confirm_authreset, LATE_TIME);
	set_content(btn, "Really reset credentials?").disabled = true;
});
