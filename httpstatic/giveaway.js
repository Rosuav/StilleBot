import choc, {set_content, DOM, fix_dialogs} from "https://rosuav.github.io/shed/chocfactory.js";
const {DIV, LI} = choc;
fix_dialogs({close_selector: ".dialog_cancel,.dialog_close", click_outside: true});

set_content("#existing", rewards.map(r => LI(r.title)));
