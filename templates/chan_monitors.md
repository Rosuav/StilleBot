# Monitors for $$channel$$

<style>
input[type=number] {width: 4em;}
.preview-frame {
	border: 1px solid black;
	padding: 4px;
}
.preview-bg {padding: 6px;}
</style>

<table border=1 id=monitors>
<tr><th>Text</th><th>Style</th><th>Actions</th><th>Preview</th><th>Link</th></tr>
<tr><td><form id=add><input size=40 name=text></form></td><td><input type=submit form=add value="Add"></td><td></td><td></td><td></td></tr>
</table>

The text can (and should!) incorporate variables, eg <code>$foo$</code>. Whenever the variable changes, this will update.

<script type=module src="$$static||monitors.js$$"></script>
