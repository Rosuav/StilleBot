# Monitors for $$channel$$

<table border=1 id=monitors>
<tr><th>Text</th><th>Actions</th><th>Link</th></tr>
<tr><td><form id=add><input size=40 name=text></form></td><td><input type=submit form=add value="Add"></td><td></td></tr>
</table>

The text can (and should!) incorporate variables, eg <code>$foo$</code>. Whenever the variable changes, this will update.

<script>let monitors = $$monitors$$;</script>
<script type=module src="$$static||monitors.js$$"></script>
