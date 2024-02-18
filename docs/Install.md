# Installing MeshChat

MeshChat is distributed as an Itsy package (IPK file) to be installed on an
AREDN node. This is the simplest way to install MeshChat.

Simply download the MeshChat package to your compute and then access the
Administration panel in the AREDN's node setup. Under Package Management
you will have the option to upload a package. Once uploaded the MeshChat
system will be started within a couple of seconds.

Usually there is not really any configuration that needs to be done, but
review of the [configuration settings](../module/meshchatconfig.html) is
suggested. To make any configuration changes one needs to log into the
node using SSH and edit the file `/www/cgi-bin/meshchatconfig.lua`.

## Installing MeshChat on Linux

The current distribution of MeshChat does not currently support Linux. In
order to run MeshChat on a Linux machine, one needs to download MeshChat
v1.0.2 and install it on the Linux machine. Once installed, the configuration
need to be updated to set the `api_host` setting to the hostname or IP
of an AREDN node that has the MeshChat API package installed.
