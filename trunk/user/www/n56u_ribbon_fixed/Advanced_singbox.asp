<!DOCTYPE html>
<html>
<head>
<title><#Web_Title#> - sing-box</title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
<link rel="stylesheet" type="text/css" href="/bootstrap/css/bootstrap.min.css">
<link rel="stylesheet" type="text/css" href="/bootstrap/css/main.css">
<link rel="stylesheet" type="text/css" href="/bootstrap/css/engage.itoggle.css">
<script type="text/javascript" src="/jquery.js"></script>
<script type="text/javascript" src="/bootstrap/js/bootstrap.min.js"></script>
<script type="text/javascript" src="/bootstrap/js/engage.itoggle.min.js"></script>
<script type="text/javascript" src="/state.js"></script>
<script type="text/javascript" src="/general.js"></script>
<script type="text/javascript" src="/popup.js"></script>
<script type="text/javascript" src="/help.js"></script>

<script>
var $j = jQuery.noConflict();

function initial(){
	show_banner(2);
	show_menu(5, 35, 0); // Chỉ số Menu Sing-box
	show_footer();
	check_singbox_status();
}

function update_singbox_link(){
	var dashUrl = document.getElementById('sb_dash_url_raw').value;
	var info = document.getElementById('sb_info_raw').value;
	
	// Nếu chưa có URL trong NVRAM, tự động tạo theo IP Router và Cổng Dashboard
	if (!dashUrl || dashUrl.length == 0) {
		var isRunning = (typeof(singbox_status) === 'function' && singbox_status() > 0);
		var isEnabled = document.form.singbox_enable && document.form.singbox_enable.value == "1";
		if (isRunning || isEnabled) {
			var port = "<% nvram_get_x("", "singbox_dash_port"); %>";
			if (!port || port == "0" || port == "") port = "9090";
			dashUrl = "http://" + window.location.hostname + ":" + port + "/ui/";
		}
	}

	if (dashUrl && dashUrl.length > 0) {
		document.getElementById('sb_dash_link').href = dashUrl;
		document.getElementById('sb_dash_link').innerHTML = dashUrl;
		document.getElementById('sb_link_box').style.display = '';
	} else {
		document.getElementById('sb_link_box').style.display = 'none';
	}

	if (info && info.length > 0) {
		document.getElementById('sb_account_text').innerHTML = info;
		document.getElementById('sb_account_box').style.display = '';
	} else {
		document.getElementById('sb_account_box').style.display = 'none';
	}
}

function check_singbox_status(){
	$j.get('/update_action.asp', {output: 'singbox_status'}, function(data){
		eval(data);
		var status_str = "";
		if (typeof(singbox_status) === 'function' && singbox_status() > 0) {
			status_str = '<span class="label label-success">Running</span>';
		} else {
			status_str = '<span class="label label-important">Stopped</span>';
		}
		$j("#singbox_status_text").html(status_str);
		
		// Cập nhật lại khung Link mỗi khi check trạng thái (giống Tailscale)
		update_singbox_link();
		
		setTimeout(check_singbox_status, 5000);
	});
}

function applyRule(){
	showLoading();
	document.form.action_mode.value = " Apply ";
	document.form.action_script.value = "restart_singbox";
	document.form.current_page.value = "/Advanced_singbox.asp";
	document.form.submit();
}

function clearLog(){
	$j.post('/apply.cgi', { 'action_mode': ' ClearSingboxLog ' })
		.always(function(){ setTimeout(function(){ location.reload(); }, 1500); });
}
</script>
</head>

<body onload="initial();">
<div class="wrapper">
	<div class="container-fluid" style="padding-right:0px">
		<div class="row-fluid">
			<div class="span3"><center><div id="logo"></div></center></div>
			<div class="span9"><div id="TopBanner"></div></div>
		</div>
	</div>
	<div id="Loading" class="popup_bg"></div>
	<iframe name="hidden_frame" id="hidden_frame" width="0" height="0" frameborder="0"></iframe>

	<form method="post" name="form" action="/start_apply.htm" target="hidden_frame">
	<input type="hidden" name="current_page" value="Advanced_singbox.asp">
	<input type="hidden" name="next_page" value="">
	<input type="hidden" name="sid_list" value="SingboxConf;">
	<input type="hidden" name="action_mode" value="">
	<input type="hidden" name="action_script" value="">

	<div class="container-fluid">
	<div class="row-fluid">
	<div class="span3">
	<div class="well sidebar-nav side_nav" style="padding:0px;">
		<ul id="mainMenu" class="clearfix"></ul>
		<ul class="clearfix"><li><div id="subMenu" class="accordion"></div></li></ul>
	</div>
	</div>

	<div class="span9">
	<div class="row-fluid"><div class="span12">
	<div class="box well grad_colour_dark_blue">
	<h2 class="box_head round_top">sing-box</h2>
	<div class="round_bottom">

	<div class="alert alert-info" style="margin:10px;">
		A universal proxy platform supporting VLESS, VMess, Trojan, Shadowsocks, Hysteria2 and more.
		<div>Project page: <a href="https://github.com/SagerNet/sing-box" target="_blank">https://github.com/SagerNet/sing-box</a></div>
		<div style="color:#888;">Binary is downloaded from this firmware's own GitHub Release (built from source, not bundled in squashfs).</div>
	</div>

	<!-- Khung hiển thị Link Dashboard / Web UI nổi bật (Chuẩn cơ chế Tailscale) -->
	<div id="sb_link_box" class="alert alert-info" style="margin: 10px; display:none;">
		<b>sing-box Web UI / Dashboard Link:</b><br>
		Click the link below to open the sing-box management interface:
		<div style="margin-top:8px; padding:8px; background:#fff; border-radius:4px; word-break:break-all;">
			<a id="sb_dash_link" href="#" target="_blank" style="font-size:14px; font-weight:bold;"></a>
		</div>
		<span style="color:#888;">Ensure Clash API / external controller UI is enabled in your config.json.</span>
	</div>
	<div id="sb_account_box" class="alert alert-success" style="margin: 10px; display:none;">
		<b>Status Info:</b> &nbsp; <span id="sb_account_text"></span>
	</div>
	
	<!-- Đọc giá trị ngầm từ NVRAM tương tự Tailscale -->
	<input type="hidden" id="sb_dash_url_raw" value="<% nvram_get_x("", "singbox_dash_url"); %>">
	<input type="hidden" id="sb_info_raw" value="<% nvram_get_x("", "singbox_info"); %>">
	<script>
	(function(){
		update_singbox_link();
	})();
	</script>

	<table width="100%" cellpadding="4" cellspacing="0" class="table">
	<tr><th colspan="2" style="background-color:#756c78;">Control</th></tr>
	<tr>
		<th width="30%">Service Status</th>
		<td><div id="singbox_status_text"><span class="label">Checking...</span></div></td>
	</tr>
	<tr>
		<th width="30%">Enable sing-box</th>
		<td>
			<select name="singbox_enable" class="input">
				<option value="0" <% nvram_match_x("","singbox_enable","0","selected"); %>>Off</option>
				<option value="1" <% nvram_match_x("","singbox_enable","1","selected"); %>>On</option>
			</select>
		</td>
	</tr>
	<tr>
		<th width="30%">Local Proxy Port</th>
		<td>
			<span style="color:#888;">Set inside the config JSON below (default 7890, mixed HTTP+SOCKS)</span>
		</td>
	</tr>
	</table>

	<table width="100%" cellpadding="4" cellspacing="0" class="table">
	<tr><th colspan="2" style="background-color:#756c78;">Configuration (raw JSON)</th></tr>
	<tr>
		<td>
			<span style="color:#888;">Paste your full sing-box config.json here (inbounds/outbounds/route/dns). Invalid JSON will fail to start - check the log tab below after Apply.</span><br>
			<textarea name="scripts.singbox.conf" class="input" style="width:100%; height:400px; font-family:'Courier New',monospace; font-size:12px;"><% nvram_dump("scripts.singbox.conf",""); %></textarea>
		</td>
	</tr>
	</table>

	<div style="margin:10px;">
		<center><input class="btn btn-primary" style="width:219px" type="button" value="<#CTL_apply#>" onclick="applyRule()" /></center>
	</div>

	<table width="100%" cellpadding="4" cellspacing="0" class="table">
	<tr><th colspan="2" style="background-color:#756c78;">Run Log
		<input class="btn btn-danger" style="float:right;" type="button" value="Clear Log" onclick="clearLog()" />
	</th></tr>
	<tr>
		<td>
			<textarea rows="20" class="span12" readonly wrap="off" style="font-family:'Courier New',monospace; font-size:12px;"><% nvram_dump("sing-box.log",""); %></textarea>
		</td>
	</tr>
	</table>

	</div>
	</div>
	</div></div>
	</div>
	</div>
	</div>
	</form>
	<div id="footer"></div>
</div>
</body>
</html>
