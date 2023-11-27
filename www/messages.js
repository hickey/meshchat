
// Messages is a singleton that keeps a copy of all messages
class Messages {

    constructor() {
        if (! this.__instance) {
            this.messages = {};
            this.message_order = [];
            this.delete_list = [];             // future enhancement
            this.channels = [];
            this.db_version = 0;
            this.last_update = 0;
            this._updating = false;

            this.__instance = this;
        }
        return this.__instance;
    }

    // return reference to singleton, creating if necessary
    getInstance() {
        if (! this.__instance) {
            this.__instance = new Messages();
        }
        return this.__instance;
    }

    check() {
        var pending_db_version = 0;

        return new Promise((newMessages, noMessages) => {
            if (this._updating == true) noMessages();

            // lock out all other updates
            this._updating = true;

            $.getJSON('/cgi-bin/meshchat?action=messages_version_ui&call_sign=' + call_sign + '&id=' + meshchat_id + '&epoch=' + epoch(),
                (data) => {
                    if ('messages_version' in data) {
                        if (this.db_version != data.messages_version) {
                            this.fetch(data.messages_version);
                        }
                    } else {
                        this._updating = false;
                    }
                    newMessages();
                }).fail((error) => {
                    // TODO error message on UI describing failure
                    this._updating = false;
                    noMessages();
                });
        });
    }

    fetch(pending_version) {

        return new Promise((fetched, empty) => {
            $.getJSON('/cgi-bin/meshchat?action=messages&call_sign=' + call_sign + '&id=' + meshchat_id + '&epoch=' + epoch(),
                (data) => {
                    if (data == null) empty();

                    this.messages = data;

                this.update();
                this.last_update = epoch();
                this.db_version = pending_version;
                fetched();
            }).fail((error) => {
                // TODO error message on UI describing failure
                this._updating = false;
                empty();
            }).always(() => {
                this._updating = false;
            });
        });
    }

    /* update the message DB with counts, channels, etc.
       If msg_ids is not specified, then process all messages in the
       DB */
    update(msg_ids=null) {
        if (msg_ids === null) {
            msg_ids = this.messages.keys();
        }

        for (var id in msg_ids) {
            // null channel names is the Everything channel (empty string)
            if (this.messages[id].channel === null) {
                this.messages[id].channel = "";
            }

            // update list of available channels
            if (! this.messages[id].channel in this.channels) {
                this.channels.push(this.messages[id].channel);
            }
        }

        // sort the messages by time (descending)
        this.message_order = this.messages.keys().sort(function(a,b) {
            this.messages[a].epoch > this.messages[b].epoch ? -1 : 1;
        })
    }

    // return a list of channels available across all messages
    channels() {
        return this.channels;
    }

    // return a rendered version of a block of messages
    render(channel, search_filter) {
        let html = '';
        let search = search_filter.toLowerCase();

        for (var id in this.message_order) {
            var message = this.messages[id];

            if (search != '') {
                //console.log(search);
                //console.log(message.toLowerCase());
                if (message.message.toLowerCase().search(search) == -1 &&
                    message.call_sign.toLowerCase().search(search) == -1 &&
                    message.node.toLowerCase().search(search) == -1 &&
                    formated_date.toLowerCase().search(search) == -1) {
                    continue;
                }
            }

            if (channel == '' || channel == this.selected_channel) {
                html += this.render_row(message);
            }

            // if (messages[i].channel != "" && !channels.hasOwnProperty(messages[i].channel)) {
            //     channels[messages[i].channel] = 1;
            // }

        }

        if (messages_version != 0) {
            if (total != messages_version) {
                alert.play();
            }
        }

        // messages_version = total;

        return html;
    }

    render_row(msg_data) {
        let date = new Date(0).setUTCSeconds(msg_data.epoch);
        let message = msg_data.message.replace(/(\r\n|\n|\r)/g, "<br/>");

        let row = '<tr>';
        row += '<td>' + format_date(date) + '</td>';
        row += '<td>' + message + '</td>';
        row += '<td>' + msg_data.call_sign + '</td>';
        row += '<td class="col_channel">' + msg_data.channel + '</td>';
        if (msg_data.platform == 'node') {
            row += '<td class="col_node"><a href="http://' + aredn_domain(msg_data.node) + ':8080" target="_blank">' + msg_data.node + '</a></td>';
        } else {
            row += '<td class="col_node"><a href="http://' + aredn_domain(msg_data.node) + '" target="_blank">' + msg_data.node + '</a></td>';
        }
        row += '</tr>';

        return row;
    }
}