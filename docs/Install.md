# Installing MeshChat

MeshChat is distributed as an Itsy package (IPK file) to be installed on an
AREDN node. This is the simplest way to install MeshChat.

Simply download the MeshChat package to your compute and then access the
Administration panel in the AREDN's node setup. Under Package Management
you will have the option to upload a package. Once uploaded the MeshChat
system will be started within a couple of seconds.

Usually there is not really any configuration that needs to be done, but
review of the [configuration settings](../module/meshchatconfig.html) is
suggested.

Starting with `v2.12.0` the configuration of MeshChat occurs in the file
`/www/cgi-bin/meshchat_local.lua`. Any configuration settings that need
to be modified need to be entered into the `meshchat_local.lua` file and
not in the `meshchatconfig.lua` file that previous version used to
configure MeshChat. Making changes to `meshchatconfig.lua` will be lost
when MeshChat is upgraded or downgraded. Making changes to the configuration
still requires one to SSH into the node and edit `meshchat_local.lua`
directly.

## Setting the MeshChat Zone Name

MeshChat uses a zone name to locate other MeshChat servers running with
the same zone name. Once servers are added to the same zone name, they
will automatically synchronize their message databases with one another.
Setting the zone name is done in the AREDN node adminstration settings
under the advertised services.

After a new install of MeshChat the installation will randomly generate
a zone name and register it with the AREDN node. The service name
(i.e. zone name) can be changed to the desired zone name used by other
MeshChat servers. Once the service name has been saved, it is best to
reboot the AREDN node to insure that MeshChat is restarted with the
correct zone name.

## Installing MeshChat on Linux

The current distribution of MeshChat does not currently support Linux. In
order to run MeshChat on a Linux machine, one needs to download MeshChat
v1.0.2 and install it on the Linux machine. Once installed, the configuration
need to be updated to set the `api_host` setting to the hostname or IP
of an AREDN node that has the MeshChat API package installed.
