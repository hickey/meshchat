# Troubleshooting

This is a "living" document. It is attempted to keep it up to date with
any new problems and troubleshooting techniques. If you find something
missing, please create an [Issue](https://github.com/hickey/meshchat/issues/new/choose)
do describe what problem or issue is missing. Better yet is to fork the
MeshChat repository, update the documentation in the forked repository
and then generate a PR back to the official MeshChat repository. Your
efforts will be greatly appreciated.

It is important to realize that MeshChat is effectively two separate
programs: one that runs in your browser (the frontend code) and one that
runs on the AREDN node (the backend code or API). While it may not be
obvious which piece of code is having the problem, it generally can be
broken down as if there is an issue with the format of a message or it
being displayed in the browser then the frontend code should be investigated.
Otherwise the API should be investigated.

## Installation Issues

There is a known issue that if an older AREDN firmware is being upgraded,
any additional packages will need to be reinstalled after the node has
completed the firmware upgrade. This should not be the case for AREDN
firmware 3.23.8.0 or greater.

If it appears that the installation of the package did not completely
install or is not fully functional, check the node to determine how much
disk space is available. Generally one should plan on a minimum of 100 KB
of disk space for MeshChat to operate.

Package installation failures also generally have an error message displayed
above the upload button when there is a failure. This can help indicate
what the failure type was, so it should be reported back as a project
issue using the link above.

## Message Synchronization Issues

In order for messages to be synchronized between MeshChat instances, the
`meshchatsync` process needs to be running. Log into the node and execute
`ps | grep meshchatsync` to see if the process exists. If it is not
running, then one can start it with executing `/usr/local/bin/meshchatsync`.
Doing so will keep the process attached to the current terminal and any
error output will be displayed in the terminal. Once the terminal is
exited, the `meshchatsync` process will terminate. So after determining
that there are no errors being generated, it is best to reboot the node.
This will allow `meshchatsync` to startup normally with no manual
intervention.

If it appears that `meshchatsync` is operating correctly, then the next
item to check is that the message database exists and messages are being
written to it. On an AREDN node, the message database is normally located
in `/tmp/meshchat`. Check for a `messages.<ZONE NAME>`. If the message
database does exist, post a new message in the MeshChat instance on the
node and insure that the message gets written to the message database.

Also insure that the message database has write permissions on the file.

