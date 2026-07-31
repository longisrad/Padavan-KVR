var sw_mode = '<% nvram_get_x("", "sw_mode"); %>';
var wan_route_x = '<% nvram_get_x("", "wan_route_x"); %>';
var wan_proto = '<% nvram_get_x("", "wan_proto"); %>';
var lan_proto = '<% nvram_get_x("", "lan_proto_x"); %>';
var log_float = '<% nvram_get_x("", "log_float_ui"); %>';
var reboot_schedule_support = '<% nvram_get_x("", "reboot_schedule_enable"); %>';
var ss_schedule_support = '<% nvram_get_x("", "ss_schedule_enable"); %>';
var log_stamp = 0;
var sysinfo = <% json_system_status(); %>;
var uptimeStr = "<% uptime(); %>";
var timezone = uptimeStr.substring(26,31);
var newformat_systime = uptimeStr.substring(8,11) + " " + uptimeStr.substring(5,7) + " " + uptimeStr.substring(17,25) + " " + uptimeStr.substring(12,16); 
var systime_millsec = Date.parse(newformat_systime); 
var JS_timeObj = new Date(); 
var cookie_pref = 'n56u_cookie_';

var uagent = navigator.userAgent.toLowerCase();
var is_ie11p = (/trident\/7\./).test(uagent);
var is_mobile = (/iphone|ipod|ipad|iemobile|android|blackberry|fennec/).test(uagent);

var new_wan_internet = '<% nvram_get_x("", "link_internet"); %>';
var id_check_status = 0;
var id_system_info = 0;

var cookie = {
	set: function(key, value, days) {
		document.cookie = cookie_pref + key + '=' + value + '; expires=' +
			(new Date(new Date().getTime() + ((days ? days : 14) * 86400000))).toUTCString() + '; path=/';
	},
	get: function(key) {
		var r = ('; ' + document.cookie + ';').match('; ' + cookie_pref + key + '=(.*?);');
		return r ? r[1] : null;
	},
	unset: function(key) {
		document.cookie = cookie_pref + key + '=; expires=' + (new Date(1)).toUTCString() + '; path=/';
	}
};

<% firmware_caps_hook(); %>

function get_ap_mode(){
	return (wan_route_x == 'IP_Bridged' || sw_mode == '3') ? true : false;
}

function unload_body(){
	disableCheckChangedStatus();
	no_flash_button();
	return true;
}

function enableCheckChangedStatus(flag){
	var tm_int_sec = 1;
	disableCheckChangedStatus();
	if (new_wan_internet == '0')
		tm_int_sec = 2;
	else if (new_wan_internet == '1')
		tm_int_sec = 5;
	id_check_status = setTimeout("get_changed_status();", tm_int_sec * 1000);
}

function disableCheckChangedStatus(){
	clearTimeout(id_check_status);
}

function update_internet_status(){
	if (new_wan_internet == '1')
		showMapWANStatus(1);
	else if(new_wan_internet == '2')
		showMapWANStatus(2);
	else
		showMapWANStatus(0);
}

function notify_status_internet(wan_internet){
	this.new_wan_internet = wan_internet;
	if((location.pathname == "/" || location.pathname == "/index.asp") && (typeof(update_internet_status) === 'function'))
		update_internet_status();
}

function notify_status_vpn_client(vpnc_state){
	if((location.pathname == "/vpncli.asp") && (typeof(update_vpnc_status) === 'function'))
		update_vpnc_status(vpnc_state);
}

function get_changed_status(){
	var $j = jQuery.noConflict();
	$j.ajax({
		type: 'get',
		url: '/status_internet.asp',
		dataType: 'script',
		cache: true,
		error: function(xhr) { ; },
		success: function(response) {
			notify_status_internet(now_wan_internet);
			notify_status_vpn_client(now_vpnc_state);
			enableCheckChangedStatus();
		}
	});
}

function get_system_info(){
	var $j = jQuery.noConflict();
	clearTimeout(id_system_info);
	$j.ajax({
		type: 'get',
		url: '/system_status_data.asp',
		dataType: 'script',
		cache: true,
		error: function(xhr) {
			id_system_info = setTimeout('get_system_info()', 2000);
		},
		success: function(response) {
			id_system_info = setTimeout('get_system_info()', 2000);
			setSystemInfo(response);
		}
	});
}

function bytesToSize(bytes, precision){
	var absval = Math.abs(bytes);
	var kilobyte = 1024;
	var megabyte = kilobyte * 1024;
	var gigabyte = megabyte * 1024;
	var terabyte = gigabyte * 1024;

	if (absval < kilobyte)
		return bytes + ' B';
	else if (absval < megabyte)
		return (bytes / kilobyte).toFixed(precision) + ' KB';
	else if (absval < gigabyte)
		return (bytes / megabyte).toFixed(precision) + ' MB';
	else if (absval < terabyte)
		return (bytes / gigabyte).toFixed(precision) + ' GB';
	else
		return (bytes / terabyte).toFixed(precision) + ' TB';
}

function getLALabelStatus(num){
	var la = parseFloat(num);
	return la > 0.9 ? 'danger' : (la > 0.5 ? 'warning' : 'info');
}

function setSystemInfo(response){
	if(typeof(si_new) !== 'object')
		return;
	var cpu_now = {};
	var cpu_total = (si_new.cpu.total - sysinfo.cpu.total);
	if (!cpu_total) cpu_total = 1;
	cpu_now.busy = parseInt((si_new.cpu.busy - sysinfo.cpu.busy) * 100 / cpu_total);
	cpu_now.user = parseInt((si_new.cpu.user - sysinfo.cpu.user) * 100 / cpu_total);
	cpu_now.nice = parseInt((si_new.cpu.nice - sysinfo.cpu.nice) * 100 / cpu_total);
	cpu_now.system = parseInt((si_new.cpu.system - sysinfo.cpu.system) * 100 / cpu_total);
	cpu_now.idle = parseInt((si_new.cpu.idle - sysinfo.cpu.idle) * 100 / cpu_total);
	cpu_now.iowait = parseInt((si_new.cpu.iowait - sysinfo.cpu.iowait) * 100 / cpu_total);
	cpu_now.irq = parseInt((si_new.cpu.irq - sysinfo.cpu.irq) * 100 / cpu_total);
	cpu_now.sirq = parseInt((si_new.cpu.sirq - sysinfo.cpu.sirq) * 100 / cpu_total);
	sysinfo = si_new;
	showSystemInfo(cpu_now,1);
}

function showSystemInfo(cpu_now,force){
	var $j = jQuery.noConflict();
	var arrLA = sysinfo.lavg.split(' ');
	var h = sysinfo.uptime.hours < 10 ? ('0'+sysinfo.uptime.hours) : sysinfo.uptime.hours;
	var m = sysinfo.uptime.minutes < 10 ? ('0'+sysinfo.uptime.minutes) : sysinfo.uptime.minutes;

	$j("#la_info").html('<span class="label label-'+getLALabelStatus(arrLA[0])+'">'+arrLA[0]+'</span>&nbsp;<span class="label label-'+getLALabelStatus(arrLA[1])+'">'+arrLA[1]+'</span>&nbsp;<span class="label label-'+getLALabelStatus(arrLA[2])+'">'+arrLA[2]+'</span>');
	$j("#cpu_info").html(cpu_now.busy + '%');
	$j("#mem_info").html(bytesToSize(sysinfo.ram.free*1024, 2) + " / " + bytesToSize(sysinfo.ram.total*1024, 2));
	$j("#uptime_info").html(sysinfo.uptime.days + "d " + h + "h " + m + "m");

	$j("#cpu_usage tr:nth-child(1) td:first").html('busy: '+cpu_now.busy+'%');
	$j("#cpu_usage tr:nth-child(2) td:first").html('user: '+cpu_now.user+'%');
	$j("#cpu_usage tr:nth-child(2) td:last").html('system: '+cpu_now.system+'%');
	$j("#cpu_usage tr:nth-child(3) td:first").html('sirq: '+cpu_now.sirq+'%');
	$j("#cpu_usage tr:nth-child(3) td:last").html('irq: '+cpu_now.irq+'%');
	$j("#cpu_usage tr:nth-child(4) td:first").html('idle: '+cpu_now.idle+'%');
	$j("#cpu_usage tr:nth-child(4) td:last").html('nice: '+cpu_now.nice+'%');

	$j("#mem_usage tr:nth-child(1) td:first").html('total: '+bytesToSize(sysinfo.ram.total*1024, 2));
	$j("#mem_usage tr:nth-child(2) td:first").html('free: '+bytesToSize(sysinfo.ram.free*1024, 2));
	$j("#mem_usage tr:nth-child(2) td:last").html('used: '+bytesToSize(sysinfo.ram.used*1024, 2));
	$j("#mem_usage tr:nth-child(3) td:first").html('cached: '+bytesToSize(sysinfo.ram.cached*1024, 2));
	$j("#mem_usage tr:nth-child(3) td:last").html('buffers: '+bytesToSize(sysinfo.ram.buffers*1024, 2));
	$j("#mem_usage tr:nth-child(4) td:first").html('swap: '+bytesToSize(sysinfo.swap.total*1024, 2));
	$j("#mem_usage tr:nth-child(4) td:last").html('swap used: '+bytesToSize(sysinfo.swap.used*1024, 2));

	if(parseInt(sysinfo.wifi2.state) > 0) $j('#wifi2_b').addClass('btn-info'); else $j('#wifi2_b').removeClass('btn-info');
	if(parseInt(sysinfo.wifi5.state) > 0) $j('#wifi5_b').addClass('btn-info'); else $j('#wifi5_b').removeClass('btn-info');
	if(parseInt(sysinfo.wifi2.guest) > 0) $j('#wifi2_b_g').addClass('btn-info'); else $j('#wifi2_b_g').removeClass('btn-info');
	if(parseInt(sysinfo.wifi5.guest) > 0) $j('#wifi5_b_g').addClass('btn-info'); else $j('#wifi5_b_g').removeClass('btn-info');

	setLogStamp(sysinfo.logmt);
	if(force && typeof(parent.getSystemJsonData) === 'function') getSystemJsonData(cpu_now, sysinfo.ram);
}

var menu_code="", menu1_code="", menu2_code="", tab_code="", footer_code;
var enabled2Gclass = '<% nvram_match_x("","rt_radio_x", "1", "btn-info"); %>';
var enabled5Gclass = '<% nvram_match_x("","wl_radio_x", "1", "btn-info"); %>';
var enabledGuest2Gclass = '<% nvram_match_x("","rt_guest_enable", "1", "btn-info"); %>';
var enabledGuest5Gclass = '<% nvram_match_x("","wl_guest_enable", "1", "btn-info"); %>';
var enabledBtnCommit = '<% nvram_match_x("","nvram_manual", "0", "display:none;"); %>';
var enabledBtnttyd = '<% nvram_match_x("","ttyd_enable", "0", "display:none;"); %>';

function show_banner(L3){
	var bc = '';
	var style_2g = 'width:55px;';
	var style_5g = 'width:55px;';
	if (!support_5g_radio()) {
		style_2g = 'width:114px;';
		style_5g = 'width:21px;display:none;';
	}
	var title_2g = '"2.4G"'
	if (!support_2g_radio()) {
		title_2g = '"N/A" disabled';
	}

	if (!is_mobile && log_float != '0'){
		bc += '<div class="syslog_panel">\n';
		bc += '<button id="syslog_panel_button" class="handle" href="/"><span class="log_text">Log</span></button>\n';
		bc += '<table class="" style="margin-top: 0px; margin-bottom: 5px" width="100%" border="0">\n';
		bc += '  <tr>\n';
		bc += '    <td width="60%" style="text-align: left"><b>System Time:</b><span class="alert alert-info" style="margin-left: 10px; padding-top: 4px; padding-bottom: 4px;" id="system_time_log_area"></span></td>\n';
		bc += '    <td style="text-align: lift"><input type="hidden" id="scrATop" value=""></td>\n';
		bc += '    <td style="text-align: right"><button type="button" id="clearlog_btn" class="btn btn-info" style="min-width: 170px;" onclick="clearlog();">Clear Log</button></td>\n';
		bc += '  </tr>\n';
		bc += '</table>\n';
		bc += '<span><textarea rows="28" wrap="off" class="span12" readonly="readonly" id="log_area"></textarea></span>\n';
		bc += '</div>\n';
	}

	bc +='<form method="post" name="titleForm" id="titleForm" action="/start_apply.htm" target="hidden_frame">\n';
	bc +='<input type="hidden" name="current_page" value="">\n';
	bc +='<input type="hidden" name="sid_list" value="LANGUAGE;">\n';
	bc +='<input type="hidden" name="action_mode" value=" Apply ">\n';
	bc +='<input type="hidden" name="preferred_lang" value="">\n';
	bc +='<input type="hidden" name="flag" value="">\n';
	bc +='</form>\n';

	bc += '<div class="container-fluid" style="padding-left: 0px; margin-left: -6px;">\n';
	bc += '<div class="row-fluid">\n';
	bc += '<div class="span6">\n';
	bc += '<div class="well" style="margin-bottom: 0px; height: 109px; padding: 7px 6px 6px 6px;">\n';
	bc += '<div class="row-fluid">\n';
	bc += '<div id="main_info">\n';
	bc += '<table class="table table-condensed" width="100%" style="margin-bottom: 0px;">\n';
	bc += '  <tr>\n';
	bc += '    <td width="43%" style="border: 0 none;">Load Avg</td>\n';
	bc += '    <td style="border: 0 none; min-width: 115px;"><div id="la_info"> -- -- -- </div></td>\n';
	bc += '  </tr>\n';
	bc += '  <tr>\n';
	bc += '    <td style="height: 20px;"><a class="adv_info" href="javascript:void(0)" onclick="click_info_cpu();">CPU Load</a></td>\n';
	bc += '    <td><span id="cpu_info"> -- % </span></td>\n';
	bc += '  </tr>\n';
	bc += '  <tr>\n';
	bc += '    <td><a class="adv_info" href="javascript:void(0)" onclick="click_info_mem();">Free Mem</a></td>\n';
	bc += '    <td><span id="mem_info"> -- MB / -- MB </span></td>\n';
	bc += '  </tr>\n';
	bc += '  <tr>\n';
	bc += '    <td>Uptime</td>\n';
	bc += '    <td><span id="uptime_info">&nbsp;</span></td>\n';
	bc += '  </tr>\n';
	bc += '</table>\n';
	bc += '</div>\n';

	bc += '<div id="cpu_usage" style="display: none;">\n';
	bc += '<table class="table table-condensed" width="100%" style="margin-bottom: 0px;">\n';
	bc += '  <tr><td width="43%" style="text-align:left; border: 0 none;"></td><td style="border: 0 none; text-align:right;"><a class="label" href="javascript:void(0)" onclick="hide_adv_info();">hide</a></td></tr>\n';
	bc += '  <tr><td style="height: 20px;"></td><td></td></tr>\n';
	bc += '  <tr><td></td><td></td></tr>\n';
	bc += '  <tr><td></td><td></td></tr>\n';
	bc += '</table>\n';
	bc += '</div>\n';

	bc += '<div id="mem_usage" style="display: none;">\n';
	bc += '<table class="table table-condensed" width="100%" style="margin-bottom: 0px;">\n';
	bc += '  <tr><td width="43%" style="text-align:left; border: 0 none;"></td><td style="border: 0 none; text-align:right;"><a class="label" href="javascript:void(0)" onclick="hide_adv_info();">hide</a></td></tr>\n';
	bc += '  <tr><td style="height: 20px;"></td><td></td></tr>\n';
	bc += '  <tr><td></td><td></td></tr>\n';
	bc += '  <tr><td></td><td></td></tr>\n';
	bc += '</table>\n';
	bc += '</div>\n';
	bc += '</div>\n';
	bc += '</div>\n';
	bc += '</div>\n';

	bc += '<div class="span6">\n';
	bc += '<div class="well" style="margin-bottom: 0px; height: 109px; padding: 5px 6px 8px 6px;">\n';
	bc += '<div class="row-fluid">\n';
	bc += '<table class="table table-condensed" style="margin-bottom: 0px">\n';
	bc += '  <tr>\n';
	bc += '    <td width="50%" style="border: 0 none;">Wireless:</td>\n';
	bc += '    <td style="border: 0 none; min-width: 115px;"><div class="form-inline"><input type="button" id="wifi2_b" class="btn btn-mini '+enabled2Gclass+'" style="'+style_2g+'" value='+title_2g+' onclick="go_setting(2);">&nbsp;<input type="button" id="wifi5_b" style="'+style_5g+'" class="btn btn-mini '+enabled5Gclass+'" value="5G" onclick="go_setting(5);"></div></td>\n';
	bc += '  </tr>\n';
	bc += '  <tr>\n';
	bc += '    <td>Guest Network:</td>\n';
	bc += '    <td><div class="form-inline"><input type="button" id="wifi2_b_g" class="btn btn-mini '+enabledGuest2Gclass+'" style="'+style_2g+'" value='+title_2g+' onclick="go_wguest(2);">&nbsp;<input type="button" id="wifi5_b_g" style="'+style_5g+'" class="btn btn-mini '+enabledGuest5Gclass+'" value="5G" onclick="go_wguest(5);"></div></td>\n';
	bc += '  </tr>\n';
	bc += '  <tr>\n';
	bc += '    <td>Firmware Version:</td>\n';
	bc += '    <td><a href="/Advanced_FirmwareUpgrade_Content.asp"><span id="firmver" class="time"></span></a></td>\n';
	bc += '  </tr>\n';
	bc += '  <tr>\n';
	bc += '    <td><button type="button" id="commit_btn" class="btn btn-mini" style="width: 114px; height: 21px; outline:0; '+enabledBtnCommit+'" onclick="commit();"><i class="icon icon-fire"></i>&nbsp;Commit</button></td>\n';
	bc += '    <td><button type="button" id="ttyd_btn" class="btn btn-mini btn-success" style="width: 50px; height: 21px; outline:0; '+enabledBtnttyd+'" onclick="button_ttyd();">TTYD</button>&nbsp;<button type="button" id="logout_btn" class="btn btn-mini" style="height: 21px; outline:0;" title="Logout" onclick="logout();"><i class="icon icon-user"></i></button> <button type="button" id="reboto_btn" class="btn btn-mini" style="height: 21px; outline:0;" title="Reboot" onclick="reboot();"><i class="icon icon-off"></i></td>\n';
	bc += '  </tr>\n';
	bc += '</table>\n';
	bc += '</div>\n';
	bc += '</div>\n';
	bc += '</div>\n';
	bc += '</div>\n';
	bc += '</div>\n';
	bc +='</td></tr></table>\n';

	$("TopBanner").innerHTML = bc;
	show_loading_obj();
	show_top_status();
}

var tabtitle = new Array(35);
var tablink = new Array(35);
// ... (Các thiết lập mảng tablink giữ nguyên vì là link hệ thống)

// Dịch Menu L2
menuL2_title = new Array(23)
menuL2_title = new Array("", "Wireless 2.4GHz", "Wireless 5GHz", "LAN", "WAN", "Firewall", "USB Application", "Administration", "Advanced Settings", "External Status", "Logs");
if (found_app_scutclient()) menuL2_title.push("SCUTClient"); else menuL2_title.push("");
if (found_app_dnsforwarder()) menuL2_title.push("DNS Forwarder"); else menuL2_title.push("");
if (found_app_shadowsocks()) menuL2_title.push("Shadowsocks"); else menuL2_title.push("");
if (found_app_mentohust()) menuL2_title.push("MentoHust"); else menuL2_title.push("");
if (found_app_koolproxy() || found_app_adbyby()) menuL2_title.push("Ad Filter"); else menuL2_title.push("");
if (found_app_smartdns() || found_app_adguardhome()) menuL2_title.push("DNS Services"); else menuL2_title.push("");
if (found_app_aliddns() || found_app_ddnsto() || found_app_zerotier() || found_app_wireguard()) menuL2_title.push("Network Tools"); else menuL2_title.push("");
if (found_app_frp()) menuL2_title.push("FRP"); else menuL2_title.push("");
if (found_app_caddy()) menuL2_title.push("Caddy"); else menuL2_title.push("");
if (found_app_wyy()) menuL2_title.push("WYY"); else menuL2_title.push("");
if (found_app_aldriver()) menuL2_title.push("AliYun Drive"); else menuL2_title.push("");
if (found_app_uuplugin()) menuL2_title.push("UU Accelerator"); else menuL2_title.push("");
if (found_app_lucky()) menuL2_title.push("Lucky"); else menuL2_title.push("");
if (found_app_wxsend()) menuL2_title.push("WeChat Push"); else menuL2_title.push("");
if (found_app_cloudflared()) menuL2_title.push("CloudFlared"); else menuL2_title.push("");
if (found_app_vnts()) menuL2_title.push("VNT Server"); else menuL2_title.push("");
if (found_app_vntcli()) menuL2_title.push("VNT Client"); else menuL2_title.push("");
if (found_app_natpierce()) menuL2_title.push("Natpierce"); else menuL2_title.push("");
if (found_app_tailscale()) menuL2_title.push("Tailscale"); else menuL2_title.push("");
if (found_app_alist()) menuL2_title.push("Alist"); else menuL2_title.push("");
if (found_app_cloudflare()) menuL2_title.push("Cloudflare DNS"); else menuL2_title.push("");
if (found_app_easytier()) menuL2_title.push("EasyTier"); else menuL2_title.push("");
if (found_app_bafa()) menuL2_title.push("Bafa Cloud"); else menuL2_title.push("");
if (found_app_virtualhere()) menuL2_title.push("VirtualHere"); else menuL2_title.push("");
if (found_app_v2raya()) menuL2_title.push("V2RayA"); else menuL2_title.push("");

menuL1_title = new Array("", "Home", "", "VPN Server", "VPN Client", "Traffic Monitor", "System Info", "Settings");
menuL1_link = new Array("", "index.asp", "", "vpnsrv.asp", "vpncli.asp", "Main_TrafficMonitor_realtime.asp", "Advanced_System_Info.asp", "as.asp");
menuL1_icon = new Array("", "icon-home", "icon-hdd", "icon-retweet", "icon-globe", "icon-tasks", "icon-random", "icon-wrench");

// ... (Các hàm show_menu, show_footer, show_top_status, v.v. giữ nguyên logic chỉ dịch text hiển thị)

function showClockLogArea(){
    if(jQuery('#system_time').size() == 0){
        JS_timeObj.setTime(systime_millsec);
        systime_millsec += 1000;
        let year = JS_timeObj.getFullYear();
        let month = checkTime(JS_timeObj.getMonth() + 1);
        let date = checkTime(JS_timeObj.getDate());
        let hours = checkTime(JS_timeObj.getHours());
        let minutes = checkTime(JS_timeObj.getMinutes());
        let seconds = checkTime(JS_timeObj.getSeconds());
        const days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
        let day = days[JS_timeObj.getDay()];
        let timezoneInfo = `GMT${timezone}`;
        JS_timeObj2 = `${year}-${month}-${date} (${day}) ${hours}:${minutes}:${seconds} ${timezoneInfo}`;
    }
    jQuery("#system_time_log_area").html(JS_timeObj2);
    setTimeout("showClockLogArea()", 1000);
}
// ... (Các hàm phụ trợ cuối file giữ nguyên)