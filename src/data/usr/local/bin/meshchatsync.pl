#!/usr/bin/perl

BEGIN { push @INC, '/www/cgi-bin', '/usr/lib/cgi-bin' }
use meshchatlib;
use meshchatconfig;

my $new_messages = 0;
my %sync_status  = ();
my %non_mesh_chat_nodes;

my $node = node_name();

dbg "startup";

if ( !-d $meshchat_path ) {
    mkdir($meshchat_path);
    mkdir($local_files_dir);
    `touch $lock_file`;
}

if (!-e $lock_file) {
    `touch $lock_file`;
}

if (!-e $messages_db_file) {
    `touch $messages_db_file`;
    chmod( 0666, $messages_db_file );
}

save_messages_db_version();

chmod( 0777, $meshchat_path );

while (1) {
    my $node_list = node_list();

    $messages_db_file = $messages_db_file_orig . '.' . zone_name();

    $new_messages = 0;
    %sync_status  = ();

    foreach my $node_info (@$node_list) {
        my $remote_node     = $$node_info{node};
        my $remote_platform = $$node_info{platform};
        my $remote_port = $$node_info{port};

        my $port = '';

        if ($remote_port ne '') {
            $port = ':' . $remote_port;
        }

        if ( $port eq '' && $remote_platform eq 'node' ) {
            $port = ':8080';
        }

        dbg $remote_node . ':' . $port . ' ' . $remote_platform;

        my $version = get_messages_db_version();

        # Poll non mesh chat nodes at a longer interval
        if ( exists $non_mesh_chat_nodes{$remote_node} ) {
            if ( time() < $non_mesh_chat_nodes{$remote_node} ) { next; }
        }

        # Get remote users file
        unlink( $meshchat_path . '/remote_users' );
        my $escape_node = url_escape($node);
        my $output      = `curl --retry 0 --connect-timeout $connect_timeout -sD - "http://$remote_node$port/cgi-bin/meshchat?action=users_raw&platform=$platform&node=$escape_node" -o $meshchat_path/remote_users 2>&1`;

        #dbg $output;

        # Check if meshchat is installed
        if ( $output =~ /404 Not Found/ ) {
            dbg "Non mesh node";
            $non_mesh_chat_nodes{$remote_node} = time() + $non_meshchat_poll_interval;
            next;
        }

        if ( $output =~ /Content\-MD5\: (.*)\r\n/ ) {
            my $file_md5 = file_md5( $meshchat_path . '/remote_users' );
            if ( $file_md5 eq $1 ) {
                my $cur_size = file_size( $meshchat_path . '/remote_users' );

                if ( $cur_size > 0 ) {
                    merge_users();
                }
            }
        }

        # Get remote files file
        unlink( $meshchat_path . '/remote_files' );
        $output = `curl --retry 0 --connect-timeout $connect_timeout -sD - http://$remote_node$port/cgi-bin/meshchat?action=local_files_raw -o $meshchat_path/remote_files 2>&1`;

        if ( $output =~ /Content\-MD5\: (.*)\r\n/ ) {
            my $file_md5 = file_md5( $meshchat_path . '/remote_files' );
            dbg "MD5 $file_md5 $1";
            if ( $file_md5 eq $1 ) {
                my $cur_size = file_size( $meshchat_path . '/remote_files' );

                if ( $cur_size > 0 ) {
                    dbg "save file list $cur_size";
                    rename($meshchat_path . '/remote_files', $meshchat_path . '/remote_files.' . $remote_node);
                } else {
                    dbg "remove file list";
                    unlink($meshchat_path . '/remote_files.' . $remote_node);
                }
            } else {
                dbg "remove file list";
                unlink($meshchat_path . '/remote_files.' . $remote_node);
            }
        }

        # Get remote messages
        unlink( $meshchat_path . '/remote_messages' );

        my $remote_version = `curl --retry 0 --connect-timeout $connect_timeout http://$remote_node$port/cgi-bin/meshchat?action=messages_version -o - 2> /dev/null`;

        # Check the version of the remote db against ours. Only download the db if the remote has a different copy

        dbg "version check $version = $remote_version";

        if ( $remote_version ne '' && $version eq $remote_version ) {
            dbg "same version skip download";
            $sync_status{$remote_node} = time();
            next;
        }

        $output = `curl --retry 0 --connect-timeout $connect_timeout -sD - http://$remote_node$port/cgi-bin/meshchat?action=messages_raw -o $meshchat_path/remote_messages 2>&1`;

        dbg $output;

        if ( -e $meshchat_path . '/remote_messages' ) {
            if ( $output =~ /Content\-MD5\: (.*)\r\n/ ) {
                my $file_md5 = file_md5( $meshchat_path . '/remote_messages' );
                if ( $file_md5 eq $1 ) {
                    my $cur_size = file_size( $meshchat_path . '/remote_messages' );

                    if ( $cur_size > 0 ) {
                        $sync_status{$remote_node} = time();
                        merge_messages();
                    }
                }
                else {
                    dbg "failed remote_messages md5 check *$file_md5* *$1*";
                }
            }
        }
    }

    log_status();

    #trim_db();

    unlink( $meshchat_path . '/remote_messages' );
    unlink( $meshchat_path . '/remote_users' );
    unlink( $meshchat_path . '/remote_files' );

    dbg "sleeping $poll_interval";

    sleep($poll_interval);
}

sub log_status {
    my %cur_status;
    my %lmsg;
    my $num_rmsg = 0;

    if ( !-e $sync_status_file ) { `touch $sync_status_file`; }

    get_lock();

    open( STATUS, $sync_status_file );
    while (<STATUS>) {
        my $line = $_;
        chomp($_);
        my @parts = split( "\t", $_ );
        $cur_status{ $parts[0] } = $parts[1];
    }
    close(STATUS);

    open( STATUS, '>' . $sync_status_file );
    foreach my $key ( keys %sync_status ) {
        print STATUS "$key\t$sync_status{$key}\n";
    }
    foreach my $key ( keys %cur_status ) {
        if ( !exists $sync_status{$key} ) {
            print STATUS "$key\t$cur_status{$key}\n";
        }
    }
    close(STATUS);

    release_lock();
}

sub merge_messages {
    my %rmsg;
    my %lmsg;
    my %done;
    my $num_rmsg = 0;
    my @new_messages;

    dbg "merge_messages";

    open( RMSG, $meshchat_path . '/remote_messages' );
    while (<RMSG>) {
        my @parts = split( "\t", $_ );
        $rmsg{ $parts[0] } = $_;
    }
    close(RMSG);

    get_lock();

    open( LMSG, $messages_db_file );
    while (<LMSG>) {
        my @parts = split( "\t", $_ );
        $lmsg{ $parts[0] } = 1;
    }
    close(LMSG);

    open( MSG, '>>' . $messages_db_file );
    foreach my $rmsg_id ( keys %rmsg ) {
        if ( !exists $lmsg{$rmsg_id} ) {
            print MSG $rmsg{$rmsg_id};
            push(@new_messages, $rmsg{$rmsg_id});
            $new_messages = 1;
        }
        else {
            #print "$rmsg_id is IN in local db\n";
        }
    }
    close(MSG);

    sort_db();

    trim_db();

    save_messages_db_version();

    release_lock();

    dbg "process actions";

    foreach my $msg (@new_messages) {
        dbg "action: $msg";
        process_message_action($msg);
    }
}

sub merge_users {
    my %rusers;
    my %lusers;
    my %done;

    dbg "merge_users";

    open( RUSERS, $meshchat_path . '/remote_users' );
    while (<RUSERS>) {
        my @parts = split( "\t", $_ );
        $key = $parts[0] . "\t" . $parts[1] . "\t" . $parts[2];
        if ( $_ !~ /error/ && $#parts > 2 ) { $rusers{$key} = $parts[3] . "\t" . $parts[4]; }
    }
    close(RUSERS);

    get_lock();

    open( LUSERS, $remote_users_status_file );
    while (<LUSERS>) {
        my @parts = split( "\t", $_ );
        $key = $parts[0] . "\t" . $parts[1] . "\t" . $parts[2];
        if ( $_ !~ /error/ && $#parts > 2 ) { $lusers{$key} = $parts[3] . "\t" . $parts[4]; }
    }
    close(LUSERS);

    open( USERS, '>' . $remote_users_status_file );

    foreach my $key ( keys %rusers ) {
        my @parts = split( "\t", $key );

        dbg "$key\n$#parts\n";

        if ( exists( $lusers{$key} ) ) {
            if ( $lusers{$key} > $rusers{$key} ) {
                print USERS "$key\t$lusers{$key}";
            }
            else {
                print USERS "$key\t$rusers{$key}";
            }
        }
        else {
            if ( $#parts > 1 ) { print USERS "$key\t$rusers{$key}"; }
        }
    }

    foreach my $key ( keys %lusers ) {
        my @parts = split( "\t", $key );
        if ( $#parts > 1 && !exists $rusers{$key} ) {
            print USERS "$key\t$lusers{$key}";
        }
    }

    close(USERS);

    release_lock();
}
