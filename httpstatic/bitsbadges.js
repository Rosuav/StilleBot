import choc, {set_content, DOM, fix_dialogs} from "https://rosuav.github.io/shed/chocfactory.js";
const {DIV, LI, OL} = choc; //autoimport

function update_leaders(periodicdata) {
	set_content("#leaders", periodicdata.map(period => DIV([
		period[0],
		period[1].length ? OL(period[1].map(person => LI(
			person.user_name
		))) : " (no data)",
	])));
}
update_leaders(periodicdata);
