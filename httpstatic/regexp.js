import {choc, set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {BR, CODE, SPAN} = choc; //autoimport

function send() {ws_sync.send({cmd: "test", regexp: DOM("#regexp").value, text: DOM("#text").value});}
on("input", "#regexp,#text", send);
send();

export function sockmsg_testresult(msg) {
	if (msg.error) set_content("#result", msg.error).className = "regex-error";
	else if (msg.matches) set_content("#result", msg.matchtext.map((m, i) =>
		!i ? ["Matches ", SPAN({class: "regex-match"}, m)] //The main match
		: [BR(), CODE("{regexp" + i + "}"), " - ", SPAN({class: "regex-match"}, m)] //Any subexpression matches
	)).className = "";
	else set_content("#result", "Doesn't match").className = "regex-nomatch";
}
