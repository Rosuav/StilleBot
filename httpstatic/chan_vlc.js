import choc, {set_content, DOM, fix_dialogs} from "https://rosuav.github.io/shed/chocfactory.js";
const {A, BUTTON, INPUT, LI, TR, TD} = choc;
fix_dialogs({close_selector: ".dialog_cancel,.dialog_close", click_outside: true});

export const render_parent = DOM("#blocks tbody");
export function render_item(block) {
	return TR({"data-id": block.id}, [
		TD(INPUT({value: block.id, className: "path", size: 80})),
		TD(INPUT({value: block.desc, className: "desc", size: 80})),
		TD([
			//TODO: Replace all this with a websocket update message
			BUTTON({type: "button", onclick: e => {
				const tr = e.currentTarget.closest("tr");
				fetch("vlc?saveblock", {
					method: "POST",
					body: JSON.stringify({
						path: tr.querySelector(".path").value,
						desc: tr.querySelector(".desc").value,
					}),
					headers: {"content-type": "application/json"},
					credentials: "include",
				}).then(r => r.json())
				.then(data => {
					blocks = data.blocks;
					unknowns = data.unknowns;
					update_blocks_unknowns();
				});
			}}, "Save"),
		]),
	]);
}

export function render(data) {
	set_content("#nowplaying", data.playing ? "Now playing: " + data.current : "Not playing or integration not active");
	set_content("#recent", data.recent.map(track => LI(track)));
}

