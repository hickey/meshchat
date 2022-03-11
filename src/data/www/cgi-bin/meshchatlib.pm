BEGIN { push @INC, '/www/cgi-bin', '/usr/lib/cgi-bin' }

use meshchatconfig;

our $version = '1.02';

$messages_db_file = $messages_db_file_orig . '.' . zone_name();

if ( $platform eq 'node' && -d '/mnt/usb/meshchat/files' ) {
    $local_files_dir = '/mnt/usb/meshchat/files';
}

sub dbg {
    my $txt = shift;

    if ( $debug == 1 ) { print STDERR "$txt\n"; }
}

# flock based locking. We always lock with this before we read or
# write to any files to prevent things from stomping on each other
# A lot of things are in flight at a given time so this is crucial

sub get_lock {
    if (!-e $lock_file) {
        `touch $lock_file`;
    }

    open( $lock_fh, '<' . $lock_file );

    if ( flock( $lock_fh, 2 ) ) {
        return;
    }
    else {
        print '{"status":500, "response":"Could not get lock"}';
        die('could not get lock');
    }
}

sub release_lock {
    #flock( $lock_fh, LOCK_UN );
    close($lock_fh);
}

# Get the name on the local node. For Raspberry Pi we use the hostname.
# For AREDN nodes we get the config node name

sub node_name {
    if ( $platform eq 'node' ) {
        return lc( nvram_get("node") );
    }
    elsif ( $platform eq 'pi' ) {
        open( HST, "/etc/hostname" );
        my $hostname = <HST>;
        close(HST);

        chomp($hostname);

        if ( $hostname eq '' ) {
            $hostname = `hostname`;
            chomp($hostname);
        }

        return lc($hostname);
    }
}

# Returns a md5 of a file. This is added to the HTTP response header
# so the client and validiate the file integrity

sub file_md5 {
    my $file = shift;

    if ( !-e $file ) { return ''; }

    my $output = `md5sum $file`;

    # Fix to work on OSX

    if ( $output eq '' ) {
        $output = `md5 -r $file`;
    }

    my @parts = split( /\s/, $output );

    return $parts[0];
}

# Returns the size of a file

sub file_size {
    my $file = shift;

    my @stats = stat($file);

    return $stats[7];
}

# Returns the file time stamp as epoch

sub file_epoch {
    my $file = shift;

    my @stats = stat($file);

    return $stats[9];
}

# Returns the cache version of the message db

sub get_messages_db_version {
    open( VER, $messages_version_file );
    my $ver = <VER>;
    chomp($ver);
    close(VER);

    return $ver;
}

# Calculate and save the message db version

sub save_messages_db_version {
    open( VER, '>' . $messages_version_file );
    print VER messages_db_version() . "\n";
    close(VER);

    chmod( 0666, $messages_version_file );
}

# Calculate the message db by converting the message id from hex to
# decimnal and adding all the ids together

sub messages_db_version {
    my $sum = 0;

    open( MSG, $messages_db_file );
    while (<MSG>) {
        my $line = $_;
        chomp($line);

        my @parts = split( "\t", $line );

        if ( $parts[0] =~ /[0-9a-f]/ ) {
            $sum += hex( $parts[0] );
        }
    }
    close(MSG);

    return $sum;
}

# Returns the free, available, total, etc stats of the filesystem the
# file sharing folder is located on

sub file_storage_stats {

    #my $stats = `df | grep /tmp | awk '{print $2} {print $3}'`;
    my @lines = `df -k $local_files_dir`;

    my ( $dev, $blocks, $used, $available ) = split( /\s+/, $lines[1] );

    $used      = $used * 1024;
    $available = $available * 1024;

    $total = $used + $available;

    my $local_files_bytes = 0;

    if ( $platform eq 'pi' ) {
        $max_file_storage  = $total * 0.95;
        $local_files_bytes = $used;
    }

    if ( $platform eq 'node' ) {
        get_lock();

        opendir( my $dh, $local_files_dir );
        my $file;

        while ( $file = readdir($dh) ) {
            if ( $file !~ /^\./ ) {
                $local_files_bytes += file_size( $local_files_dir . '/' . $file ),;
            }
        }
        closedir($dh);

        release_lock();
    }

    if ( ( $max_file_storage - $local_files_bytes ) < 0 ) {
        $local_files_bytes = $max_file_storage;
    }

    return {
        total      => $total,
        used       => $used,
        files      => $local_files_bytes,
        files_free => $max_file_storage - $local_files_bytes,
        allowed    => $max_file_storage
    };
}

# Return a list of nodes that should be polled for new messages. AREDN nodes
# and Raspberry Pi have their own functions.

sub node_list {
    my $nodes;

    if ( $platform eq 'node' ) {
        $nodes = mesh_node_list();
    }
    else {
        $nodes = pi_node_list();
    }

    push( @$nodes, @$extra_nodes );

    foreach my $node (@$nodes) {
        dbg "$$node{platform} $$node{node} $$node{port}\n";
    }

    dbg "\n\n";

    return $nodes;
}

# Returns a list of nodes to poll for Raspberry Pi. We get list of nodes via HTTP
# to an AREDN node that has mesh chat installed. We need to do it this way as there
# is no external API right now to get the service list from OLSR off node

sub pi_node_list {
    dbg "pi_node_list";

    my $local_node = node_name();

    my $zone_name = zone_name();

    dbg "ZONE: $zone_name";

    my @output = `curl --retry 0 --connect-timeout $connect_timeout "http://$local_meshchat_node:8080/cgi-bin/meshchat?action=meshchat_nodes&zone_name=$zone_name" 2> /dev/null`;

    my $nodes = [];

    foreach my $line (@output) {
        my ( $node, $port ) = split( "\t", $line );

        if ( lc($local_node) eq lc($node) ) { next; }

        if ( $port == 8080 ) {
            push( @$nodes, { platform => 'node', node => lc($node) } );
        }
        else {
            push( @$nodes, { platform => 'pi', node => lc($node) } );
        }
    }

    return $nodes;
}

# Returns the node list to poll by parsing the OLSR services and finding nodes that
# have the same zone name as this node

sub mesh_node_list {
    dbg "mesh_node_list";

    my $local_node = node_name();

    my $zone_name = zone_name();

    dbg "ZONE: $zone_name";

    my $nodes = [];

    foreach (`grep -i "/meshchat|" /var/run/services_olsr | grep \$'|$zone_name\t'`) {
        chomp;
        if ( $_ =~ /^http:\/\/(.*)\:(\d+)\// ) {
            if ( lc($local_node) eq lc($1) ) { next; }

            if ( $2 == 8080 ) {
                push( @$nodes, { platform => 'node', node => lc($1), port => $2 } );
            }
            else {
                push( @$nodes, { platform => 'pi', node => lc($1), port => $2 } );
            }
        }
    }

    return $nodes;
}

# Returns the zone that this nodes belongs too. Seperate functions for AREDN and Pi.

sub zone_name {
    if ( $platform eq 'node' ) {
        return node_zone_name();
    }
    else {
        return pi_zone_name();
    }
}

# Get the AREDN zone by looking for the service name given to mesh chat on the local node

sub node_zone_name {
    my $service = `grep ":8080/meshchat|" /var/run/services_olsr | grep "my own"`;

    if ( $service =~ /\|tcp\|(.*?)\t/ ) {
        return $1;
    }
    else {
        return "MeshChat";
    }
}

# Returns the zone configured in meshchatconfig.pm

sub pi_zone_name {
    return $pi_zone;
}

# Process the action scripts for a new message either from the UI or from polling
# Action scripts are ran asyncronously. meshchat_action.pl reads /etc/meshchat_actions.conf
# and loops over that config file to find any matches. If a match is found then
# meshchat_script.pl will execute the script with a timeout and log the results

sub process_message_action {
    my $line = shift;

    dbg "LINE: $line";

    if ( $platform ne 'pi' ) { return; }

    if ( !-e $action_conf_file ) { return; }

    chomp($line);

    my ( $id, $epoch, $message, $call_sign, $node, $platform, $channel ) = split( /\t/, $line );

    $message = unpack_message($message);

    my $action_file = "$meshchat_path/$id";

    dbg "action file: $action_file\n";

    open( FILE, ">$action_file" );
    print FILE "$id\t$epoch\t$message\t$call_sign\t$node\t$platform\t$channel\n";
    close(FILE);

    dbg "running action\n";

    `perl /usr/local/bin/meshchat_action.pl $action_file > /tmp/mechchat_action.log 2>&1 &`;
    chmod( 0666, '/tmp/mechchat_action.log' );
}

# Save a error message when processing an action script to the log file.

sub action_error_log {
    my $text = shift;

    require POSIX;

    open( LOG, ">>$action_error_log_file" );
    print LOG strftime( "%F %T", localtime $^T );
    print LOG "\t$text\n";
    close(LOG);
}

# Returns a random 8 hex character hash. This is used for messages ids in the db

sub hash {
    my $string = time() . int( rand(99999) );

    my $hash = `echo $string | md5sum`;

    # Fix to work on OSX

    if ( $hash eq '' ) {
        $hash = `echo $string | md5 -r`;
    }

    $hash =~ s/\s*\-//g;

    chomp($hash);

    $hash = substr( $hash, 0, 8 );

    return $hash;
}

# Unpack a message from the message db.

sub unpack_message {
    my $message = shift;

    $message =~ s/\\n/\n/g;
    $message =~ s/\\"/\"/g;

    return $message;
}

# Trim the message db by removing the oldest messages first to be at the
# allowed message count

sub trim_db {
    get_lock();

    dbg "trim_db";

    my $line_count = 0;

    # Get a count of the lines
    open( MSG, $messages_db_file );
    while (<MSG>) {
        $line_count++;
    }
    close(MSG);

    if ( $line_count <= $max_messages_db_size ) {
        dbg "nothing to trim $line_count";
        return;
    }

    my $lines_to_trim = $line_count - $max_messages_db_size;
    $line_count = 1;

    dbg "trimming $lines_to_trim lines";

    open( NEW, ">$meshchat_path/shrink_messages" );
    open( OLD, $messages_db_file );

    while (<OLD>) {
        my $line = $_;

        if ( $line_count > $lines_to_trim ) {
            print NEW $line;
        }

        $line_count++;
    }

    #print "Removed $deleted_bytes\n";

    close(OLD);
    close(NEW);

    unlink($messages_db_file);
    `cp $meshchat_path/shrink_messages $messages_db_file`;
    chmod( 0666, $messages_db_file );
    unlink( $meshchat_path . '/shrink_messages' );

    release_lock();
}

sub uri_unescape {

    # Note from RFC1630:  "Sequences which start with a percent sign
    # but are not followed by two hexadecimal characters are reserved
    # for future extension"
    my $str = shift;
    if ( @_ && wantarray ) {

        # not executed for the common case of a single argument
        my @str = ( $str, @_ );    # need to copy
        for (@str) {
            s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
        }
        return @str;
    }
    $str =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg if defined $str;
    $str;
}

sub url_escape {
    my ($rv) = @_;
    $rv =~ s/([^A-Za-z0-9])/sprintf("%%%2.2X", ord($1))/ge;
    return $rv;
}

sub sort_db {
    get_lock();

    my $messages = [];

    open( MSG, $messages_db_file );
    while (<MSG>) {
        my $line = $_;

        #chomp($line);

        my @parts = split( "\t", $line );

        my $msg = {
            epoch => $parts[1],
            id    => hex( $parts[0] ),
            line  => $line
        };

        push( @$messages, $msg );
    }
    close(MSG);

    @$messages =
      sort { $a->{epoch} <=> $b->{epoch} or $a->{id} <=> $b->{id} } @$messages;

    open( MSG, ">$messages_db_file" );
    foreach my $msg (@$messages) {
        print MSG $$msg{line};
    }
    close(MSG);

    release_lock();
}

#### perlfunc.pm

sub nvram_get {
    my ($var) = @_;
    return "ERROR" if not defined $var;
    chomp( $var = `uci -c /etc/local/uci/ -q get hsmmmesh.settings.$var` );
    return $var;
}

$stdinbuffer = "";

sub fgets {
    my ($size) = @_;
    my $line = "";
    while (1) {
        unless ( length $stdinbuffer ) {
            return "" unless read STDIN, $stdinbuffer, $size;
        }
        my ( $first, $cr ) = $stdinbuffer =~ /^([^\n]*)(\n)?/;
        $cr = "" unless $cr;
        $line .= $first . $cr;
        $stdinbuffer = substr $stdinbuffer, length "$first$cr";
        if ( $cr or length $line >= $size ) {
            if (0) {
                $line2 = $line;
                $line2 =~ s/\r/\\r/;
                $line2 =~ s/\n/\\n/;
                push @parse_errors, "[$line2]";
            }
            return $line;
        }
    }
}

# read postdata
# (from STDIN in method=post form)
sub read_postdata {
    print STDERR "read_postdata\n$ENV{REQUEST_METHOD}\n$ENV{REQUEST_METHOD}";
    if ( $ENV{REQUEST_METHOD} != "POST" || !$ENV{REQUEST_METHOD} ) { return; }
    my ( $line, $parm, $file, $handle, $tmp );
    my $state = "boundary";
    my ($boundary) = $ENV{CONTENT_TYPE} =~ /boundary=(\S+)/ if $ENV{CONTENT_TYPE};
    my $parsedebug = 0;
    push( @parse_errors, "[$boundary]" ) if $parsedebug;
    while ( length( $line = fgets(1000) ) ) {
        $line =~ s/[\r\n]+$//;    # chomp doesn't strip \r!
        print STDERR "[$state] $line<br>\n";

        if ( $state eq "boundary" and $line =~ /^--$boundary(--)?$/ ) {
            last if $line eq "--$boundary--";
            $state = "cdisp";
        }
        elsif ( $state eq "cdisp" ) {
            my $prefix = "Content-Disposition: form-data;";
            if ( ( $parm, $file ) = $line =~ /^$prefix name="(\w+)"; filename="(.*)"$/ ) {    # file upload
                $parms{$parm} = $file;
                if   ($file) { $state = "ctype" }
                else         { $state = "boundary" }
            }
            elsif ( ($parm) = $line =~ /^$prefix name="(\w+)"$/ ) {                           # form parameter
                $line = fgets(10);
                push( @parse_errors, "not blank: '$line'" ) unless $line eq "\r\n";
                $line = fgets(1000);
                $line =~ s/[\r\n]+$//;
                $parms{$parm} = $line;
                $state = "boundary";
            }
            else {                                                                            # oops, don't know what this is
                push @parse_errors, "unknown line: '$line'";
            }
        }
        elsif ( $state eq "ctype" )                                                           # file upload happens here
        {
            push( @parse_errors, "unexpected: '$line'" ) unless $line =~ /^Content-Type: /;
            $line = fgets(10);
            push( @parse_errors, "not blank: '$line'" ) unless $line eq "\r\n";
            $tmp = "";
            system "mkdir -p $tmp_upload_dir";
            open( $handle, ">$tmp_upload_dir/file" );
            while (1) {

                # get the next line from the form
                $line = fgets(1000);
                last unless length $line;
                last if $line =~ /^--$boundary(--)?\r\n$/;

                # make sure the trailing \r\n doesn't get into the file
                print $handle $tmp;
                $tmp = "";
                if ( $line =~ /\r\n$/ ) {
                    $line =~ s/\r\n$//;
                    $tmp = "\r\n";
                }
                print $handle $line;
            }
            close($handle);
            last if $line eq "--$boundary--\r\n";
            $state = "cdisp";
        }
    }

    push( @parse_errors, `md5sum $tmp_upload_dir/file` ) if $parsedebug and $handle;
}

1;
