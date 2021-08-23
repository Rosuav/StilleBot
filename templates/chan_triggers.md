# Triggered responses for $$channel$$

Every chat message is checked against these triggers (in order). All matching
responses will be sent. Unlike [commands](commands), triggers do not require
that the command name be at the start of the message; they can react to any
word or phrase anywhere in the message. They can also react to a variety of
other aspects of the message, including checking whether the person is a mod,
by using appropriate conditionals. Any response can be given, as per command
handling.

To respond to special events such as subscriptions, see [Special Triggers](specials).

Channel moderators may add and edit these responses below.

ID          | Response | -
------------|----------|----
-           | $$loadingmsg$$
{: #triggers}

$$save_or_login$$

> ### Available trigger types:
> Type | Description
> -----|------------
> $$templates$$
>
> Customize as desired, or use as-is.
{: tag=dialog #templates}

<style>
table {width: 100%;}
th, td {width: 100%;}
dialog td:last-of-type {width: 100%;}
th:first-of-type, th:last-of-type, td:first-of-type, td:last-of-type {width: max-content;}
td:nth-of-type(2n+1):not([colspan]) {white-space: nowrap;}
.gap {height: 1em;}
td ul {margin: 0;}
</style>
