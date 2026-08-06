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
	show_menu(5, 30, 0);
	show_footer();
	$j("#tab_singbox_cfg, #tab_singbox_log").click(function () {
		var newHash = $j(this).attr('href').toLowerCase();
		showTab(newHash);
		return false;
	});
}

var arrHashes = ["cfg","log"];
function showTab(curHash) {
	var obj = $('tab_singbox_' + curHash.slice(1));
	if (obj == null || obj.style.display == 'none')
		curHash = '#cfg';
	for (var i = 0; i < arrHashes.length; i++) {
		if (curHash == ('#' + arrHashes[i])) {
			$j('#tab_singbox_' + arrHashes[i]).parents('li').addClass('active');
			$j('#wnd_singbox_' + arrHashes[i]).show();
		} else {
			$j('#wnd_singbox_' + arrHashes[i]).hide();
			$j('#tab_singbox_' + arrHashes[i]).parents('li').removeClass('active');
		}
	}
	window.location.hash = curHash;
}

function applyRule(){
	showLoading();
	document.form.action_mode.value = " Apply ";
	document.form.action_script.value = "restart_singbox";
	document.form.current_page.value = "/Advanced_singbox.asp";
	document.form.submit();
}

function toggleConfig(){
	var row = document.getElementById('singbox_config_row');
	row.style.display = (row.style.display === 'none') ? '' : 'none';
}

function loadFromUrl(){
	var url = document.getElementById('cfg_url').value.trim();
	var status = document.getElementById('cfg_url_status');
	if (!url) { status.innerHTML = 'Enter a URL first'; return; }
	status.innerHTML = 'Loading...';
	$j.ajax({
		url: url,
		dataType: 'text',
		timeout: 10000,
		success: function(data){
			try { JSON.parse(data); } catch(e) {
				status.innerHTML = '<span style="color:#d9534f;">Fetched, but not valid JSON - review before Apply</span>';
				document.getElementById('singbox_config').value = data;
				return;
			}
			document.getElementById('singbox_config').value = data;
			status.innerHTML = '<span style="color:#5cb85c;">Loaded OK - review then click Apply</span>';
		},
		error: function(){
			status.innerHTML = '<span style="color:#d9534f;">Failed to fetch (CORS or network) - paste manually instead</span>';
		}
	});
}

/* Nút kiểm tra Link Subscription hợp lệ */
function checkSubUrl(){
	var url = $j('#singbox_sub_url').val().trim();
	var status = $j('#sub_url_status');
	if(!url){ 
		status.html('<span style="color:#d9534f;">Vui lòng nhập URL trước!</span>'); 
		return; 
	}
	status.html('<span style="color:#f0ad4e;">Đang kiểm tra kết nối...</span>');
	$j.ajax({
		url: url,
		type: 'GET',
		timeout: 8000,
		success: function(data, textStatus, xhr){
			var size = data ? data.length : 0;
			if(size > 100){
				status.html('<span style="color:#5cb85c;">✅ Link hợp lệ! (HTTP 200 - Dung lượng: ' + Math.round(size/1024) + ' KB)</span>');
			} else {
				status.html('<span style="color:#d9534f;">❌ Dữ liệu trả về quá nhỏ hoặc rỗng</span>');
			}
		},
		error: function(xhr){
			var code = xhr.status ? xhr.status : 'Timeout/CORS';
			status.html('<span style="color:#d9534f;">❌ Kết nối thất bại (Mã lỗi: ' + code + ')</span>');
		}
	});
}

function openDashboard(){
	var ip = "<% nvram_get_x("","lan_ipaddr"); %>";
	window.open("http://" + ip + ":9090/ui", "_blank");
}

function clearLog(){
	$j.post('/apply.cgi', { 'action_mode': ' ClearSingboxLog ' })
		.always(function(){ setTimeout(function(){ location.reload(); }, 2000); });
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
	<div>
	<ul class="nav nav-tabs" style="margin-bottom: 10px;">
		<li class="active"><a id="tab_singbox_cfg" href="#cfg">Basic Settings</a></li>
		<li><a id="tab_singbox_log" href="#log">Run Log</a></li>
	</ul>
	</div>

	<div id="wnd_singbox_cfg">

	<div class="alert alert-info" style="margin:10px;">
		A universal proxy platform supporting VLESS, VMess, Trojan, Shadowsocks, Hysteria2 and more.
		<div>Project page: <a href="https://github.com/SagerNet/sing-box" target="blank">https://github.com/SagerNet/sing-box</a></div>
		<div style="color:#888;">Binary is downloaded from this firmware's own GitHub Release (built from source, not bundled in squashfs).</div>
	</div>

	<div style="margin:10px; text-align:center;">
		<a class="btn btn-success" style="width:260px; font-size:15px;" href="javascript:void(0);" onclick="openDashboard();">Open sing-box Dashboard</a>
	</div>

	<!-- BẢNG 1: ĐIỀU KHIỂN CƠ BẢN -->
	<table width="100%" cellpadding="4" cellspacing="0" class="table">
	<tr><th colspan="2" style="background-color:#756c78;">Basic Control</th></tr>
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
		<th>Running Mode</th>
		<td>
			<select name="singbox_mode" class="input">
				<option value="0" <% nvram_match_x("","singbox_mode","0","selected"); %>>Mode 1: Proxy Mode (Mixed Port 7890 - Chỉnh tay từng máy)</option>
				<option value="1" <% nvram_match_x("","singbox_mode","1","selected"); %>>Mode 2: TUN Mode (Toàn mạng LAN qua VPN tự động)</option>
				<option value="2" <% nvram_match_x("","singbox_mode","2","selected"); %>>Mode 3: Custom JSON (Dùng cấu hình bên dưới)</option>
			</select>
		</td>
	</tr>
	</table>

	<!-- BẢNG 2: QUẢN LÝ SUBSCRIPTION / LINK NODE -->
	<table width="100%" cellpadding="4" cellspacing="0" class="table">
	<tr><th colspan="2" style="background-color:#756c78;">Subscription & Node Management</th></tr>
	<tr>
		<th width="30%">Tên Nhóm / Thư mục</th>
		<td>
			<input type="text" name="singbox_sub_name" class="input" style="width:60%;" value="<% nvram_get_x("","singbox_sub_name"); %>" placeholder="Ví dụ: 🇻🇳 Gói VIP Viettel">
			<span style="color:#888; display:block;">Tên này sẽ hiển thị làm Thư mục phân loại trên Dashboard.</span>
		</td>
	</tr>
	<tr>
		<th>Link Subscription (URL)</th>
		<td>
			<input type="text" id="singbox_sub_url" name="singbox_sub_url" class="input" style="width:60%;" value="<% nvram_get_x("","singbox_sub_url"); %>" placeholder="https://example.com/sub/link">
			<input class="btn btn-info" type="button" value="🔍 Check Link" onclick="checkSubUrl();">
			<div id="sub_url_status" style="margin-top:5px;"></div>
		</td>
	</tr>
	</table>

	<!-- BẢNG 3: TỐI ƯU NÂNG CAO -->
	<table width="100%" cellpadding="4" cellspacing="0" class="table">
	<tr><th colspan="2" style="background-color:#756c78;">Optimization & Advanced Settings</th></tr>
	<tr>
		<th width="30%">Bypass IP/Tên miền VN</th>
		<td>
			<select name="singbox_bypass_vn" class="input">
				<option value="0" <% nvram_match_x("","singbox_bypass_vn","0","selected"); %>>Disable (Tất cả qua VPN)</option>
				<option value="1" <% nvram_match_x("","singbox_bypass_vn","1","selected"); %>>Enable (Cho IP/Web Việt Nam đi thẳng)</option>
			</select>
			<span style="color:#888; display:block;">Giúp vào trang web Việt Nam nhanh nhất và tiết kiệm dung lượng VPN.</span>
		</td>
	</tr>
	<tr>
		<th>Chặn quảng cáo (AdBlock)</th>
		<td>
			<select name="singbox_adblock" class="input">
				<option value="0" <% nvram_match_x("","singbox_adblock","0","selected"); %>>Disable</option>
				<option value="1" <% nvram_match_x("","singbox_adblock","1","selected"); %>>Enable (Chặn quảng cáo tự động)</option>
			</select>
		</td>
	</tr>
	<tr>
		<th>Chế độ DNS (DNS Mode)</th>
		<td>
			<select name="singbox_dns_mode" class="input">
				<option value="0" <% nvram_match_x("","singbox_dns_mode","0","selected"); %>>Direct (Mặc định)</option>
				<option value="1" <% nvram_match_x("","singbox_dns_mode","1","selected"); %>>FakeIP (Tăng tốc & Chống rò rỉ DNS)</option>
				<option value="2" <% nvram_match_x("","singbox_dns_mode","2","selected"); %>>DoH (Cloudflare / Google Secure DNS)</option>
			</select>
		</td>
	</tr>
	<tr>
		<th>Giới hạn RAM (Go Runtime)</th>
		<td>
			<select name="singbox_mem_limit" class="input">
				<option value="48MiB" <% nvram_match_x("","singbox_mem_limit","48MiB","selected"); %>>48 MB (Khuyên dùng cho NEWIFI3)</option>
				<option value="64MiB" <% nvram_match_x("","singbox_mem_limit","64MiB","selected"); %>>64 MB</option>
				<option value="96MiB" <% nvram_match_x("","singbox_mem_limit","96MiB","selected"); %>>96 MB</option>
			</select>
		</td>
	</tr>
	</table>

	<!-- BẢNG 4: RAW CONFIG JSON -->
	<table width="100%" cellpadding="4" cellspacing="0" class="table">
	<tr><th colspan="2" style="background-color:#756c78;">
		Configuration (raw JSON - Dùng cho Mode 3)
		<input class="btn btn-mini" style="float:right;" type="button" value="Show/Hide" onclick="toggleConfig();" />
	</th></tr>
	<tr id="singbox_config_row" style="display:none;">
		<td>
			<div style="margin-bottom:8px;">
				<input type="text" id="cfg_url" class="input" placeholder="https://example.com/config.json" style="width:60%;">
				<input class="btn btn-info" type="button" value="Load from URL" onclick="loadFromUrl();">
				<span id="cfg_url_status" style="color:#888; margin-left:8px;"></span>
			</div>
			<span style="color:#888;">Paste your full sing-box config.json here (inbounds/outbounds/route/dns), or fetch it from a URL above. Invalid JSON will fail to start - check the Run Log tab after Apply.</span><br>
			<textarea name="singbox_config" id="singbox_config" class="input" style="width:100%; height:400px; font-family:'Courier New',monospace; font-size:12px;"><% nvram_dump_x("scripts.singbox.conf",""); %></textarea>
		</td>
	</tr>
	</table>

	<div style="margin:10px;">
		<center><input class="btn btn-primary" style="width:219px" type="button" value="<#CTL_apply#>" onclick="applyRule()" /></center>
	</div>

	</div>

	<!-- TAB RUN LOG -->
	<div id="wnd_singbox_log" style="display:none;">
	<div class="alert alert-info" style="margin:10px;">Live log output from sing-box.
		<input class="btn btn-danger" style="float:right;" type="button" value="Clear Log" onclick="clearLog()" />
	</div>
	<textarea rows="21" class="span12" style="height:377px; font-family:'Courier New', Courier, mono; font-size:13px;" readonly="readonly" wrap="off" id="textarea"><% nvram_dump("sing-box.log",""); %></textarea>
	</div>

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
