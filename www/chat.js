<<<<<<< HEAD
var meshchat_id;
var last_messages_update = epoch();
var call_sign            = 'NOCALL';
var enable_video         = 0;         // TODO move to meshchat config

var messages         = new Messages();
let alert            = new Audio('alert.mp3');

$(function() {
    meshchat_init();
});

function monitor_last_update() {
    var secs = epoch() - last_messages_update;
    $('#last-update').html('<strong>Updated:</strong> ' + secs + ' seconds ago');
}

function update_messages(reason=Messages.MSG_UPDATE) {
    if (reason != Messages.MSG_UPDATE) return;
    console.debug("update_messages(reason=" + reason + ")");

    // update the message table
    let html = messages.render($('#channels').val(), $('#search').val());
    if (html) $('#message-table').html(html);
    last_messages_update = epoch();
}

function new_messages(reason) {
    if (reason != Messages.NEW_MSG) return;
    console.debug("new_messages(reason=" + reason + ")");
    alert.play();
}

function update_channels(reason) {
    if (reason != Messages.CHAN_UPDATE) return;
    console.debug("update_channels(reason="+ reason + ")");

    let msg_refresh      = false;
    let channels         = messages.channels().sort();
    let channel_filter   = $('#channels').val();
    let cur_send_channel = $('#send-channel').val();
    // null signals a new channel was just created
    if (cur_send_channel == null) {
        channel_filter = messages.current_channel();
        cur_send_channel = messages.current_channel();
        msg_refresh = true;
    }

    // clear channel selection boxes
    $('#send-channel').find('option').remove().end();
    $('#channels').find('option').remove().end();

    function add_option(select, title, value) {
        select.append("<option value='"+value+"'>"+title+"</option>");
    }

    // Add static channels to channel selection boxes
    add_option($('#send-channel'), "Everything", "");
    add_option($('#send-channel'), "Add New Channel", "Add New Channel");
    add_option($('#channels'), "Everything", "");

    for (var chan of channels) {
        if (chan != "") {
            add_option($('#send-channel'), chan, chan);
            add_option($('#channels'), chan, chan);
        }
    }

    $("#channels").val(channel_filter);
    $("#send-channel").val(cur_send_channel);
    if (msg_refresh) update_messages();
}

function start_chat() {
    //$('#logout').html('Logout ' + call_sign);
    messages.subscribe(update_messages);
    messages.subscribe(new_messages);
    messages.subscribe(update_channels);
    messages.set_channel("");
    messages.check();
    load_users();
    monitor_last_update();

    // start event loops to update MeshChat client
    setInterval(() => { messages.check() }, 15000);
    setInterval(() => { load_users() }, 15000);
    setInterval(() => { monitor_last_update() }, 2500);
}

function meshchat_init() {
    $('#message').val('');
    meshchat_id = Cookies.get('meshchat_id');
    if (meshchat_id == undefined) {
        // TODO set default expiration of cookie
        Cookies.set('meshchat_id', make_id());
        meshchat_id = Cookies.get('meshchat_id');
    }

    $('#submit-message').on('click', function(e) {
        e.preventDefault();
        if ($('#message').val().length == 0) return;

        ohSnapX();

        // disable message sending box
        $(this).prop("disabled", true);
        $('#message').prop("disabled", true);
        $(this).html('<div class="loading"></div>');

        let channel = $('#send-channel').val();

        if ($('#new-channel').val() != '') {
            channel = $('#new-channel').val();
            $('#send-channel').val('Everything');
        }

        messages.send($('#message').val(), channel, call_sign).then(
            // sent
            (sent) => {
                $('#message').val('');
                ohSnap('Message sent', 'green');
                update_messages(Messages.NEW_MSG);

                // clear out new channel box in case it was used and
                // reset to normal selection box
                $('#new-channel').val('');
                $('#new-channel').hide();
                $('#send-channel').show();
            },
            // error
            (err_msg) => {
                ohSnap(err_msg, 'red', {time: '30000'});
            }
        ).finally(() => {
            // change the channel selector to the channel the message was
            // just sent to
            $('#channels').val(channel);
            messages.set_channel(channel);
            update_messages();

            // re-enable message sending box
            $(this).prop("disabled", false);
            $('#message').prop("disabled", false);
            $(this).html('Send');
        });
    });

    $('#submit-call-sign').on('click', function(e) {
        e.preventDefault();
        if ($('#call-sign').val().length == 0) return;
        call_sign = $('#call-sign').val().toUpperCase();
        // TODO set default expiration of cookie
        Cookies.set('meshchat_call_sign', call_sign);
        $('#call-sign-container').addClass('hidden');
        $('#chat-container').removeClass('hidden');
        $('#callsign').html('<strong>Call Sign:</strong> ' + call_sign);
        start_chat();
    });

    $('#channels').on('change', function() {
        $('#send-channel').val(this.value);
        messages.set_channel(this.value);
        update_messages();
    });

    $('#search').keyup(function() {
        //console.log(this.value);
        update_messages();
    });

    $('#message-expand').on('click', function(e) {
        $('#message-panel').toggleClass('message-panel-collapse');
        $('#message-panel-body').toggleClass('message-panel-body-collapse');
        $('#users-panel').toggleClass('users-panel-collapse');
        $('#users-panel-body').toggleClass('users-panel-body-collapse');
    });

    // allow user to enter new channel
    $('#send-channel').on('change', function() {
        if (this.value == "Add New Channel") {
            $('#new-channel').show().focus();
            $(this).hide();
        }
    });

    // process a CTRL <ENTER> to send a message
    $('#message').keydown(function (e) {
        if ((e.keyCode == 10 || e.keyCode == 13) && e.ctrlKey) {
            $("#submit-message").trigger( "click" );
        }
    });

    // login with a cookie
    var cookie_call_sign = Cookies.get('meshchat_call_sign');
    if (cookie_call_sign == undefined) {
        $('#call-sign-container').removeClass('hidden');
    } else {
        $('#call-sign-container').addClass('hidden');
        $('#chat-container').removeClass('hidden');
        call_sign = cookie_call_sign;
        start_chat();
    }
}

let users_updating = false;
function load_users() {
    if (users_updating == true) return;
    console.debug("load_users()");

    // lock to prevent simultaneous updates
    users_updating = true;

    $.getJSON('/cgi-bin/meshchat?action=users&call_sign=' + call_sign + '&id=' + meshchat_id,
        (data) => {
            if (data == null || data == 0) return;

            let html = '';
            let count = 0;

            for (var entry of data) {
                var date = new Date(0);
                date.setUTCSeconds(entry.epoch);

                // user heartbeat timeout > 4 mins
                if ((epoch() - entry.epoch) > 240) continue;

                // user heartbeat > 2 mins, expiring
                if ((epoch() - entry.epoch) > 120) {
                    html += '<tr class="grey-background">';
                } else {
                    html += '<tr>';
                }

                if (enable_video == 0) {
                    html += '<td>' + entry.call_sign + '</td>';
                } else {
                    html += '<td><a href="' + entry.id + '" onclick="start_video(\'' + entry.id + '\');return false;">' + entry.call_sign + '</td>';
                }

                if (entry.platform == 'node') {
                    html += '<td><a href="http://' + aredn_domain(entry.node) + ':8080" target="_blank">' + entry.node + '</a></td>';
                } else {
                    html += '<td><a href="http://' + aredn_domain(entry.node) + '" target="_blank">' + entry.node + '</a></td>';
                }

                html += '<td>' + format_date(date) + '</td>';
                html += '</tr>';

                count++;
            }
            $('#users-table').html(html);
            $('#users-count').html(count);
        }).always(() => {
            // allow updates again
            users_updating = false;
        });
}
||||||| parent of fff9980 (Initial pass at reorganization)
=======
var last_messages_update = epoch();
var call_sign = 'NOCALL';
var meshchat_id;
var peer;
var mediaConnection;
var enable_video = 0;
var messages_updating = false;
var users_updating = false;
var messages = [];
var channel_filter = '';
var messages_version = 0;
var alert = new Audio('alert.mp3');
var message_db_version = 0;
var pending_message_db_version = 0;
var search_filter = '';

$(function() {
    meshchat_init();
});

function monitor_last_update() {
    var secs = epoch() - last_messages_update;
    $('#last-update').html('<strong>Updated:</strong> ' + secs + ' seconds ago');
}

function start_chat() {
    //$('#logout').html('Logout ' + call_sign);   
    load_messages();
    load_users();
    monitor_last_update();
    setInterval(function() {
        load_messages()
    }, 15000);
    setInterval(function() {
        load_users()
    }, 15000);
    setInterval(function() {
        monitor_last_update()
    }, 2500);
}

function meshchat_init() {
    $('#message').val('');
    meshchat_id = Cookies.get('meshchat_id');
    if (meshchat_id == undefined) {
        Cookies.set('meshchat_id', make_id());
        meshchat_id = Cookies.get('meshchat_id');
    }
    //console.log(meshchat_id);    
    $('#submit-message').on('click', function(e) {
        e.preventDefault();
        if ($('#message').val().length == 0) return;

        ohSnapX();

        $(this).prop("disabled", true);
        $('#message').prop("disabled", true);
        $(this).html('<div class="loading"></div>');

        var channel = $('#send-channel').val();

        if ($('#new-channel').val() != '') {
            channel = $('#new-channel').val();
            $('#send-channel').val('Everything');
        }

        $.ajax({
            url: '/cgi-bin/meshchat',
            type: "POST",
            tryCount : 0,
            retryLimit : 3,
            cache: false,
            timeout: 5000,
            data:
            {
                action: 'send_message',
                message: $('#message').val(),
                call_sign: call_sign,
                epoch: epoch(),
                channel: channel
            },
            dataType: "json",
            context: this,
            success: function(data, textStatus, jqXHR)
            {
                if (data.status == 500) {
                    ohSnap('Error sending message: ' + data.response, 'red', {time: '30000'});  
                } else {
                    $('#message').val('');
                    ohSnap('Message sent', 'green');
                    load_messages();        
                    channel_filter = channel;      
                    $('#new-channel').val('');
                    $('#new-channel').hide();
                    $('#send-channel').show();      
                }
            },
            error: function(jqXHR, textStatus, errorThrown)
            {
                if (textStatus == 'timeout') {
                    this.tryCount++;
                    if (this.tryCount <= this.retryLimit) {
                        //try again
                        $.ajax(this);
                        return;
                    }    
                    ohSnap('Error sending message: ' + textStatus, 'red', {time: '30000'});        
                }                
            },
            complete: function(jqXHR, textStatus) {
                $(this).prop("disabled", false);
                $('#message').prop("disabled", false);
                $(this).html('Send');
            }
        });
    });
    
    $('#submit-call-sign').on('click', function(e) {
        e.preventDefault();
        if ($('#call-sign').val().length == 0) return;
        call_sign = $('#call-sign').val().toUpperCase();
        Cookies.set('meshchat_call_sign', call_sign);
        $('#call-sign-container').addClass('hidden');
        $('#chat-container').removeClass('hidden');
        $('#callsign').html('<strong>Call Sign:</strong> ' + Cookies.get('meshchat_call_sign'));
        start_chat();
    });    

    $('#channels').on('change', function() {        
        channel_filter = this.value;
        process_messages();
    });

    $('#search').keyup(function() {        
        //console.log(this.value);
        search_filter = this.value;
        process_messages();
    });

    $('#message-expand').on('click', function(e) {  
        $('#message-panel').toggleClass('message-panel-collapse');
        $('#message-panel-body').toggleClass('message-panel-body-collapse');    
        $('#users-panel').toggleClass('users-panel-collapse');
        $('#users-panel-body').toggleClass('users-panel-body-collapse');
    });

    $('#send-channel').on('change', function() {
        if (this.value == "Add New Channel") {
            $('#new-channel').show();
            $(this).hide();
        }
    });

    $('#message').keydown(function (e) {
        if ((event.keyCode == 10 || event.keyCode == 13) && event.ctrlKey) {
            $("#submit-message").trigger( "click" );
        }
    });

    var cookie_call_sign = Cookies.get('meshchat_call_sign');
    if (cookie_call_sign == undefined) {
        $('#call-sign-container').removeClass('hidden');
    } else {
        $('#call-sign-container').addClass('hidden');
        $('#chat-container').removeClass('hidden');
        call_sign = cookie_call_sign;
        start_chat();
    }
}

function load_messages() {
    if (messages_updating == true) return;

    messages_updating = true;

    $.ajax({
        url: '/cgi-bin/meshchat?action=messages_version_ui&call_sign=' + call_sign + '&id=' + meshchat_id + '&epoch=' + epoch(),
        type: "GET",
        dataType: "json",
        context: this,
        cache: false,
        success: function(data, textStatus, jqXHR)
        {            
            if (data == null) {
                messages_updating = false;
                return;
            }

            if (data.messages_version != message_db_version) {
                pending_message_db_version = data.messages_version;
                fetch_messages();
            } else {
                messages_updating = false;
                last_messages_update = epoch();
            }
        },
        error: function(jqXHR, textStatus, errorThrown)
        {
            messages_updating = false;
        },
        complete: function(jqXHR, textStatus) {

        }
    });
    
}

function fetch_messages() {
    $.ajax({
        url: '/cgi-bin/meshchat?action=messages&call_sign=' + call_sign + '&id=' + meshchat_id + '&epoch=' + epoch(),
        type: "GET",
        dataType: "json",
        context: this,
        cache: false,
        success: function(data, textStatus, jqXHR)
        {            
            if (data == null) return;

            messages = data;

            process_messages();
            last_messages_update = epoch();
            message_db_version = pending_message_db_version;
        },
        complete: function(jqXHR, textStatus) {
            //console.log( "messages complete" );
            messages_updating = false;
        }
    });
}

function process_messages() {
    var html = '';

    var cur_send_channel = $("#send-channel").val();

    $('#send-channel')
    .find('option')
    .remove()
    .end();

    $('#channels')
    .find('option')
    .remove()
    .end();

    var channels = {};

    var total = 0;

    var search = search_filter.toLowerCase();

    for (var i = 0; i < messages.length; i++) {
        var row = '';        
        var date = new Date(0);
        date.setUTCSeconds(messages[i].epoch);
        var message = messages[i].message;
        message = message.replace(/(\r\n|\n|\r)/g, "<br/>");

        var id = parseInt(messages[i].id, 16);
        total += id;

        var formated_date = format_date(date);

        if (search != '') {
            //console.log(search);
            //console.log(message.toLowerCase());
            if (message.toLowerCase().search(search) == -1 &&
                messages[i].call_sign.toLowerCase().search(search) == -1 &&
                messages[i].node.toLowerCase().search(search) == -1 &&
                formated_date.toLowerCase().search(search) == -1) {
                continue;
            }
        }

        if (messages[i].channel == null) {
            messages[i].channel = "";
        }

        row += '<tr>';
        row += '<td>' + formated_date + '</td>';
        row += '<td>' + message + '</td>';
        row += '<td>' + messages[i].call_sign + '</td>';
        row += '<td class="col_channel">' + messages[i].channel + '</td>';
        if (messages[i].platform == 'node') {
            row += '<td class="col_node"><a href="http://' + aredn_domain(messages[i].node) + ':8080" target="_blank">' + messages[i].node + '</a></td>';
        } else {
            row += '<td class="col_node"><a href="http://' + aredn_domain(messages[i].node) + '" target="_blank">' + messages[i].node + '</a></td>';
        }
        row += '</tr>';

        if (messages[i].channel != "" && !channels.hasOwnProperty(messages[i].channel)) {
            channels[messages[i].channel] = 1;
        }

        if (channel_filter != '') {
            if (channel_filter == messages[i].channel) html += row;
        } else {
            html += row;
        }        
    }

    if (messages_version != 0) {
        if (total != messages_version) {            
            alert.play();
        }
    }

    messages_version = total;        

    $('#message-table').html(html);           

    $('#send-channel')
    .append($("<option></option>")
    .attr("value", "")
    .text("Everything")); 

    $('#send-channel')
    .append($("<option></option>")
    .attr("value", "Add New Channel")
    .text("Add New Channel")); 

    $('#channels')
    .append($("<option></option>")
    .attr("value", "")
    .text("Everything")); 

    for (var property in channels) {
        if (channels.hasOwnProperty(property)) {
            $('#send-channel')
            .append($("<option></option>")
            .attr("value", property)
            .text(property)); 

            $('#channels')
            .append($("<option></option>")
            .attr("value", property)
            .text(property));
        }
    }

    $("#channels").val(channel_filter);
    $("#send-channel").val(cur_send_channel);
}

function load_users() {
    if (users_updating == true) return;

    users_updating = true;

    $.ajax({
        url: '/cgi-bin/meshchat?action=users&call_sign=' + call_sign + '&id=' + meshchat_id,
        type: "GET",
        dataType: "json",
        context: this,
        cache: false,
        success: function(data, textStatus, jqXHR)
        {
            var html = '';
            if (data == null) return;
            var count = 0;
            for (var i = 0; i < data.length; i++) {
                var date = new Date(0);
                date.setUTCSeconds(data[i].epoch);
                if ((epoch() - data[i].epoch) > 240) continue;
                if ((epoch() - data[i].epoch) > 120) {
                    html += '<tr class="grey-background">';
                } else {
                    html += '<tr>';
                }
                if (enable_video == 0) {
                    html += '<td>' + data[i].call_sign + '</td>';
                } else {
                    html += '<td><a href="' + data[i].id + '" onclick="start_video(\'' + data[i].id + '\');return false;">' + data[i].call_sign + '</td>';
                }
                if (data[i].platform == 'node') {
                    html += '<td><a href="http://' + aredn_domain(data[i].node) + ':8080" target="_blank">' + data[i].node + '</a></td>';
                } else {
                    html += '<td><a href="http://' + aredn_domain(data[i].node) + '" target="_blank">' + data[i].node + '</a></td>';
                }
                html += '<td>' + format_date(date) + '</td>';
                html += '</tr>';

                count++;
            }
            $('#users-table').html(html);
            $('#users-count').html(count);
        },
        complete: function(jqXHR, textStatus) {
            //console.log( "users complete" );
            users_updating = false;
        }
    });
}
>>>>>>> fff9980 (Initial pass at reorganization)
