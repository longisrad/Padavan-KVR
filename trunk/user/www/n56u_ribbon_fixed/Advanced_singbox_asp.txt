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

// Gia tri nvram tailscale_enable (app Tailscale doc lap - KHAC voi
// singbox_ts_enable). Doc server-side vi trang nay khong co control nao
// cho bien do (thuoc trang/app khac), can biet de gate nut Bat sing-box.
var standaloneTsEnabled = ("<% nvram_get_x("", "tailscale_enable"); %>" === "1");

$j(document).ready(function() {
	init_itoggle('singbox_enable');
	init_itoggle('singbox_bypass_vn');
	init_itoggle('singbox_adblock');
	init_itoggle('singbox_dns_redirect');
	init_itoggle('singbox_auto_update');
	init_itoggle('singbox_ts_enable');
	init_itoggle('singbox_ts_accept_routes');
	init_itoggle('singbox_ts_ephemeral');
	init_itoggle('singbox_ts_exit_node_allow_lan');
	init_itoggle('singbox_ts_advertise_exit_node');
	init_itoggle('singbox_ts_ssh_server');
	updateUiVisibility();

	// singbox_enable la itoggle (khong phai <select> co san onchange), nen
	// phai tu bind click vao div wrapper de bat lai gating tab Tailscale
	// ngay sau khi nguoi dung bam Bat/Tat sing-box. setTimeout 50ms de doi
	// itoggle.js (engage.itoggle.min.js) cap nhat xong radio/checkbox that
	// truoc khi minh doc lai trang thai - giong pattern initial() ben duoi
	// dang dung setTimeout 100/500 de chong loi cache y het.
	$j('#singbox_enable_on_of').on('click', function(){ setTimeout(updateUiVisibility, 50); });
});

var subList = [];

function initial(){
	show_banner(2);
	show_menu(5, 30, 0);
	show_footer();
	fetchSubListFromRouter();
	updateUiVisibility();
	setTimeout(updateUiVisibility, 100);
	setTimeout(updateUiVisibility, 500);
}

function fetchSubListFromRouter(){
	$j.post('/apply.cgi', {
		'action_mode': ' GetSingboxSubList '
	}).done(function(data){
		try {
			subList = (typeof data === 'string') ? JSON.parse(data) : data;
			if (!Array.isArray(subList)) subList = [];
		} catch(e) {
			subList = [];
		}
		renderSubTable();
	}).fail(function(){
		subList = [];
		renderSubTable();
	});
}

function renderSubTable(){
	var tbody = $j('#sub_list_tbody');
	tbody.empty();
	if (!subList || subList.length === 0) {
		tbody.append('<tr><td colspan="4" style="text-align:center; color:#888;">Chưa có Link Sub nào trên /etc/storage. Hãy dán Link bên trên và bấm "Thêm Sub".</td></tr>');
		return;
	}
	for (var i = 0; i < subList.length; i++) {
		var item = subList[i];
		var isEnabled = (item.enabled !== false && item.enabled !== "0");
		var statusBadge = isEnabled 
			? '<button type="button" class="btn btn-mini btn-success" onclick="toggleSub(' + i + ')">🟢 BẬT</button>' 
			: '<button type="button" class="btn btn-mini btn-secondary" onclick="toggleSub(' + i + ')">🔴 TẮT</button>';
		
		var row = '<tr>' +
			'<td width="10%" style="text-align:center;">' + statusBadge + '</td>' +
			'<td width="28%"><b>' + escapeHtml(item.name || ("Gói Sub " + (i+1))) + '</b></td>' +
			'<td style="word-break:break-all; font-size:12px; color:#aaa;">' + escapeHtml(item.url) + '</td>' +
			'<td width="20%" style="text-align:center;">' +
				'<button type="button" class="btn btn-mini btn-danger" onclick="deleteSub(' + i + ')">🗑️ Xóa</button>' +
			'</td>' +
		'</tr>';
		tbody.append(row);
	}
}

function addSubDirect(){
	var name = $j('#input_sub_name').val().trim();
	var url = $j('#input_sub_url').val().trim();
	if (!url) { alert("Vui lòng nhập Link Subscription!"); return; }
	if (!name) { name = "Gói Proxy " + (subList.length + 1); }

	$j('#sub_url_status').html('<span style="color:#f0ad4e;">Đang ghi trực tiếp vào /etc/storage...</span>');
	$j.post('/apply.cgi', {
		'action_mode': ' AddSingboxSub ',
		'sub_name': name,
		'sub_url': url
	}).always(function(){
		$j('#input_sub_name').val('');
		$j('#input_sub_url').val('');
		$j('#sub_url_status').html('<span style="color:#5cb85c;">✅ Đã ghi vào /etc/storage!</span>');
		setTimeout(fetchSubListFromRouter, 800);
	});
}

function deleteSub(index){
	if (confirm("Bạn có chắc chắn muốn xóa Sub này khỏi /etc/storage?")) {
		$j.post('/apply.cgi', {
			'action_mode': ' DelSingboxSub ',
			'sub_idx': index
		}).always(function(){
			setTimeout(fetchSubListFromRouter, 800);
		});
	}
}

function toggleSub(index){
	$j.post('/apply.cgi', {
		'action_mode': ' ToggleSingboxSub ',
		'sub_idx': index
	}).always(function(){
		setTimeout(fetchSubListFromRouter, 800);
	});
}

function loadDefaultPresetSubs(){
	if (confirm("Nạp các nguồn Sub mẫu miễn phí vào /etc/storage?")) {
		$j.post('/apply.cgi', {
			'action_mode': ' PresetSingboxSub '
		}).always(function(){
			setTimeout(fetchSubListFromRouter, 800);
		});
	}
}

function checkSubUrl(){
	var url = $j('#input_sub_url').val().trim();
	var status = $j('#sub_url_status');
	if(!url){ status.html('<span style="color:#d9534f;">Vui lòng nhập Link Subscription trước!</span>'); return; }
	status.html('<span style="color:#f0ad4e;">Đang kiểm tra kết nối...</span>');
	$j.post('/apply.cgi', {
		'action_mode': ' CheckSingboxSubUrl ',
		'check_url': url
	}).done(function(data){
		var res;
		try { res = (typeof data === 'string') ? JSON.parse(data) : data; } catch(e) { res = null; }
		if(res && res.ok){
			status.html('<span style="color:#5cb85c;">✅ Link hợp lệ! (HTTP ' + res.http_code + ')</span>');
		} else {
			status.html('<span style="color:#d9534f;">❌ Lỗi kết nối tới link</span>');
		}
	});
}

function fetchTsLoginUrl(){
	var status = $j('#ts_login_url_status');
	var box = $j('#ts_login_url_box');
	var link = $j('#ts_login_url_link');
	status.html('<span style="color:#f0ad4e;">Đang lấy link từ log (chờ sing-box khởi động xong nếu vừa Apply)...</span>');
	box.hide();
	$j.post('/apply.cgi', {
		'action_mode': ' GetSingboxTsUrl '
	}).done(function(data){
		var res;
		try { res = (typeof data === 'string') ? JSON.parse(data) : data; } catch(e) { res = null; }
		if(res && res.url){
			status.html('<span style="color:#5cb85c;">✅ Đã tìm thấy link - bấm vào để đăng nhập (mở tab mới):</span>');
			link.attr('href', res.url).text(res.url);
			box.show();
		} else {
			status.html('<span style="color:#d9534f;">Chưa thấy link trong log. Có thể node đã đăng nhập trước đó rồi, hoặc cần Apply + đợi vài giây rồi bấm lại.</span>');
		}
	}).fail(function(){
		status.html('<span style="color:#d9534f;">Lỗi khi gọi Router.</span>');
	});
}

function forceUpdateSub(){
	showLoading();
	document.form.action_mode.value = " Apply ";
	document.form.action_script.value = "update_singbox_sub";
	document.form.current_page.value = "/Advanced_singbox.asp";
	document.form.submit();
}

function generateClientLinks(){
	$j('#client_links_area').val('Đang tạo link kết nối cho thiết bị con...');
	$j('#wnd_client_links').show();
	$j.post('/apply.cgi', {
		'action_mode': ' RunGenLinks '
	}).always(function(){
		setTimeout(function(){
			$j.post('/apply.cgi', {
				'action_mode': ' GetSingboxClients '
			}).done(function(data){
				$j('#client_links_area').val(data || 'Chưa có dữ liệu link clients');
			}).fail(function(){
				$j('#client_links_area').val('Lỗi khi tải dữ liệu clients từ Router');
			});
		}, 1500);
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
	if (row) {
		row.style.display = (row.style.display === 'none') ? '' : 'none';
	}
}

function openDashboard(){
	var ip = "<% nvram_get_x("","lan_ipaddr"); %>";
	window.open("http://" + ip + ":9090/ui/#/setup?host=" + ip + "&port=9090", "_blank");
}

/* Tu dong BAT redirect DNS khi chuyen sang TProxy Mode - chi chay khi
   user CHU DONG doi dropdown Mode (onchange), KHONG goi trong
   updateUiVisibility() vi ham do con chay ca luc page load/reload, neu
   ep bat o do se ghi de len lua chon TAT redirect nguoi dung da luu
   truoc do (VD dang ket hop AdGuard Home can TAT redirect).
   Khong dung .trigger('click') vi itoggle.js (init_itoggle) khong bind
   click truc tiep vao checkbox _fake - no bind vao div _on_of qua plugin
   .iToggle(), roi tu set checkbox/radio trong callback onClickOn/
   onClickOff. Nen o day set thang y het logic onClickOn cua itoggle.js:
   checkbox _fake, 2 radio _0/_1, va background-position cua label de
   khop UI voi trang thai moi. */
function onModeChange(){
	var modeSelect = $j('#singbox_mode_select');
	if (modeSelect.length && modeSelect.val() === "1") {
		var objF = $j('#singbox_dns_redirect_fake');
		if (objF.length && !objF.is(':checked')) {
			var objO = $j('#singbox_dns_redirect_0');
			var obj1 = $j('#singbox_dns_redirect_1');
			objF.attr("checked", "checked").attr("value", 1);
			obj1.attr("checked", "checked");
			objO.removeAttr("checked");
			$j('#singbox_dns_redirect_on_of label.itoggle').css("background-position", '0% -27px');
		}
	}
	updateUiVisibility();
}

/* LOGIC ĐIỀU KHIỂN GIAO DIỆN HOÀN CHỈNH (CHỐNG LỖI CACHE KHU BẤM APPLY) */
function updateUiVisibility(){
	var modeSelect = $j('#singbox_mode_select');
	if (!modeSelect.length) return;

	var mode = modeSelect.val(); // 0: Mixed, 1: TProxy, 2: Custom
	var dnsSelect = $j('#singbox_dns_mode_select');
	var dnsMode = dnsSelect.val();

	var dnsModeRow = $j('#singbox_dns_mode_row')[0];
	var bypassRow = $j('#singbox_bypass_vn_row')[0];
	var adblockRow = $j('#singbox_adblock_row')[0];
	var redirectRow = $j('#singbox_dns_redirect_row')[0];
	var configRow = $j('#singbox_config_row')[0];
	var tsRow = $j('#singbox_ts_table')[0];

	// 1. Chế độ Custom JSON (Mode 2)
	if (mode === "2") {
		if (dnsModeRow) dnsModeRow.style.display = 'none';
		if (bypassRow) bypassRow.style.display = 'none';
		if (adblockRow) adblockRow.style.display = 'none';
		if (redirectRow) redirectRow.style.display = 'none';
		if (tsRow) tsRow.style.display = 'none';
		if (configRow) configRow.style.display = '';
		return;
	} else {
		if (configRow) configRow.style.display = 'none';
		if (tsRow) tsRow.style.display = '';
	}

	// 2. Chế độ Mixed Proxy (Mode 0) và TProxy Mode (Mode 1)
	if (dnsModeRow) dnsModeRow.style.display = '';
	if (bypassRow) bypassRow.style.display = '';
	if (adblockRow) adblockRow.style.display = '';

	var optFakeIp = dnsSelect.find('option[value="1"]');

	if (mode === "0") {
		// Mixed Mode: Vừa vô hiệu hóa vừa ẩn option FakeIP
		optFakeIp.prop('disabled', true).hide();
		if (dnsMode === "1") {
			dnsSelect.val("2"); // Nếu đang dính FakeIP thì tự chuyển về DoH
		}
		// Ép ẩn dòng Redirect DNS 53
		if (redirectRow) redirectRow.style.display = 'none';
		var hintMixed = $j('#dns_redirect_hint');
		if (hintMixed.length) hintMixed.html('');
	} else if (mode === "1") {
		// TProxy Mode: Mở lại option FakeIP
		optFakeIp.prop('disabled', false).show();
		
		// Hiện dòng Redirect DNS 53
		if (redirectRow) redirectRow.style.display = '';

		// Cập nhật chú thích - chỉ phụ thuộc vào Mode (TProxy), không phân
		// nhánh theo DNS Mode nữa
		var hint = $j('#dns_redirect_hint');
		if (hint.length) {
			hint.html('<span style="color:#f0ad4e; margin-left:10px;">(Khuyên BẬT khi chạy độc lập; TẮT nếu kết hợp với các dịch vụ DNS khác làm DNS chính).</span>');
		}
	}

	// 2.5. Gating nut "Bat sing-box": neu Tailscale doc lap (standalone,
	// nvram tailscale_enable - KHAC voi singbox_ts_enable) dang BAT, sing-box
	// se tu choi khoi dong hoan toan (xem guard trong ham start() cua
	// singbox.sh). Hien warning + khoa han nut bang pointer-events:none +
	// opacity (giong ky thuat da dung cho tsTable ben duoi), vi day CHI la
	// rao chan UX - logic that su van nam o phia script.
	var warnRow = $j('#singbox_conflict_warning_row')[0];
	var enableToggleDiv = $j('#singbox_enable_on_of');
	if (standaloneTsEnabled) {
		if (warnRow) warnRow.style.display = '';
		enableToggleDiv.css({ opacity: '0.4', pointerEvents: 'none' });
		$j('#singbox_enable_1, #singbox_enable_0').prop('disabled', true);
	} else {
		if (warnRow) warnRow.style.display = 'none';
		enableToggleDiv.css({ opacity: '1', pointerEvents: 'auto' });
		$j('#singbox_enable_1, #singbox_enable_0').prop('disabled', false);
	}

	// 3. Gating tab Tailscale: bat buoc phai BAT sing-box (tab sing-box) va
	// Apply truoc thi tab Tailscale moi cho chinh sua. Day CHI la rao chan
	// phia giao dien (UX) - khong thay the kiem tra logic that su o phia
	// singbox.sh (script da tu chan hoan toan viec sing-box khoi dong khi
	// phat hien Tailscale native dang bat, xem ham start()/check_ts_conflict).
	// Dung pointer-events:none + opacity thay vi chi disabled cac input, vi
	// cac itoggle (main_itoggle) bind click vao div wrapper ngoai, khong
	// tuan theo thuoc tinh disabled cua checkbox an ben trong.
	var sbEnabled = $j('#singbox_enable_fake').is(':checked');
	var tsWarn = $j('#singbox_ts_disabled_warning')[0];
	var tsTable = $j('#singbox_ts_table');
	if (sbEnabled) {
		if (tsWarn) tsWarn.style.display = 'none';
		tsTable.css({ opacity: '1', pointerEvents: 'auto' });
		tsTable.find('input, select, textarea').prop('disabled', false);
	} else {
		if (tsWarn) tsWarn.style.display = '';
		tsTable.css({ opacity: '0.45', pointerEvents: 'none' });
		tsTable.find('input, select, textarea').prop('disabled', true);
	}
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
	<h2 class="box_head round_top">sing-box Smart Proxy</h2>
	<div class="round_bottom">

	<div class="alert alert-info" style="margin:10px;">
		Nền tảng Proxy đa giao thức hỗ trợ VLESS, VMess, Trojan, Shadowsocks, Hysteria2, TUIC và Mieru.
		<div>Tích hợp sẵn: <b>TProxy Full Mạng LAN</b>, <b>FakeIP Cổng 5353</b> và <b>Bypass Tailscale</b>.</div>
	</div>

	<div style="margin:15px; text-align:center;">
		<a class="btn btn-success" style="width:200px; font-size:14px; font-weight:bold;" href="javascript:void(0);" onclick="openDashboard();">📊 Mở Clash Dashboard</a>
		<a class="btn btn-info" style="width:200px; font-size:14px; font-weight:bold; margin-left:10px;" href="javascript:void(0);" onclick="generateClientLinks();">🔗 Lấy Link Client</a>
	</div>

	<div id="wnd_client_links" style="display:none; margin:10px;" class="alert alert-block">
		<button type="button" class="close" onclick="$j('#wnd_client_links').hide();">&times;</button>
		<h4>📋 Danh sách Link kết nối cho thiết bị con (clients.txt):</h4>
		<textarea id="client_links_area" style="width:98%; height:120px; font-family:monospace; font-size:12px;" readonly></textarea>
	</div>

	<!-- TABS: tach Tailscale ra 1 tab rieng, doc lap voi cac thiet lap sing-box goc -->
	<ul class="nav nav-tabs" style="margin:10px 10px 0 10px;">
		<li class="active"><a href="#tab_singbox" data-toggle="tab">⚙️ Sing-box</a></li>
		<li><a href="#tab_tailscale" data-toggle="tab">🌐 Tailscale</a></li>
	</ul>
	<div class="tab-content" style="padding:0 10px;">
	<div class="tab-pane active" id="tab_singbox">

	<!-- BẢNG 1: ĐIỀU KHIỂN CƠ BẢN -->
	<table width="100%" cellpadding="4" cellspacing="0" class="table">
	<tr><th colspan="2" style="background-color:#756c78;">Basic Control</th></tr>
	<tr id="singbox_conflict_warning_row" style="display:none;">
		<td colspan="2">
			<div class="alert alert-danger" style="margin:6px 0; background-color:#f2dede; border:1px solid #ebccd1; color:#a94442; padding:10px; border-radius:4px;">
				⚠️ <b>Xung đột:</b> Tailscale độc lập (standalone) hiện đang <b>BẬT</b>.
				Sing-box sẽ <b>từ chối khởi động</b> cho tới khi bạn tắt Tailscale độc lập trước
				(vào mục Tailscale riêng để tắt). Nút bên dưới đã bị khoá tạm thời.
			</div>
		</td>
	</tr>
	<tr>
		<th width="30%">Bật sing-box</th>
		<td>
			<div class="main_itoggle">
				<div id="singbox_enable_on_of">
					<input type="checkbox" id="singbox_enable_fake" <% nvram_match_x("", "singbox_enable", "1", "value=1 checked"); %><% nvram_match_x("", "singbox_enable", "0", "value=0"); %> />
				</div>
			</div>
			<div style="position: absolute; margin-left: -10000px;">
				<input type="radio" value="1" name="singbox_enable" id="singbox_enable_1" class="input" <% nvram_match_x("", "singbox_enable", "1", "checked"); %> /><#checkbox_Yes#>
				<input type="radio" value="0" name="singbox_enable" id="singbox_enable_0" class="input" <% nvram_match_x("", "singbox_enable", "0", "checked"); %> /><#checkbox_No#>
			</div>
		</td>
	</tr>
	<tr>
		<th>Chế độ hoạt động (Running Mode)</th>
		<td>
			<select name="singbox_mode" id="singbox_mode_select" class="input" onchange="onModeChange();">
				<option value="0" <% nvram_match_x("","singbox_mode","0","selected"); %>>Mode 1: Mixed Proxy (Port 7890 - Chỉnh thủ công từng máy)</option>
				<option value="1" <% nvram_match_x("","singbox_mode","1","selected"); %>>Mode 2: TProxy Mode (Toàn mạng LAN)</option>
				<option value="2" <% nvram_match_x("","singbox_mode","2","selected"); %>>Mode 3: Custom JSON (Dùng cấu hình bên dưới)</option>
			</select>
		</td>
	</tr>
	</table>

	<!-- BẢNG 2: QUẢN LÝ SUBSCRIPTION -->
	<table width="100%" cellpadding="4" cellspacing="0" class="table">
	<tr>
		<th colspan="2" style="background-color:#756c78;">
			Quản lý Link Subscription (Lưu trực tiếp trên /etc/storage)
			<input class="btn btn-mini btn-info" style="float:right;" type="button" value="⚡ Nạp Sub Mẫu Miễn Phí" onclick="loadDefaultPresetSubs();" />
			<input class="btn btn-mini btn-warning" style="float:right; margin-right:5px;" type="button" value="⚡ Cập nhật Sub Ngay" onclick="forceUpdateSub();" />
		</th>
	</tr>
	<tr>
		<th width="30%">Thêm Sub mới</th>
		<td>
			<div style="margin-bottom:6px;">
				<input type="text" id="input_sub_name" class="input" style="width:38%;" placeholder="Tên Nhóm">
				<input type="text" id="input_sub_url" class="input" style="width:54%;" placeholder="Link Subscription (https://...)">
			</div>
			<div>
				<input class="btn btn-info" type="button" value="🔍 Check Link" onclick="checkSubUrl();">
				<input class="btn btn-success" id="btn_add_sub" type="button" value="➕ Thêm Sub" onclick="addSubDirect();">
				<span id="sub_url_status" style="margin-left:8px;"></span>
			</div>
		</td>
	</tr>
	<tr>
		<td colspan="2">
			<table class="table table-bordered table-striped" style="margin-bottom:0;">
				<thead>
					<tr style="background-color:#5a525d; color:#fff;">
						<th style="text-align:center;">Trạng thái</th>
						<th>Tên Nhóm / Thư mục</th>
						<th>Link Subscription</th>
						<th style="text-align:center;">Hành động</th>
					</tr>
				</thead>
				<tbody id="sub_list_tbody">
				</tbody>
			</table>
		</td>
	</tr>
	<tr>
		<th>Tự động cập nhật Sub</th>
		<td>
			<div class="main_itoggle">
				<div id="singbox_auto_update_on_of">
					<input type="checkbox" id="singbox_auto_update_fake" <% nvram_match_x("", "singbox_auto_update", "1", "value=1 checked"); %><% nvram_match_x("", "singbox_auto_update", "0", "value=0"); %> />
				</div>
			</div>
			<div style="position: absolute; margin-left: -10000px;">
				<input type="radio" value="1" name="singbox_auto_update" id="singbox_auto_update_1" class="input" <% nvram_match_x("", "singbox_auto_update", "1", "checked"); %> /><#checkbox_Yes#>
				<input type="radio" value="0" name="singbox_auto_update" id="singbox_auto_update_0" class="input" <% nvram_match_x("", "singbox_auto_update", "0", "checked"); %> /><#checkbox_No#>
			</div>
			<span style="color:#888; margin-left:10px; display:inline-block; vertical-align:middle;">Tự động kiểm tra & gộp lại Subscription mỗi 3 ngày.</span>
		</td>
	</tr>
	</table>

	<!-- BẢNG 3: TỐI ƯU NÂNG CAO -->
	<table width="100%" cellpadding="4" cellspacing="0" class="table">
	<tr><th colspan="2" style="background-color:#756c78;">Optimization & Advanced Settings</th></tr>
	<tr id="singbox_dns_mode_row">
		<th width="30%">Chế độ DNS (DNS Mode)</th>
		<td>
			<select name="singbox_dns_mode" id="singbox_dns_mode_select" class="input" onchange="updateUiVisibility();">
				<option value="0" <% nvram_match_x("","singbox_dns_mode","0","selected"); %>>Direct (Khong ma hoa, khong fake-ip)</option>
				<option value="1" <% nvram_match_x("","singbox_dns_mode","1","selected"); %>>FakeIP Cổng 5353 (Hỗ trợ TProxy & Chống rò rỉ DNS)</option>
				<option value="2" <% nvram_match_x("","singbox_dns_mode","2","selected"); %>>DoH (Cloudflare / Google Secure DNS)</option>
			</select>
		</td>
	</tr>
	<tr id="singbox_bypass_vn_row">
		<th>Bypass IP/Tên miền VN</th>
		<td>
			<div class="main_itoggle">
				<div id="singbox_bypass_vn_on_of">
					<input type="checkbox" id="singbox_bypass_vn_fake" <% nvram_match_x("", "singbox_bypass_vn", "1", "value=1 checked"); %><% nvram_match_x("", "singbox_bypass_vn", "0", "value=0"); %> />
				</div>
			</div>
			<div style="position: absolute; margin-left: -10000px;">
				<input type="radio" value="1" name="singbox_bypass_vn" id="singbox_bypass_vn_1" class="input" <% nvram_match_x("", "singbox_bypass_vn", "1", "checked"); %> /><#checkbox_Yes#>
				<input type="radio" value="0" name="singbox_bypass_vn" id="singbox_bypass_vn_0" class="input" <% nvram_match_x("", "singbox_bypass_vn", "0", "checked"); %> /><#checkbox_No#>
			</div>
			<span style="color:#888; margin-left:10px; display:inline-block; vertical-align:middle;">Bật để IP/Web Việt Nam đi thẳng (không qua VPN) giúp tối ưu tốc độ.</span>
		</td>
	</tr>
	<tr id="singbox_adblock_row">
		<th>Chặn quảng cáo (AdBlock)</th>
		<td>
			<div class="main_itoggle">
				<div id="singbox_adblock_on_of">
					<input type="checkbox" id="singbox_adblock_fake" <% nvram_match_x("", "singbox_adblock", "1", "value=1 checked"); %><% nvram_match_x("", "singbox_adblock", "0", "value=0"); %> />
				</div>
			</div>
			<div style="position: absolute; margin-left: -10000px;">
				<input type="radio" value="1" name="singbox_adblock" id="singbox_adblock_1" class="input" <% nvram_match_x("", "singbox_adblock", "1", "checked"); %> /><#checkbox_Yes#>
				<input type="radio" value="0" name="singbox_adblock" id="singbox_adblock_0" class="input" <% nvram_match_x("", "singbox_adblock", "0", "checked"); %> /><#checkbox_No#>
			</div>
		</td>
	</tr>
	<tr>
		<th>Giới hạn RAM (Go Runtime)</th>
		<td>
			<select name="singbox_mem_limit" class="input">
				<option value="64MiB" <% nvram_match_x("","singbox_mem_limit","64MiB","selected"); %>>64 MB</option>
				<option value="128MiB" <% nvram_match_x("","singbox_mem_limit","128MiB","selected"); %>>128 MB</option>
				<option value="192MiB" <% nvram_match_x("","singbox_mem_limit","192MiB","selected"); %>>192 MB</option>
				<option value="256MiB" <% nvram_match_x("","singbox_mem_limit","256MiB","selected"); %>>256 MB</option>
			</select>
		</td>
	</tr>
	<tr id="singbox_dns_redirect_row">
		<th>Chuyển hướng DNS (53 -> 5353)</th>
		<td>
			<div class="main_itoggle">
				<div id="singbox_dns_redirect_on_of">
					<input type="checkbox" id="singbox_dns_redirect_fake" <% nvram_match_x("", "singbox_dns_redirect", "1", "value=1 checked"); %><% nvram_match_x("", "singbox_dns_redirect", "0", "value=0"); %> />
				</div>
			</div>
			<div style="position: absolute; margin-left: -10000px;">
				<input type="radio" value="1" name="singbox_dns_redirect" id="singbox_dns_redirect_1" class="input" <% nvram_match_x("", "singbox_dns_redirect", "1", "checked"); %> /><#checkbox_Yes#>
				<input type="radio" value="0" name="singbox_dns_redirect" id="singbox_dns_redirect_0" class="input" <% nvram_match_x("", "singbox_dns_redirect", "0", "checked"); %> /><#checkbox_No#>
			</div>
			<span id="dns_redirect_hint" style="display:inline-block; vertical-align:middle;"></span>
		</td>
	</tr>
	</table>

	<!-- BẢNG 4: RAW CONFIG JSON -->
	<table width="100%" cellpadding="4" cellspacing="0" class="table" style="margin:0 10px; width:calc(100% - 20px);">
	<tr><th colspan="2" style="background-color:#756c78;">
		Configuration (raw JSON - Dùng cho Mode 3)
		<input class="btn btn-mini" style="float:right;" type="button" value="Show/Hide" onclick="toggleConfig();" />
	</th></tr>
	<tr id="singbox_config_row" style="display:none;">
		<td>
			<span style="color:#888;">Paste your full sing-box config.json here (inbounds/outbounds/route/dns). Invalid JSON will fail to start - check the Run Log tab after Apply.</span><br>
			<textarea name="scripts.singbox.conf" id="singbox_config" class="input" style="width:100%; height:400px; font-family:'Courier New',monospace; font-size:12px;"><% nvram_dump_x("scripts.singbox.conf",""); %></textarea>
		</td>
	</tr>
	</table>

	</div>
	<!-- /tab_singbox -->

	<div class="tab-pane" id="tab_tailscale">

	<div id="singbox_ts_disabled_warning" class="alert alert-warning" style="display:none; margin:10px 0;">
		⚠️ <b>Cần Bật sing-box ở tab "⚙️ Sing-box" và bấm Apply trước</b>, sau đó mới quay lại đây chỉnh Tailscale. Các ô bên dưới đang bị khoá.
	</div>

	<!-- BẢNG 3.5: TAILSCALE NATIVE ENDPOINT (chạy trong chính tiến trình sing-box) -->
	<table width="100%" cellpadding="4" cellspacing="0" class="table" id="singbox_ts_table">
	<tr><th colspan="2" style="background-color:#756c78;">Tailscale (Native Endpoint - chạy trong sing-box)</th></tr>
	<tr>
		<td colspan="2">
			<div class="alert alert-info" style="margin:6px 0;">
				Tailscale chạy trực tiếp bên trong tiến trình sing-box (yêu cầu sing-box &ge; 1.12.0), <b>không</b> tạo interface <code>tailscale0</code> riêng ở tầng kernel, tránh xung đột routing/interface với TPROXY.
				<b>Không bật đồng thời</b> với ứng dụng Tailscale độc lập (mục Tailscale riêng ở menu VPN) - chỉ nên dùng MỘT trong hai.
			</div>
		</td>
	</tr>
	<tr>
		<th width="30%">Bật Tailscale (Native)</th>
		<td>
			<div class="main_itoggle">
				<div id="singbox_ts_enable_on_of">
					<input type="checkbox" id="singbox_ts_enable_fake" <% nvram_match_x("", "singbox_ts_enable", "1", "value=1 checked"); %><% nvram_match_x("", "singbox_ts_enable", "0", "value=0"); %> />
				</div>
			</div>
			<div style="position: absolute; margin-left: -10000px;">
				<input type="radio" value="1" name="singbox_ts_enable" id="singbox_ts_enable_1" class="input" <% nvram_match_x("", "singbox_ts_enable", "1", "checked"); %> /><#checkbox_Yes#>
				<input type="radio" value="0" name="singbox_ts_enable" id="singbox_ts_enable_0" class="input" <% nvram_match_x("", "singbox_ts_enable", "0", "checked"); %> /><#checkbox_No#>
			</div>
		</td>
	</tr>
	<tr>
		<th>Auth Key <span style="color:#888; font-weight:normal;">(tùy chọn)</span></th>
		<td>
			<input type="password" name="singbox_ts_authkey" id="singbox_ts_authkey" class="input" style="width:60%;" maxlength="128" autocomplete="off" value="<% nvram_get_x("", "singbox_ts_authkey"); %>" placeholder="Để trống nếu muốn đăng nhập qua Link (khuyên dùng)" />
			<span style="color:#888; margin-left:8px;">
				Chỉ cần điền nếu muốn tự động hoá (tạo tại
				<a href="https://login.tailscale.com/admin/settings/keys" target="_blank">login.tailscale.com/admin/settings/keys</a>).
			</span>
			<div style="margin-top:8px;">
				<input class="btn btn-info" type="button" value="🔗 Lấy Link Đăng Nhập" onclick="fetchTsLoginUrl();" />
				<span id="ts_login_url_status" style="margin-left:8px;"></span>
			</div>
			<div id="ts_login_url_box" style="display:none; margin-top:8px;">
				<a id="ts_login_url_link" href="#" target="_blank" style="font-family:monospace;"></a>
			</div>
		</td>
	</tr>
	<tr>
		<th>Nhận Route quảng bá (Accept Routes)</th>
		<td>
			<div class="main_itoggle">
				<div id="singbox_ts_accept_routes_on_of">
					<input type="checkbox" id="singbox_ts_accept_routes_fake" <% nvram_match_x("", "singbox_ts_accept_routes", "1", "value=1 checked"); %><% nvram_match_x("", "singbox_ts_accept_routes", "0", "value=0"); %> />
				</div>
			</div>
			<div style="position: absolute; margin-left: -10000px;">
				<input type="radio" value="1" name="singbox_ts_accept_routes" id="singbox_ts_accept_routes_1" class="input" <% nvram_match_x("", "singbox_ts_accept_routes", "1", "checked"); %> /><#checkbox_Yes#>
				<input type="radio" value="0" name="singbox_ts_accept_routes" id="singbox_ts_accept_routes_0" class="input" <% nvram_match_x("", "singbox_ts_accept_routes", "0", "checked"); %> /><#checkbox_No#>
			</div>
			<span style="color:#888; margin-left:10px;">Bật nếu muốn nhận subnet route được quảng bá từ các node khác trong tailnet.</span>
		</td>
	</tr>
	<tr>
		<th>Hostname <span style="color:#888; font-weight:normal;">(tùy chọn)</span></th>
		<td>
			<input type="text" name="singbox_ts_hostname" class="input" style="width:40%;" maxlength="63" value="<% nvram_get_x("", "singbox_ts_hostname"); %>" placeholder="newifi3-router" />
			<span style="color:#888; margin-left:8px;">Tên hiển thị của node này trên tailnet. Để trống = dùng hostname hệ thống.</span>
		</td>
	</tr>
	<tr>
		<th>Control URL <span style="color:#888; font-weight:normal;">(tùy chọn)</span></th>
		<td>
			<input type="text" name="singbox_ts_control_url" class="input" style="width:60%;" maxlength="200" value="<% nvram_get_x("", "singbox_ts_control_url"); %>" placeholder="https://controlplane.tailscale.com (để trống nếu không tự host Headscale)" />
			<span style="color:#888; margin-left:8px;">Chỉ điền nếu bạn tự host coordination server riêng (VD: Headscale).</span>
		</td>
	</tr>
	<tr>
		<th>Ephemeral Node</th>
		<td>
			<div class="main_itoggle">
				<div id="singbox_ts_ephemeral_on_of">
					<input type="checkbox" id="singbox_ts_ephemeral_fake" <% nvram_match_x("", "singbox_ts_ephemeral", "1", "value=1 checked"); %><% nvram_match_x("", "singbox_ts_ephemeral", "0", "value=0"); %> />
				</div>
			</div>
			<div style="position: absolute; margin-left: -10000px;">
				<input type="radio" value="1" name="singbox_ts_ephemeral" id="singbox_ts_ephemeral_1" class="input" <% nvram_match_x("", "singbox_ts_ephemeral", "1", "checked"); %> /><#checkbox_Yes#>
				<input type="radio" value="0" name="singbox_ts_ephemeral" id="singbox_ts_ephemeral_0" class="input" <% nvram_match_x("", "singbox_ts_ephemeral", "0", "checked"); %> /><#checkbox_No#>
			</div>
			<span style="color:#888; margin-left:10px;">Node tự động bị xoá khỏi tailnet khi offline (phù hợp khi test, không nên bật cho router chạy lâu dài).</span>
		</td>
	</tr>
	<tr>
		<th>Exit Node <span style="color:#888; font-weight:normal;">(tùy chọn)</span></th>
		<td>
			<input type="text" name="singbox_ts_exit_node" class="input" style="width:40%;" maxlength="128" value="<% nvram_get_x("", "singbox_ts_exit_node"); %>" placeholder="tên-node hoặc IP 100.x.x.x" />
			<span style="color:#888; margin-left:8px;">Route toàn bộ traffic của router này qua 1 node khác trong tailnet (node đó phải tự bật "Advertise as Exit Node").</span>
		</td>
	</tr>
	<tr>
		<th>Exit Node - Cho phép truy cập LAN</th>
		<td>
			<div class="main_itoggle">
				<div id="singbox_ts_exit_node_allow_lan_on_of">
					<input type="checkbox" id="singbox_ts_exit_node_allow_lan_fake" <% nvram_match_x("", "singbox_ts_exit_node_allow_lan", "1", "value=1 checked"); %><% nvram_match_x("", "singbox_ts_exit_node_allow_lan", "0", "value=0"); %> />
				</div>
			</div>
			<div style="position: absolute; margin-left: -10000px;">
				<input type="radio" value="1" name="singbox_ts_exit_node_allow_lan" id="singbox_ts_exit_node_allow_lan_1" class="input" <% nvram_match_x("", "singbox_ts_exit_node_allow_lan", "1", "checked"); %> /><#checkbox_Yes#>
				<input type="radio" value="0" name="singbox_ts_exit_node_allow_lan" id="singbox_ts_exit_node_allow_lan_0" class="input" <% nvram_match_x("", "singbox_ts_exit_node_allow_lan", "0", "checked"); %> /><#checkbox_No#>
			</div>
			<span style="color:#888; margin-left:10px;">Chỉ có tác dụng khi đã điền Exit Node phía trên. Lưu ý: nếu Exit Node đó chưa quảng bá route LAN tương ứng, mạng LAN cục bộ vẫn không truy cập được dù bật tùy chọn này.</span>
		</td>
	</tr>
	<tr>
		<th>Advertise Routes <span style="color:#888; font-weight:normal;">(tùy chọn)</span></th>
		<td>
			<input type="text" name="singbox_ts_advertise_routes" class="input" style="width:60%;" maxlength="256" value="<% nvram_get_x("", "singbox_ts_advertise_routes"); %>" placeholder="192.168.2.0/24, 192.168.3.0/24" />
			<span style="color:#888; margin-left:8px;">Quảng bá subnet LAN của router này cho các node khác trong tailnet dùng (Subnet Router). Nhiều subnet cách nhau bằng dấu phẩy. Cần vào Tailscale Admin Console duyệt (approve) route sau khi Apply.</span>
		</td>
	</tr>
	<tr>
		<th>Advertise as Exit Node</th>
		<td>
			<div class="main_itoggle">
				<div id="singbox_ts_advertise_exit_node_on_of">
					<input type="checkbox" id="singbox_ts_advertise_exit_node_fake" <% nvram_match_x("", "singbox_ts_advertise_exit_node", "1", "value=1 checked"); %><% nvram_match_x("", "singbox_ts_advertise_exit_node", "0", "value=0"); %> />
				</div>
			</div>
			<div style="position: absolute; margin-left: -10000px;">
				<input type="radio" value="1" name="singbox_ts_advertise_exit_node" id="singbox_ts_advertise_exit_node_1" class="input" <% nvram_match_x("", "singbox_ts_advertise_exit_node", "1", "checked"); %> /><#checkbox_Yes#>
				<input type="radio" value="0" name="singbox_ts_advertise_exit_node" id="singbox_ts_advertise_exit_node_0" class="input" <% nvram_match_x("", "singbox_ts_advertise_exit_node", "0", "checked"); %> /><#checkbox_No#>
			</div>
			<span style="color:#888; margin-left:10px;">Cho phép các node khác trong tailnet chọn router này làm Exit Node (route toàn bộ traffic của họ qua đây). Cần duyệt (approve) trong Tailscale Admin Console sau khi Apply.</span>
		</td>
	</tr>
	<tr>
		<th>Advertise Tags <span style="color:#888; font-weight:normal;">(tùy chọn)</span></th>
		<td>
			<input type="text" name="singbox_ts_advertise_tags" class="input" style="width:50%;" maxlength="256" value="<% nvram_get_x("", "singbox_ts_advertise_tags"); %>" placeholder="tag:router, tag:server" />
			<span style="color:#888; margin-left:8px;">Gắn tag ACL cho node này (phải được định nghĩa trước trong ACL policy trên Tailscale Admin Console). Nhiều tag cách nhau bằng dấu phẩy.</span>
		</td>
	</tr>
	<tr>
		<th>Tailscale SSH Server</th>
		<td>
			<div class="main_itoggle">
				<div id="singbox_ts_ssh_server_on_of">
					<input type="checkbox" id="singbox_ts_ssh_server_fake" <% nvram_match_x("", "singbox_ts_ssh_server", "1", "value=1 checked"); %><% nvram_match_x("", "singbox_ts_ssh_server", "0", "value=0"); %> />
				</div>
			</div>
			<div style="position: absolute; margin-left: -10000px;">
				<input type="radio" value="1" name="singbox_ts_ssh_server" id="singbox_ts_ssh_server_1" class="input" <% nvram_match_x("", "singbox_ts_ssh_server", "1", "checked"); %> /><#checkbox_Yes#>
				<input type="radio" value="0" name="singbox_ts_ssh_server" id="singbox_ts_ssh_server_0" class="input" <% nvram_match_x("", "singbox_ts_ssh_server", "0", "checked"); %> /><#checkbox_No#>
			</div>
			<span style="color:#888; margin-left:10px;">Cho phép SSH vào router qua Tailscale (kiểm soát quyền qua SSH ACL trên Admin Console), độc lập với SSH thường của Padavan.</span>
		</td>
	</tr>
	</table>

	</div>
	<!-- /tab_tailscale -->

	</div>
	<!-- /tab-content -->

	<!-- BẢNG 5: BUTTON APPLY -->
	<div style="margin:10px;">
		<center><input class="btn btn-primary" style="width:219px" type="button" value="<#CTL_apply#>" onclick="applyRule()" /></center>
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
