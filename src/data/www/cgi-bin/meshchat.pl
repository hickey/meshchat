#!/usr/bin/perl

BEGIN { push @INC, '/www/cgi-bin', '/usr/lib/cgi-bin' }
use meshchatlib;
use meshchatconfig;

$| = 1;

my $start_time = time();

my %query;

my $node = node_name();

parse_params();

if ( $query{action} eq 'messages' ) {
    messages();
}
elsif ( $query{action} eq 'config' ) {
    config();
}
elsif ( $query{action} eq 'send_message' ) {
    send_message();
}
elsif ( $query{action} eq 'sync_status' ) {
    sync_status();
}
elsif ( $query{action} eq 'messages_raw' ) {
    messages_raw();
}
elsif ( $query{action} eq 'messages_md5' ) {
    messages_md5();
}
elsif ( $query{action} eq 'messages_download' ) {
    messages_download();
}
elsif ( $query{action} eq 'users_raw' ) {
    users_raw();
}
elsif ( $query{action} eq 'users' ) {
    users();
}
elsif ( $query{action} eq 'local_files_raw' ) {
    local_files_raw();
}
elsif ( $query{action} eq 'file_download' ) {
    file_download();
}
elsif ( $query{action} eq 'files' ) {
    files();
}
elsif ( $query{action} eq 'delete_file' ) {
    delete_file();
}
elsif ( $query{action} eq 'messages_version' ) {
    messages_version();
}
elsif ( $query{action} eq 'messages_version_ui' ) {
    messages_version_ui();
}
elsif ( $query{action} eq 'hosts' ) {
    hosts();
}
elsif ( $query{action} eq 'hosts_raw' ) {
    hosts_raw();
}
elsif ( $query{action} eq 'upload_file' ) {
    upload_file();
}
elsif ( $query{action} eq 'meshchat_nodes' ) {
    meshchat_nodes();
}
elsif ( $query{action} eq 'action_log' ) {
    action_log();
}
else {
    error('error no action');
}

#print STDERR "$query{action} took " . (time() - $start_time) . " secs\n";

sub parse_params {
    my $post_data;

    if ( length( $ENV{'QUERY_STRING'} ) > 0 ) {
        $post_data = $ENV{'QUERY_STRING'};
    }
    else {
        foreach my $data (<STDIN>) {
            $post_data .= $data;
        }
    }

    if ( length($post_data) > 0 ) {
        $buffer = $post_data;
        @pairs = split( /&/, $buffer );
        foreach $pair (@pairs) {
            ( $name, $value ) = split( /=/, $pair );
            $value =~ s/\+/ /g;
            $value =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
            $query{$name} = $value;
        }
    }
}

sub error {
    my $msg = shift;

    print "Content-type:text\r\n\r\n";
    print $msg;
}

sub config {
    print "Content-type:application/json\r\n\r\n";

    my $zone_name = zone_name();

    print "{\"version\":\"$version\",\"node\":\"$node\",\"zone\":\"$zone_name\"}";
}

sub json_encode_string {
  my $str = shift;
  $str =~ s!([\x00-\x1f\x{2028}\x{2029}\\"/])!$REVERSE{$1}!gs;
  return "\"$str\"";
}

sub messages {
    print "Content-type:application/json\r\n\r\n";

    my $messages = [];

    get_lock();

    open( MSG, $messages_db_file );
    while (<MSG>) {
        my $line = $_;
        chomp($line);

        my @parts = split( "\t", $line );

        #print "$line\n";

        if ( $parts[1] > 0 ) {
            push(
                @$messages,
                {
                    id        => $parts[0],
                    epoch     => $parts[1],
                    message   => unpack_message( $parts[2] ),
                    call_sign => $parts[3],
                    node      => $parts[4],
                    platform  => $parts[5],
                    channel   => $parts[6],
                }
            );
        }
    }
    close(MSG);

    my %users;

    open( USERS, $local_users_status_file );
    while (<USERS>) {
        my $line = $_;
        chomp($line);

        my @parts = split( "\t", $line );

        if ( $#parts > 2 ) { $users{ $parts[0] } = $line; }
    }
    close(USERS);

    my $found_user = 0;

    my $epoch = time();

    if ( $query{epoch} > $epoch ) { $epoch = $query{epoch}; }

    open( USERS, '>' . $local_users_status_file );
    foreach my $call_sign ( keys %users ) {
        if ( $call_sign eq $query{call_sign} ) {
            print USERS "$query{call_sign}\t$query{id}\t$node\t$epoch\t$platform\n";
            $found_user = 1;
        }
        else {
            print USERS "$users{$call_sign}\n";
        }
    }

    if ( $found_user == 0 ) {
        print USERS "$query{call_sign}\t$query{id}\t$node\t$epoch\t$platform\n";
    }

    close(USERS);

    release_lock();

    my @sorted = sort { $b->{epoch} <=> $a->{epoch} } @$messages;

    # JSON encoding data
    # Escaped special character map with u2028 and u2029
    my %ESCAPE = (
      '"'     => '"',
      '\\'    => '\\',
      '/'     => '/',
      'b'     => "\x08",
      'f'     => "\x0c",
      'n'     => "\x0a",
      'r'     => "\x0d",
      't'     => "\x09",
      'u2028' => "\x{2028}",
      'u2029' => "\x{2029}"
    );
    my %REVERSE = map { $ESCAPE{$_} => "\\$_" } keys %ESCAPE;

    for (0x00 .. 0x1f) {
      my $packed = pack 'C', $_;
      $REVERSE{$packed} = sprintf '\u%.4X', $_ unless defined $REVERSE{$packed};
    }

    my $json = '[';

    foreach my $message (@sorted) {
        my $str = $message->{message};
        $str =~ s!([\x00-\x1f\x{2028}\x{2029}\\"/])!$REVERSE{$1}!gs;

        $json .= '{"id":"' . $message->{id} . '","epoch":' . $message->{epoch} . ',"message":"' . $str . '","call_sign":"' . $message->{call_sign} . '","node":"' . $message->{node} . '","platform":"' . $message->{platform} . '","channel":"' . $message->{channel} . '"},';
    }

    if ( length($json) > 1 ) {
        chop($json);
    }

    $json .= ']';

    print $json;

    #print encode_json(\@sorted);
}

sub sync_status {
    print "Content-type:application/json\r\n\r\n";

    my $status = [];

    get_lock();

    open( STATUS, $sync_status_file );
    while (<STATUS>) {
        my $line = $_;
        chomp($line);

        my @parts = split( "\t", $line );

        push( @$status, { epoch => $parts[1], node => $parts[0] } );
    }
    close(STATUS);

    release_lock();

    my @sorted = sort { $b->{epoch} <=> $a->{epoch} } @$status;

    my $json = '[';

    foreach my $status (@sorted) {
        $json .= '{"epoch":' . $status->{epoch} . ',"node":"' . $status->{node} . '"},';
    }

    if ( length($json) > 1 ) {
        chop($json);
    }

    $json .= ']';

    print $json;
}

sub messages_raw {
    get_lock();

    my $md5 = file_md5($messages_db_file);

    print "Content-MD5: $md5\r\n";

    print "Content-type:text\r\n\r\n";

    open( MSG, $messages_db_file );
    while (<MSG>) {
        my $line = $_;
        print "$line";
    }
    close(MSG);

    release_lock();
}

sub messages_md5 {
    get_lock();

    my $md5 = file_md5($messages_db_file);

    print "Content-type:text\r\n\r\n";

    print $md5;

    release_lock();
}

sub messages_download {
    get_lock();

    my $md5 = file_md5($messages_db_file);

    print "Content-MD5: $md5\r\n";

    print "Content-Disposition: attachment; filename=messages.txt;\r\n";

    print "Content-type:text\r\n\r\n";

    open( MSG, $messages_db_file );
    while (<MSG>) {
        my $line = $_;
        print "$line";
    }
    close(MSG);

    release_lock();
}

sub file_download {
    my $file = uri_unescape( $query{file} );

    my $file_path = $local_files_dir . '/' . $file;

    if ( $file eq '' || !-e $file_path ) {
        error('no file');
        return;
    }

    get_lock();

    my $md5 = file_md5($file_path);

    print "Content-MD5: $md5\r\n";

    print "Content-Disposition: attachment; filename=\"$file\";\r\n";

    print "Content-type: application/octet-stream\r\n\r\n";

    open( FILE, $file_path );
    binmode FILE;

    while (1) {
        my $bytes = read( FILE, $data, 1024 * 8 );

        print STDERR "$bytes\n";

        print $data;

        if ( $bytes == 0 ) { last; }
    }

    close(FILE);

    release_lock();
}

sub users_raw {
    get_lock();

    my $md5 = file_md5($local_users_status_file);

    print "Content-MD5: $md5\r\n";

    print "Content-type:text\r\n\r\n";

    open( USERS, $local_users_status_file );
    while (<USERS>) {
        my $line = $_;
        print "$line";
    }
    close(USERS);    

    release_lock();
}

sub local_files_raw {
    get_lock();

    my $tmp_file = $meshchat_path . '/meshchat_files_local';

    open( FILES, '>' . $tmp_file );

    my @files;

    opendir( my $dh, $local_files_dir );
    my $file;

    while ( $file = readdir($dh) ) {
        if ( $file !~ /^\./ ) {
            push( @files, $file );
        }
    }
    closedir($dh);

    foreach my $file (@files) {
        my @stats = stat("$local_files_dir/$file");
        print FILES "$file\t$node:$ENV{SERVER_PORT}\t$stats[7]\t$stats[9]\t$platform\n";
    }

    close(FILES);

    my $md5 = file_md5($tmp_file);

    print "Content-MD5: $md5\r\n";

    print "Content-type:text\r\n\r\n";

    open( FILES, $tmp_file );
    while (<FILES>) {
        my $line = $_;
        print "$line";
    }
    close(FILES);

    unlink($tmp_file);

    release_lock();
}

sub pack_message {
    my $message = shift;

    $message =~ s/\n/\\n/g;
    $message =~ s/\"/\\"/g;

    return $message;
}

sub send_message {
    print "Content-type:application/json\r\n\r\n";

    my $message = pack_message( $query{message} );

    print STDERR $message;

    my $epoch = time();

    if ( $query{epoch} > $epoch ) { $epoch = $query{epoch}; }

    my $line = hash() . "\t$epoch\t$message\t$query{call_sign}\t" . $node . "\t$platform\t$query{channel}\n";

    print STDERR $line;

    get_lock();

    open( MSG, ">>" . $messages_db_file );
    print MSG $line;
    close(MSG);

    sort_db();

    trim_db();

    save_messages_db_version();

    release_lock();    

    if ($query{no_action} != 1) {
        process_message_action($line);
    }

    print '{"status":200, "response":"OK"}';
}

sub messages_version {
    my $ver = get_messages_db_version();

    print "Content-type:text\r\n\r\n";

    print $ver;
}

sub messages_version_ui {
    my $ver = get_messages_db_version();

    print "Content-type:application/json\r\n\r\n";

    print '{"messages_version":' . $ver . '}';

    get_lock();

    my %users;

    open( USERS, $local_users_status_file );
    while (<USERS>) {
        my $line = $_;
        chomp($line);

        my @parts = split( "\t", $line );

        if ( $#parts > 2 ) { $users{ $parts[0] } = $line; }
    }
    close(USERS);

    my $found_user = 0;

    my $epoch = time();

    if ( $query{epoch} > $epoch ) { $epoch = $query{epoch}; }

    open( USERS, '>' . $local_users_status_file );
    foreach my $call_sign ( keys %users ) {
        if ( $call_sign eq $query{call_sign} ) {
            print USERS "$query{call_sign}\t$query{id}\t$node\t$epoch\t$platform\n";
            $found_user = 1;
        }
        else {
            print USERS "$users{$call_sign}\n";
        }
    }

    if ( $found_user == 0 ) {
        print USERS "$query{call_sign}\t$query{id}\t$node\t$epoch\t$platform\n";
    }

    close(USERS);

    release_lock();
}

sub users {
    print "Content-type:application/json\r\n\r\n";

    my $users = [];

    get_lock();

    open( USERS, $local_users_status_file );
    while (<USERS>) {
        my $line = $_;
        chomp($line);

        my @parts = split( "\t", $line );

        #print "$line\n";

        if ( $parts[3] > 0 ) {
            push(
                @$users,
                {
                    epoch     => $parts[3],
                    id        => $parts[1],
                    call_sign => $parts[0],
                    node      => $parts[2],
                    platform  => $parts[4]
                }
            );
        }
    }
    close(USERS);

    open( USERS, $remote_users_status_file );
    while (<USERS>) {
        my $line = $_;
        chomp($line);

        my @parts = split( "\t", $line );

        #print "$line\n";

        if ( $parts[3] > 0 ) {
            push(
                @$users,
                {
                    epoch     => $parts[3],
                    id        => $parts[1],
                    call_sign => $parts[0],
                    node      => $parts[2],
                    platform  => $parts[4]
                }
            );
        }
    }
    close(USERS);

    release_lock();

    my @sorted = sort { $b->{epoch} <=> $a->{epoch} } @$users;

    #my @sorted = @$users;

    my $json = '[';

    foreach my $user (@sorted) {
        $json .= '{"epoch":' . $user->{epoch} . ',"id":"' . $user->{id} . '","call_sign":"' . $user->{call_sign} . '","node":"' . $user->{node} . '","platform":"' . $user->{platform} . '"},';
    }

    if ( length($json) > 1 ) {
        chop($json);
    }

    $json .= ']';

    print $json;

    #print encode_json(\@sorted);
}

sub files {
    print "Content-type:application/json\r\n\r\n";

    my $files = [];

    get_lock();

    opendir( my $dh, $local_files_dir );
    my $file;

    while ( $file = readdir($dh) ) {
        if ( $file !~ /^\./ ) {
            push(
                @$files,
                {
                    file     => $file,
                    epoch    => file_epoch( $local_files_dir . '/' . $file ),
                    size     => file_size( $local_files_dir . '/' . $file ),
                    node     => $node . ':' . $ENV{SERVER_PORT},
                    local    => 1,
                    platform => $platform
                }
            );
        }
    }
    closedir($dh);

    opendir( my $dh, $meshchat_path );
    my $file;

    while ( $file = readdir($dh) ) {
        if ( $file =~ /^remote_files\..*/ ) {
            open( FILES, $meshchat_path . '/' . $file );
            while (<FILES>) {
                my $line = $_;
                chomp($line);

                my @parts = split( "\t", $line );

                #print "$line\n";

                if ( $parts[3] > 0 ) {
                    push(
                       @$files,
                        {
                            file     => $parts[0],
                            epoch    => $parts[3],
                            size     => $parts[2],
                            node     => $parts[1],
                            local    => 0,
                            platform => $parts[4]
                        }
                    );
                }
            }

            close(FILES);
        }
    }
    closedir($dh);

    release_lock();

    my @sorted = sort { $b->{epoch} <=> $a->{epoch} } @$files;

    my $json_files = '[';

    foreach my $file (@sorted) {
        $json_files .= '{"epoch":' . $file->{epoch} . ',"size":"' . $file->{size} . '","file":"' . $file->{file} . '","local":' . $file->{local} . ',"node":"' . $file->{node} . '","platform":"' . $file->{platform} . '"},';
    }

    if ( length($json_files) > 1 ) {
        chop($json_files);
    }

    $json_files .= ']';

    my $stats = file_storage_stats();

    my $json_stats = '{';

    foreach my $key ( keys %$stats ) {
        $json_stats .= '"' . $key . '":' . $$stats{$key} . ',';
    }

    if ( length($json_stats) > 1 ) {
        chop($json_stats);
    }

    $json_stats .= '}';

    my $json = '{"stats":' . $json_stats . ', "files":' . $json_files . '}';

    print $json;

    #print encode_json(\@sorted);
}

sub upload_file {
    read_postdata();

    my $new_file_size = file_size('$tmp_upload_dir/file');

    my $stats = file_storage_stats();

    print STDERR "$new_file_size\n";
    print STDERR "$$stats{allowed}\n";
    print STDERR "$$stats{files_free}\n";

    if ( $new_file_size > $$stats{files_free} ) {
        unlink('$tmp_upload_dir/file');

        print "Content-type: application/json\r\n\r\n";

        print '{"status":500, "response":"Not enough storage, delete some files"}';
    }
    else {
        `cp $tmp_upload_dir/file '$local_files_dir/$parms{uploadfile}'`;

        unlink('$tmp_upload_dir/file');

        print "Content-type: application/json\r\n\r\n";

        print '{"status":200, "response":"OK"}';
    }
}

sub delete_file {
    unlink("$local_files_dir/$query{file}");

    print "Content-type: application/json\r\n\r\n";

    print '{"status":200, "response":"OK"}';
}

sub hosts_raw {
    my $hosts = [];

    print "Content-type: application/json\r\n\r\n";

    open( DHCP, "/var/dhcp.leases" );
    while (<DHCP>) {
        my ( $epoch, $mac1, $ip, $hostname, $mac2 ) = split( /\s/, $_ );
        push(
            @$hosts,
            {
                ip       => $ip,
                hostname => $hostname
            }
        );
    }
    close(DHCP);

    open( DHCP, '/etc/config.mesh/_setup.dhcp.dmz' );
    while (<DHCP>) {
        my ( $mac, $num, $hostname ) = split( /\s/, $_ );
        my $addr = ( gethostbyname($hostname) )[4];
        my ( $a, $b, $c, $d ) = unpack( 'C4', $addr );
        my $ip = "$a.$b.$c.$d";
        push(
            @$hosts,
            {
                ip       => $ip,
                hostname => $hostname
            }
        );
    }
    close(DHCP);

    foreach my $host (@$hosts) {
        print "$host->{ip}\t$host->{hostname}\n";
    }
}

sub hosts {
    my $hosts = [];

    print "Content-type: application/json\r\n\r\n";

    open( DHCP, "/var/dhcp.leases" );
    while (<DHCP>) {
        my ( $epoch, $mac1, $ip, $hostname, $mac2 ) = split( /\s/, $_ );
        push(
            @$hosts,
            {
                ip       => $ip,
                hostname => $hostname,
                node     => $node
            }
        );
    }
    close(DHCP);

    open( DHCP, '/etc/config.mesh/_setup.dhcp.dmz' );
    while (<DHCP>) {
        my ( $mac, $num, $hostname ) = split( /\s/, $_ );
        my $addr = ( gethostbyname($hostname) )[4];
        my ( $a, $b, $c, $d ) = unpack( 'C4', $addr );
        my $ip = "$a.$b.$c.$d";
        push(
            @$hosts,
            {
                ip       => $ip,
                hostname => $hostname,
                node     => $node
            }
        );
    }
    close(DHCP);

    my $node_list = node_list();

    foreach my $remote_node (@$node_list) {
        my @lines = `curl --retry 0 --connect-timeout $connect_timeout http://$remote_node:8080/cgi-bin/meshchat\\?action=hosts_raw 2> /dev/null`;

        foreach my $lines (@lines) {
            if ( $line =~ /error/ || $line eq '' ) { next; }
            my ( $ip, $hostname ) = split( "\t", $line );
            push(
                @$hosts,
                {
                    ip       => $ip,
                    hostname => $hostname,
                    node     => $remote_node
                }
            );
        }
    }

    my @sorted = sort { $a->{hostname} <=> $b->{hostname} } @$hosts;

    my $json = '[';

    foreach my $host (@sorted) {
        $json .= '{"ip":' . $host->{ip} . ',"hostname":"' . $host->{hostname} . '","node":"' . $host->{node} . '"},';
    }

    if ( length($json) > 1 ) {
        chop($json);
    }

    $json .= ']';

    print $json;
}

sub meshchat_nodes {
    print "Content-type: text/plain\r\n\r\n";

    my $zone_name = $query{zone_name};

    dbg "ZONE: $zone_name";

    foreach (`grep -i "/meshchat|" /var/run/services_olsr | grep \$'|$zone_name\t'`) {
        chomp;
        if ($_ =~ /^http:\/\/(.*)\:(\d+)\//) {
            print "$1\t$2\n";
        }
    }
}

sub action_log {
    print "Content-type:application/json\r\n\r\n";

    my $lines = [];

    get_lock();

    open( LOG, $action_log_file );
    while (<LOG>) {
        my $line = $_;
        chomp($line);

        my ($action_epoch, $script, $match, $result, $id, $msg_epoch, $message, $call_sign, $node, $platform, $channel) = split(/\t/, $line);

        push(
            @$lines,
            {
                action_epoch  => $action_epoch,
                script  => $script,
                match  => $match,
                result  => $result,
                id  => $id,
                msg_epoch  => $msg_epoch,
                message  => $message,
                call_sign  => $call_sign,
                node  => $node,
                platform  => $platform,
                channel  => $channel
            }
        );
    }

    close(LOG);    

    release_lock();

    my @sorted = sort { $b->{action_epoch} <=> $a->{action_epoch} } @$lines;

    my $json = '[';

    foreach my $line (@sorted) {
        $json .= '{';
        foreach my $key (keys %$line) {
            #if ($line->{$key} =~ /[0-9]+/) {
            #    $json .= '"' . $key . '":' . $line->{$key} . ',';
            #} else {
                $json .= '"' . $key . '":"' . $line->{$key} . '",';
            #}
        }

        chop($json);
        $json .= '},';
    }

    if ( length($json) > 1 ) {
        chop($json);
    }

    $json .= ']';

    print $json;
}

sub to_dotquad {

    # Given a binary int IP, returns dotted-quad (Reverse of ip2num)
    my $bin    = shift;
    my $result = '';      # Empty string

    for ( 24, 16, 8, 0 ) {
        $result .= ( $bin >> $_ & 255 ) . '.';
    }
    chop $result;         # Delete extra trailing dot
    return $result;
}

