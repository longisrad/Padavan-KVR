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
<script type="text/javascript" src="/itoggle.js"></script>
<script type="text/javascript" src="/popup.js"></script>
<script type="text/javascript" src="/help.js"></script>

<script>
var $j = jQuery.noConflict();

/* Khởi tạo Nút gạt Toggle theo đúng chuẩn Padavan / Tailscale */
$j(document).ready(function() {
	init_itoggle('singbox_enable');
	init_itoggle('singbox_bypass_vn');
	init_itoggle('singbox_adblock');
	init_itoggle('singbox_auto_update');
});

var subList = [];
var editingIndex = -1;

function initial(){
	show_banner(2);
	show_menu(5, 30, 0);
	show_footer();
	$j("#tab_singbox_cfg, #tab_singbox_log").click(function () {
		var newHash = $j(this).attr('href').toLowerCase();
		showTab(newHash);
		return false;
	});
	loadSubList();
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
			if (arrHashes[i] === 'log') {
				refreshLog();
			}
		} else {
			$j('#wnd_singbox_' + arrHashes[i]).hide();
			$j('#tab_singbox_' + arrHashes[i]).parents('li').removeClass('active');
		}
	}
	window.location.hash = curHash;
}

/* Nạp và cuộn log tự động */
function refreshLog(){
	$j.get('/singbox.log?_t=' + new Date().getTime(), function(data){
		if(data && data.trim() !== "") {
			$j('#textarea').val(data);
		}
		scrollLogToBottom();
	}).fail(function(){
		$j.get('/sing-box.log?_t=' + new Date().getTime(), function(data2){
			if(data2 && data2.trim() !== "") {
				$j('#textarea').val(data2);
			}
			scrollLogToBottom();
		});
	});
}

function scrollLogToBottom(){
	var textarea = document.getElementById('textarea');
	if (textarea) {
		textarea.scrollTop = textarea.scrollHeight;
	}
}

/* Quản lý danh sách Sub (Thêm / Sửa / Xóa) */
function loadSubList(){
	var raw = $j('#singbox_sub_list').val();
	if (raw && raw.trim() !== "") {
		try { subList = JSON.parse(raw); } catch(e) { subList = []; }
	}
	if (subList.length === 0) {
		var oldName = "<% nvram_get_x("","singbox_sub_name"); %>";
		var oldUrl = "<% nvram_get_x("","singbox_sub_url"); %>";
		if (oldUrl && oldUrl.trim() !== "") {
			subList.push({ name: oldName || "Gói Mặc Định", url: oldUrl });
			saveSubList();
		}
	}
	renderSubTable();
}

function saveSubList(){
	$j('#singbox_sub_list').val(JSON.stringify(subList));
}

function renderSubTable(){
	var tbody = $j('#sub_list_tbody');
	tbody.empty();
	if (subList.length === 0) {
		tbody.append('<tr><td colspan="3" style="text-align:center; color:#888;">Chưa có Thư mục / Link Sub nào. Hãy nhập thông tin bên trên và nhấn "Thêm Thư mục".</td></tr>');
		return;
	}
	for (var i = 0; i < subList.length; i++) {
		var item = subList[i];
		var row = '<tr>' +
			'<td width="30%"><b>' + escapeHtml(item.name) + '</b></td>' +
			'<td style="word-break:break-all; font-size:12px; color:#aaa;">' + escapeHtml(item.url) + '</td>' +
			'<td width="20%" style="text-align:center;">' +
				'<button type="button" class="btn btn-mini btn-warning" onclick="editSub(' + i + ')">✏️ Sửa</button> ' +
				'<button type="button" class="btn btn-mini btn-danger" onclick="deleteSub(' + i + ')">🗑️ Xóa</button>' +
			'</td>' +
		'</tr>';
		tbody.append(row);
	}
}

function addOrUpdateSub(){
	var name = $j('#input_sub_name').val().trim();
	var url = $j('#input_sub_url').val().trim();
	if (!name) { alert("Vui lòng nhập Tên Nhóm / Thư mục!"); return; }
	if (!url) { alert("Vui lòng nhập Link Subscription!"); return; }

	if (editingIndex >= 0) {
		subList[editingIndex] = { name: name, url: url };
		editingIndex = -1;
		$j('#btn_add_sub').val("➕ Thêm Thư mục").removeClass("btn-primary").addClass("btn-success");
	} else {
		subList.push({ name: name, url: url });
	}

	saveSubList();
	renderSubTable();
	$j('#input_sub_name').val('');
	$j('#input_sub_url').val('');
	$j('#sub_url_status').html('');
}

function editSub(index){
	editingIndex = index;
	$j('#input_sub_name').val(subList[index].name);
	$j('#input_sub_url').val(subList[index].url);
	$j('#btn_add_sub').val("💾 Cập nhật Thư mục").removeClass("btn-success").addClass("btn-primary");
}

function deleteSub(index){
	if (confirm("Bạn có chắc chắn muốn xóa Thư mục này khỏi danh sách?")) {
		subList.splice(index, 1);
		if (editingIndex === index) {
			editingIndex = -1;
			$j('#input_sub_name').val('');
			$j('#input_sub_url').val('');
			$j('#btn_add_sub').val("➕ Thêm Thư mục").removeClass("btn-primary").addClass("btn-success");
		}
		saveSubList();
		renderSubTable();
	}
}

function checkSubUrl(){
	var url = $j('#input_sub_url').val().trim();
	var status = $j('#sub_url_status');
	if(!url){ 
		status.html('<span style="color:#d9534f;">Vui lòng nhập Link Subscription trước!</span>'); 
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
				status.html('<span style="color:#d9534f;">❌ Dữ liệu phản hồi quá nhỏ hoặc rỗng</span>');
			}
		},
		error: function(xhr){
			var code = xhr.status ? xhr.status : 'Timeout/CORS';
			status.html('<span style="color:#d9534f;">❌ Kết nối thất bại (Mã lỗi: ' + code + ')</span>');
		}
	});
}

function escapeHtml(text){
	return $j('<div/>').text(text).html();
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

function openDashboard(){
	var ip = "<% nvram_get_x("","lan_ipaddr"); %>";
	window.open("http://" + ip + ":9090/ui", "_blank");
}

/* Cập nhật thủ công toàn bộ nguồn Subscription ngay lập tức (bỏ qua chu kỳ 3 ngày) */
function updateSubNow(){
	var $j = jQuery.noConflict();
	var status = $j('#update_sub_status');
	status.html('<span style="color:#f0ad4e;">⏳ Đang tải lại Subscription và khởi động lại sing-box, vui lòng đợi ít phút...</span>');
	$j.post('/apply.cgi', {
		'action_mode': ' UpdateSingboxSub ',
		'next_host': 'Advanced_singbox.asp#cfg'
	}).always(function() {
		status.html('<span style="color:#5cb85c;">✅ Đã gửi lệnh cập nhật! Chuyển qua tab "Run Log" để xem tiến trình.</span>');
	});
}

/* Xóa Log chuẩn theo mẫu Tailscale */
function clearLog(){
	var $j = jQuery.noConflict();
	$j.post('/apply.cgi', {
		'action_mode': ' ClearSingboxLog ',
		'next_host': 'Advanced_singbox.asp#log'
	}).always(function() {
		setTimeout(function() {
			location.reload(); 
		}, 2000);
	});
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

	<!-- Variable ẩn lưu chuỗi JSON danh sách Sub -->
	<input type="hidden" name="singbox_sub_list" id="singbox_sub_list" value="<% nvram_get_x("","singbox_sub_list"); %>">

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
			<!-- Nút gạt chuẩn Padavan / Tailscale -->
			<div class="main_itoggle">
				<div id="singbox_enable_on_of">
					<input type="checkbox" id="singbox_enable_fake" <% nvram_match_x("", "singbox_enable", "1", "value=1 checked"); %><% nvram_match_x("", "singbox_enable", "0", "value=0"); %> />
				</div>
			</div>
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

	<!-- BẢNG 2: QUẢN LÝ SUBSCRIPTION VÀ THƯ MỤC -->
	<table width="100%" cellpadding="4" cellspacing="0" class="table">
	<tr><th colspan="2" style="background-color:#756c78;">Quản lý Thư mục & Link Subscription</th></tr>
	<tr>
		<th width="30%">Thêm / Sửa Thư mục</th>
		<td>
			<div style="margin-bottom:6px;">
				<input type="text" id="input_sub_name" class="input" style="width:40%;" placeholder="Tên Thư mục (VD: 🇻🇳 Gói VIP Viettel)">
				<input type="text" id="input_sub_url" class="input" style="width:52%;" placeholder="Link Subscription (https://...)">
			</div>
			<div>
				<input class="btn btn-info" type="button" value="🔍 Check Link" onclick="checkSubUrl();">
				<input class="btn btn-success" id="btn_add_sub" type="button" value="➕ Thêm Thư mục" onclick="addOrUpdateSub();">
				<span id="sub_url_status" style="margin-left:8px;"></span>
			</div>
		</td>
	</tr>
	<tr>
		<th>Cập nhật nguồn Sub</th>
		<td>
			<input class="btn btn-warning" type="button" value="🔄 Cập nhật Sub ngay" onclick="updateSubNow();">
			<span style="color:#888; margin-left:6px;">Tải lại toàn bộ Link Subscription ở trên và khởi động lại sing-box.</span>
			<div id="update_sub_status" style="margin-top:6px;"></div>
		</td>
	</tr>
	<tr>
		<td colspan="2">
			<!-- Bảng hiển thị danh sách Sub đã thêm -->
			<table class="table table-bordered table-striped" style="margin-bottom:0;">
				<thead>
					<tr style="background-color:#5a525d; color:#fff;">
						<th>Tên Thư mục / Nhóm</th>
						<th>Link Subscription</th>
						<th style="text-align:center;">Hành động</th>
					</tr>
				</thead>
				<tbody id="sub_list_tbody">
					<!-- Các hàng dữ liệu được tự động render bằng JS -->
				</tbody>
			</table>
		</td>
	</tr>
	</table>

	<!-- BẢNG 3: TỐI ƯU NÂNG CAO -->
	<table width="100%" cellpadding="4" cellspacing="0" class="table">
	<tr><th colspan="2" style="background-color:#756c78;">Optimization & Advanced Settings</th></tr>
	<tr>
		<th width="30%">Bypass IP/Tên miền VN</th>
		<td>
			<!-- Nút gạt chuẩn Padavan / Tailscale -->
			<div class="main_itoggle">
				<div id="singbox_bypass_vn_on_of">
					<input type="checkbox" id="singbox_bypass_vn_fake" <% nvram_match_x("", "singbox_bypass_vn", "1", "value=1 checked"); %><% nvram_match_x("", "singbox_bypass_vn", "0", "value=0"); %> />
				</div>
			</div>
			<span style="color:#888; margin-left:10px; display:inline-block; vertical-align:middle;">Bật để IP/Web Việt Nam đi thẳng (không qua VPN) giúp tối ưu tốc độ.</span>
		</td>
	</tr>
	<tr>
		<th>Chặn quảng cáo (AdBlock)</th>
		<td>
			<!-- Nút gạt chuẩn Padavan / Tailscale -->
			<div class="main_itoggle">
				<div id="singbox_adblock_on_of">
					<input type="checkbox" id="singbox_adblock_fake" <% nvram_match_x("", "singbox_adblock", "1", "value=1 checked"); %><% nvram_match_x("", "singbox_adblock", "0", "value=0"); %> />
				</div>
			</div>
		</td>
	</tr>
	<tr>
		<th width="30%">Tự động cập nhật Sub (3 ngày/lần)</th>
		<td>
			<!-- Nút gạt chuẩn Padavan / Tailscale -->
			<div class="main_itoggle">
				<div id="singbox_auto_update_on_of">
					<input type="checkbox" id="singbox_auto_update_fake" <% nvram_match_x("", "singbox_auto_update", "1", "value=1 checked"); %><% nvram_match_x("", "singbox_auto_update", "0", "value=0"); %> />
				</div>
			</div>
			<span style="color:#888; margin-left:10px; display:inline-block; vertical-align:middle;">Router tự tải lại toàn bộ Subscription và khởi động lại sing-box mỗi 3 ngày (kiểm tra mỗi ngày lúc 4h sáng).</span>
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
			<span style="color:#888;">Paste your full sing-box config.json here (inbounds/outbounds/route/dns). Invalid JSON will fail to start - check the Run Log tab after Apply.</span><br>
			<textarea name="singbox_config" id="singbox_config" class="input" style="width:100%; height:400px; font-family:'Courier New',monospace; font-size:12px;"><% nvram_dump_x("scripts.singbox.conf",""); %></textarea>
		</td>
	</tr>
	</table>

	<div style="margin:10px;">
		<center><input class="btn btn-primary" style="width:219px" type="button" value="<#CTL_apply#>" onclick="applyRule()" /></center>
	</div>

	</div>

	<!-- TAB RUN LOG (ĐÃ SỬA ĐỒNG BỘ ĐỌC CẢ DẠNG KHÔNG DẤU VÀ CÓ DẤU GẠCH) -->
	<div id="wnd_singbox_log" style="display:none;">
	<div class="alert alert-info" style="margin:10px; overflow:hidden;">
		Live log output from sing-box.
		<input class="btn btn-danger" style="float:right;" type="button" value="Clear Log" onclick="clearLog()" />
	</div>
	<textarea rows="21" class="span12" style="height:377px; font-family:'Courier New', Courier, mono; font-size:13px;" readonly="readonly" wrap="off" id="textarea"><% nvram_dump("singbox.log",""); %><% nvram_dump("sing-box.log",""); %></textarea>
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
