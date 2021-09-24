import choc, {set_content, DOM, fix_dialogs} from "https://rosuav.github.io/shed/chocfactory.js";
const {LI, SPAN} = choc;

export function render(state) { }

on("input", "#regexp,#text", e => {
	ws_sync.send({cmd: "test", regexp: DOM("#regexp").value, text: DOM("#text").value});
});

export function sockmsg_testresult(msg) {
	console.log("Test result", msg);
}
