import choc, {set_content, DOM, fix_dialogs} from "https://rosuav.github.io/shed/chocfactory.js";
const {LI} = choc;
fix_dialogs({close_selector: ".dialog_cancel,.dialog_close", click_outside: true});

export function render(data) {
	set_content("#nowplaying", data.playing ? "Now playing: " + data.current : "");
	set_content("#recent", data.recent.map(track => LI(track)))
}
