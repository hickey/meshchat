var config;

$(function() {
    $('#logout').on('click', function(e){
        e.preventDefault();
        Cookies.remove('meshchat_call_sign');
        window.location = '/meshchat';
    });

    $.getJSON('/cgi-bin/meshchat?action=config', function(data) {
        config = data;

        document.title = 'Mesh Chat v' + data.version;
        $('#version').html('<strong>Mesh Chat v' + data.version + '</strong>');
        $('#node').html('<strong>Node:</strong> ' + data.node);
        $('#zone').html('<strong>Zone:</strong> ' + data.zone);
        $('#callsign').html('<strong>Call Sign:</strong> ' + Cookies.get('meshchat_call_sign'));
        $('#copyright').html('Mesh Chat v' + data.version + ' Copyright &copy; ' + new Date().getFullYear() + ' <a href="http://www.trevorsbench.com">Trevor Paskett - K7FPV</a> <small>(Lua by KN6PLV)</small>');
    });
});

function node_name() {
    return config.node;
}

function platform() {
    return config.platform || 'node'; // TODO temp patch until config API is updated
}

function epoch() {
    return Math.floor(new Date() / 1000);
}

function format_date(date) {
    var string;

    var year = String(date.getFullYear());

    string = (date.getMonth()+1) + '/' + date.getDate() + '/' + year.slice(-2);
    string += '<br/>';

    var hours = date.getHours();
    var minutes = date.getMinutes();
    var ampm = hours >= 12 ? 'PM' : 'AM';

    hours = hours % 12;
    hours = hours ? hours : 12; // the hour '0' should be '12'
    minutes = minutes < 10 ? '0'+minutes : minutes;

    string += hours + ':' + minutes + ' ' + ampm;

    return string;
}

function make_id()
{
    var text = "";
    var possible = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";

    for( var i=0; i < 5; i++ )
        text += possible.charAt(Math.floor(Math.random() * possible.length));

    return text;
}

function aredn_domain(host) {
    if (host.indexOf(".") !== -1) {
        return host;
    }
    host = host.split(":")
    return host[0] + ".local.mesh" + (host[1] ? ":" + host[1] : "");
}

function debug(msg) {
    context.debug && console.debug(msg);
}
