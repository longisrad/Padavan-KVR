<!DOCTYPE html>
<html>
<head>
<title><#Web_Title#> - CAKE SQM</title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
<meta http-equiv="Pragma" content="no-cache">
<meta http-equiv="Expires" content="-1">

<link rel="shortcut icon" href="images/favicon.ico">
<link rel="icon" href="images/favicon.png">
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
<style>
.cake_pre{background:#f7f7f7;color:#333;border:1px solid #ccc;border-radius:4px;padding:8px;margin:0;font-family:'Courier New',monospace;font-size:12px;white-space:pre-wrap;word-break:break-all;max-height:360px;overflow:auto}
.cake_sub th{background-color:#5a525d;color:#fff;text-align:center}
.cake_sum td,.cake_sum th{vertical-align:middle}
.cake_tool td{vertical-align:middle}
</style>
<script>
var $j = jQuery.noConflict();
<% login_state_hook(); %>

// cấu hình đang lưu trong nvram (dùng cho bảng tổng hợp)
var cfg = {
	enable: "<% nvram_get_x("", "cake_enable"); %>",
	down: "<% nvram_get_x("", "cake_down_bw"); %>",
	up: "<% nvram_get_x("", "cake_up_bw"); %>",
	flow: "<% nvram_get_x("", "cake_flow_mode"); %>",
	ds: "<% nvram_get_x("", "cake_diffserv"); %>",
	rtt: "<% nvram_get_x("", "cake_rtt"); %>",
	oh: "<% nvram_get_x("", "cake_overhead"); %>",
	ack: "<% nvram_get_x("", "cake_ack_filter"); %>",
	nat: "<% nvram_get_x("", "cake_nat"); %>",
	wash: "<% nvram_get_x("", "cake_wash"); %>",
	custom: "<% nvram_get_x("", "cake_custom"); %>"
};

$j(document).ready(function(){
	init_itoggle('cake_enable');
	init_itoggle('cake_nat');
	init_itoggle('cake_wash');
	updateUi();
	// itoggle bind click vao div wrapper; doi 50ms de plugin cap nhat xong checkbox that
	$j('#cake_enable_on_of').on('click', function(){ setTimeout(updateUi, 50); });
	// bootstrap 2 phat 'shown', bootstrap 3 phat 'shown.bs.tab'
	$j('a[data-toggle="tab"]').on('shown shown.bs.tab', function(e){
		if ($j(e.target).attr('href') == '#tab_sum') refresh_status();
	});
});

function sel(n, v){
	var e = document.form[n];
	for (var i = 0; i < e.options.length; i++){
		if (e.options[i].value == v){ e.selectedIndex = i; return; }
	}
}

function initial(){
	show_banner(1);
	show_menu(7, 37, 1);
	show_footer();

	document.form.cake_down_bw.value = cfg.down;
	document.form.cake_up_bw.value   = cfg.up;
	document.form.cake_custom.value  = cfg.custom;
	sel("cake_flow_mode",  cfg.flow);
	sel("cake_diffserv",   cfg.ds);
	sel("cake_rtt",        cfg.rtt);
	sel("cake_overhead",   cfg.oh);
	sel("cake_ack_filter", cfg.ack);

	updateUi();
	setTimeout(updateUi, 100);
	setTimeout(updateUi, 500);

	render_cfg();
	refresh_status();
}

function cake_is_on(){ return $j('#cake_enable_fake').is(':checked'); }

// Tắt CAKE: ẩn các bảng cấu hình (giá trị vẫn được giữ nguyên)
function updateUi(){
	document.getElementById("cake_settings").style.display = cake_is_on() ? "" : "none";
}

/* ---------- AJAX ---------- */
function post_cgi(body, cb){
	var x = new XMLHttpRequest();
	x.open("POST", "/apply.cgi", true);
	x.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
	x.onreadystatechange = function(){
		if (x.readyState == 4) cb(x.status == 200 ? x.responseText : null);
	};
	x.send(body);
}

function esc(s){ return String(s).replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;"); }
function lab(cls, t){ return '<span class="label label-'+cls+'">'+esc(t)+'</span>'; }
function fmtBytes(n){
	n = Number(n); if (isNaN(n)) return "-";
	var u = ["B","KB","MB","GB","TB"], i = 0;
	while (n >= 1024 && i < u.length-1){ n /= 1024; i++; }
	return (i ? n.toFixed(1) : n) + " " + u[i];
}
function rateTxt(v){ return (v && Number(v) > 0) ? v + " Mbit" : "không giới hạn"; }

/* ---------- Bảng cấu hình đang lưu ---------- */
function render_cfg(){
	var rows = [
		["Trạng thái", cfg.enable == "1" ? lab("success","BẬT") : lab("default","TẮT")],
		["Tải xuống", rateTxt(cfg.down)],
		["Tải lên", rateTxt(cfg.up)],
		["Chia luồng", esc(cfg.flow || "auto")],
		["DSCP", esc(cfg.ds || "-")],
		["RTT", esc(cfg.rtt || "-")],
		["Overhead", esc(cfg.oh || "-")],
		["ACK filter", esc(cfg.ack || "none")],
		["NAT", cfg.nat == "1" ? "Bật" : "Tắt"],
		["Wash", cfg.wash == "1" ? "Bật" : "Tắt"],
		["Tuỳ chọn thêm", esc(cfg.custom || "-")]
	];
	var h = "";
	for (var i = 0; i < rows.length; i += 2){
		h += "<tr><th width='20%'>"+rows[i][0]+"</th><td width='30%'>"+rows[i][1]+"</td>";
		if (rows[i+1]) h += "<th width='20%'>"+rows[i+1][0]+"</th><td width='30%'>"+rows[i+1][1]+"</td>";
		else h += "<th></th><td></td>";
		h += "</tr>";
	}
	document.getElementById("cfg_tbody").innerHTML = h;
}

/* ---------- Phân tích đầu ra `cake.sh status` ---------- */
function parseDir(lines){
	var t = lines.join("\n"), d = {};
	var q = t.match(/qdisc cake[^\n]*/);
	d.active = !!q;
	if (!q) return d;
	q = q[0];
	var tk = q.split(/\s+/), pick = function(re){ for (var i = 0; i < tk.length; i++) if (re.test(tk[i])) return tk[i]; return "-"; };
	d.bw = (q.match(/bandwidth (\S+)/) || [])[1] || "không giới hạn";
	d.ds = pick(/^(besteffort|diffserv\d)$/);
	d.flow = pick(/^(dual-srchost|dual-dsthost|triple-isolate|flowblind|srchost|dsthost|hosts|flows)$/);
	d.nat = pick(/^(nat|nonat)$/);
	d.rtt = (q.match(/rtt (\S+)/) || [])[1] || "-";
	d.extra = tk.filter(function(w){ return /^(ingress|wash|ack-filter|ack-filter-aggressive)$/.test(w); }).join(" ");
	var m = t.match(/Sent (\d+) bytes (\d+) pkt \(dropped (\d+), overlimits (\d+)/);
	if (m){ d.bytes = m[1]; d.pkts = m[2]; d.drops = m[3]; d.over = m[4]; }
	m = t.match(/backlog (\S+) (\d+)p/); if (m){ d.backlog = m[1]; d.backp = m[2]; }
	m = t.match(/capacity estimate: (\S+)/); if (m) d.cap = m[1];
	m = t.match(/memory used: (\S+) of (\S+)/); if (m){ d.mem = m[1] + " / " + m[2]; }
	// bảng tin
	var ls = t.split("\n"), ti = -1, i;
	for (i = 0; i < ls.length; i++) if (/^\s+thresh\s/.test(ls[i])){ ti = i; break; }
	if (ti > 0){
		var names = ls[ti-1].replace(/^\s+|\s+$/g, "").split(/\s{2,}/);
		var tin = {};
		for (i = ti; i < ls.length; i++){
			var mm = ls[i].match(/^\s+([a-z_]+)\s+(.+?)\s*$/);
			if (!mm) break;
			tin[mm[1]] = mm[2].split(/\s+/);
		}
		d.tin = tin; d.tinNames = names;
	}
	return d;
}

function renderDir(d, title, dev){
	var h = "<tr><th colspan='2' style='background-color:#756c78;'>"+title+" <small style='color:#ddd;'>("+esc(dev)+")</small></th></tr>";
	if (!d.active)
		return h + "<tr><td colspan='2'>" + lab("important","CAKE chưa chạy trên cổng này") + "</td></tr>";
	var cells = [
		["Giới hạn", esc(d.bw)], ["Phân loại", esc(d.ds)], ["Chia luồng", esc(d.flow)],
		["NAT", esc(d.nat)], ["RTT", esc(d.rtt)], ["Tuỳ chọn", esc(d.extra || "-")],
		["Đã xử lý", fmtBytes(d.bytes) + " / " + (d.pkts || 0) + " gói"],
		["Gói bị loại", (d.drops || 0) + " (overlimits " + (d.over || 0) + ")"],
		["Hàng đợi", esc(d.backlog || "0b") + " / " + (d.backp || 0) + " gói"],
		["Ước lượng băng thông", esc(d.cap || "-")],
		["Bộ nhớ", esc(d.mem || "-")]
	];
	var inner = "<table class='table table-bordered table-striped cake_sum' style='margin-bottom:0;'>";
	for (var i = 0; i < cells.length; i += 2){
		inner += "<tr><th width='18%'>"+cells[i][0]+"</th><td width='32%'>"+cells[i][1]+"</td>";
		inner += cells[i+1] ? "<th width='18%'>"+cells[i+1][0]+"</th><td width='32%'>"+cells[i+1][1]+"</td>" : "<th></th><td></td>";
		inner += "</tr>";
	}
	inner += "</table>";
	if (d.tin){
		var keys = ["thresh","target","pk_delay","av_delay","sp_delay","pkts","bytes","drops","marks","ack_drop","sp_flows","bk_flows"];
		var n = 0, k;
		for (k in d.tin){ n = Math.max(n, d.tin[k].length); }
		inner += "<table class='table table-bordered table-striped cake_sub' style='margin:6px 0 0 0;'><thead><tr><th>Chỉ số</th>";
		for (i = 0; i < n; i++) inner += "<th>" + esc(d.tinNames[i] || ("Tin " + (i+1))) + "</th>";
		inner += "</tr></thead><tbody>";
		for (var j = 0; j < keys.length; j++){
			if (!d.tin[keys[j]]) continue;
			inner += "<tr><td><b>"+keys[j]+"</b></td>";
			for (i = 0; i < n; i++) inner += "<td style='text-align:center;'>" + esc(d.tin[keys[j]][i] || "-") + "</td>";
			inner += "</tr>";
		}
		inner += "</tbody></table>";
	}
	return h + "<tr><td colspan='2'>" + inner + "</td></tr>";
}

function render_status(txt){
	document.getElementById("cake_raw").textContent = txt;
	var lines = txt.split("\n"), head = "", hw = "", dirs = [], cur = null, m, i;
	for (i = 0; i < lines.length; i++){
		m = lines[i].match(/^--- (\S+) \((upload|download)\) ---/);
		if (m){ cur = {dev: m[1], kind: m[2], lines: []}; dirs.push(cur); continue; }
		if (cur) cur.lines.push(lines[i]);
		else if (/^enable=/.test(lines[i])) head = lines[i];
		else if (/^hw_nat:/.test(lines[i])) hw = lines[i];
	}
	var run = /daemon=chay/.test(head), on = /enable=1/.test(head);
	var wan = (head.match(/wan=(\S*)/) || [])[1] || "-";
	var h = "";
	h += "<tr><th width='18%'>Dịch vụ</th><td width='32%'>" + (on ? lab("success","Đã bật") : lab("default","Đang tắt")) + " " + (run ? lab("info","daemon chạy") : lab("warning","daemon dừng")) + "</td>";
	h += "<th width='18%'>Cổng WAN</th><td width='32%'>" + esc(wan) + "</td></tr>";
	h += "<tr><th>Offload</th><td colspan='3'>" + esc(hw.replace(/^hw_nat:\s*/, "") || "-") + "</td></tr>";
	document.getElementById("sum_head").innerHTML = h;
	var body = "";
	for (i = 0; i < dirs.length; i++)
		body += renderDir(parseDir(dirs[i].lines), dirs[i].kind == "upload" ? "⬆️ Tải lên (egress)" : "⬇️ Tải xuống (ingress qua ifb0)", dirs[i].dev);
	if (!dirs.length) body = "<tr><td>Chưa có dữ liệu trạng thái.</td></tr>";
	document.getElementById("sum_dirs").innerHTML = body;
}

function refresh_status(){
	var b = document.getElementById("sum_msg"); b.innerHTML = "Đang đọc trạng thái...";
	post_cgi("action_mode=%20GetCakeStatus%20", function(t){
		if (t === null){ b.innerHTML = lab("important", "Không đọc được trạng thái"); return; }
		b.innerHTML = "Cập nhật lúc " + (new Date()).toLocaleTimeString();
		render_status(t);
	});
}

/* ---------- Công cụ (chạy /usr/bin/cake.sh) ---------- */
var toolTimer = null;
function run_tool(tool){
	if (tool == "test" && !confirm("Lệnh này tạm dừng CAKE đang chạy để thử từng tuỳ chọn. Xong bạn bấm 'Khởi động lại CAKE'. Tiếp tục?")) return;
	var out = document.getElementById("tool_out"), st = document.getElementById("tool_msg");
	out.textContent = ""; st.innerHTML = "Đang chạy cake.sh " + tool + " ...";
	if (toolTimer) clearInterval(toolTimer);
	post_cgi("action_mode=%20CakeToolRun%20&cake_tool=" + encodeURIComponent(tool), function(){
		var tries = 0;
		toolTimer = setInterval(function(){
			tries++;
			post_cgi("action_mode=%20GetCakeToolOutput%20", function(t){
				if (t !== null){
					var done = t.indexOf("[xong]") >= 0;
					out.textContent = t.replace("[xong]", "");
					out.scrollTop = out.scrollHeight;
					if (done){ clearInterval(toolTimer); st.innerHTML = lab("success", "Hoàn tất"); if (tool == "restart") setTimeout(refresh_status, 1500); }
				}
				if (tries > 60){ clearInterval(toolTimer); st.innerHTML = lab("warning", "Quá thời gian chờ"); }
			});
		}, 1000);
	});
}

/* ---------- Áp dụng cấu hình ---------- */
function check_rate(o){
	if (o.value == "") o.value = "0";
	if (!/^[0-9]+(\.[0-9]+)?$/.test(o.value)){
		alert("Tốc độ phải là số (đơn vị Mbit), 0 = không giới hạn");
		o.focus();
		return false;
	}
	return true;
}

function applyRule(){
	if (!check_rate(document.form.cake_down_bw) || !check_rate(document.form.cake_up_bw))
		return;
	if (!/^[A-Za-z0-9 ._-]*$/.test(document.form.cake_custom.value)){
		alert("Tuỳ chọn thêm chỉ được chứa chữ, số, khoảng trắng, dấu chấm, gạch ngang, gạch dưới");
		document.form.cake_custom.focus();
		return;
	}
	showLoading();
	document.form.action_mode.value = " Apply ";
	document.form.action_script.value = "restart_cake";
	document.form.current_page.value = "/Advanced_cake.asp";
	document.form.next_page.value = "";
	document.form.submit();
}
</script>
</head>

<body onload="initial();" onunload="unload_body();">

<div class="wrapper">
	<div class="container-fluid" style="padding-right: 0px">
		<div class="row-fluid">
			<div class="span3"><center><div id="logo"></div></center></div>
			<div class="span9"><div id="TopBanner"></div></div>
		</div>
	</div>

	<div id="Loading" class="popup_bg"></div>

	<iframe name="hidden_frame" id="hidden_frame" src="" width="0" height="0" frameborder="0"></iframe>

	<form method="post" name="form" id="ruleForm" action="/start_apply.htm" target="hidden_frame">

	<input type="hidden" name="current_page" value="Advanced_cake.asp">
	<input type="hidden" name="next_page" value="">
	<input type="hidden" name="next_host" value="">
	<input type="hidden" name="sid_list" value="CakeConf;">
	<input type="hidden" name="group_id" value="">
	<input type="hidden" name="action_mode" value="">
	<input type="hidden" name="action_script" value="">

	<div class="container-fluid">
		<div class="row-fluid">
			<div class="span3">
				<div class="well sidebar-nav side_nav" style="padding: 0px;">
					<ul id="mainMenu" class="clearfix"></ul>
					<ul class="clearfix">
						<li><div id="subMenu" class="accordion"></div></li>
					</ul>
				</div>
			</div>

			<div class="span9">
				<div class="row-fluid">
					<div class="span12">
						<div class="box well grad_colour_dark_blue">
							<h2 class="box_head round_top">CAKE Smart Queue Management (SQM)</h2>
							<div class="round_bottom">
								<div class="row-fluid">
									<div id="tabMenu" class="submenuBlock"></div>

									<div class="alert alert-info" style="margin: 10px;">
										CAKE giảm bufferbloat: đặt tốc độ khoảng 90–95% tốc độ đường truyền thật. Đặt 0 để không giới hạn chiều đó (tải xuống = 0 thì không dùng ingress/IFB, đỡ tốn CPU).
									</div>

									<ul class="nav nav-tabs" style="margin:10px 10px 0 10px;">
										<li class="active"><a href="#tab_cfg" data-toggle="tab">⚙️ Cấu hình</a></li>
										<li><a href="#tab_sum" data-toggle="tab">📊 Tổng hợp</a></li>
										<li><a href="#tab_tools" data-toggle="tab">🛠️ Công cụ</a></li>
									</ul>
									<div class="tab-content" style="padding:0 10px;">

<!-- ================= TAB 1: CẤU HÌNH ================= -->
<div class="tab-pane active" id="tab_cfg">

<table width="100%" align="center" cellpadding="4" cellspacing="0" class="table">
<tr><th colspan="2" style="background-color:#756c78;">Basic Control</th></tr>
<tr>
<th width="50%">Bật CAKE SQM</th>
<td>
<div class="main_itoggle">
<div id="cake_enable_on_of">
<input type="checkbox" id="cake_enable_fake" <% nvram_match_x("", "cake_enable", "1", "value=1 checked"); %><% nvram_match_x("", "cake_enable", "0", "value=0"); %>>
</div>
</div>
<div style="position: absolute; margin-left: -10000px;">
<input type="radio" value="1" name="cake_enable" id="cake_enable_1" class="input" <% nvram_match_x("", "cake_enable", "1", "checked"); %> /><#checkbox_Yes#>
<input type="radio" value="0" name="cake_enable" id="cake_enable_0" class="input" <% nvram_match_x("", "cake_enable", "0", "checked"); %> /><#checkbox_No#>
</div>
</td>
</tr>
</table>

<div id="cake_settings">
<table width="100%" align="center" cellpadding="4" cellspacing="0" class="table">
<tr><th colspan="2" style="background-color:#756c78;">Giới hạn tốc độ</th></tr>
<tr>
<th width="50%">Tốc độ tải xuống (Mbit, 0 = không giới hạn)</th>
<td><input type="text" name="cake_down_bw" class="input" maxlength="8" size="10" value=""></td>
</tr>
<tr>
<th>Tốc độ tải lên (Mbit, 0 = không giới hạn)</th>
<td><input type="text" name="cake_up_bw" class="input" maxlength="8" size="10" value=""></td>
</tr>
</table>

<table width="100%" align="center" cellpadding="4" cellspacing="0" class="table">
<tr><th colspan="2" style="background-color:#756c78;">Phân loại &amp; độ trễ</th></tr>
<tr><th>Chế độ chia luồng</th><td><select name="cake_flow_mode" class="input"><option value="auto">auto (dual-srchost tải lên / dual-dsthost tải xuống, nếu bật NAT)</option><option value="triple-isolate">triple-isolate</option><option value="dual-srchost">dual-srchost</option><option value="dual-dsthost">dual-dsthost</option><option value="hosts">hosts</option><option value="srchost">srchost</option><option value="dsthost">dsthost</option><option value="flows">flows</option><option value="flowblind">flowblind</option></select></td></tr>
<tr><th>Phân loại DSCP</th><td><select name="cake_diffserv" class="input"><option value="besteffort">besteffort</option><option value="diffserv3">diffserv3</option><option value="diffserv4">diffserv4</option><option value="diffserv8">diffserv8</option></select></td></tr>
<tr><th>RTT</th><td><select name="cake_rtt" class="input"><option value="datacentre">datacentre</option><option value="lan">lan</option><option value="metro">metro</option><option value="regional">regional</option><option value="internet">internet</option><option value="oceanic">oceanic</option><option value="satellite">satellite</option></select></td></tr>
<tr><th>Overhead (loại đường truyền)</th><td><select name="cake_overhead" class="input"><option value="raw">raw</option><option value="ethernet">ethernet</option><option value="ether-vlan">ether-vlan</option><option value="pppoe-ptm">pppoe-ptm</option><option value="bridged-ptm">bridged-ptm</option><option value="docsis">docsis</option><option value="conservative">conservative</option></select></td></tr>
</table>

<table width="100%" align="center" cellpadding="4" cellspacing="0" class="table">
<tr><th colspan="2" style="background-color:#756c78;">Optimization &amp; Advanced Settings</th></tr>
<tr><th>ACK filter (chiều tải lên)</th><td><select name="cake_ack_filter" class="input"><option value="none">Tắt</option><option value="ack-filter">ack-filter</option><option value="ack-filter-aggressive">ack-filter-aggressive</option></select></td></tr>
<tr>
<th width="50%">NAT (nên bật khi router làm NAT)</th>
<td>
<div class="main_itoggle">
<div id="cake_nat_on_of">
<input type="checkbox" id="cake_nat_fake" <% nvram_match_x("", "cake_nat", "1", "value=1 checked"); %><% nvram_match_x("", "cake_nat", "0", "value=0"); %>>
</div>
</div>
<div style="position: absolute; margin-left: -10000px;">
<input type="radio" value="1" name="cake_nat" id="cake_nat_1" class="input" <% nvram_match_x("", "cake_nat", "1", "checked"); %> /><#checkbox_Yes#>
<input type="radio" value="0" name="cake_nat" id="cake_nat_0" class="input" <% nvram_match_x("", "cake_nat", "0", "checked"); %> /><#checkbox_No#>
</div>
</td>
</tr>
<tr>
<th width="50%">Wash (xoá DSCP gói tải xuống)</th>
<td>
<div class="main_itoggle">
<div id="cake_wash_on_of">
<input type="checkbox" id="cake_wash_fake" <% nvram_match_x("", "cake_wash", "1", "value=1 checked"); %><% nvram_match_x("", "cake_wash", "0", "value=0"); %>>
</div>
</div>
<div style="position: absolute; margin-left: -10000px;">
<input type="radio" value="1" name="cake_wash" id="cake_wash_1" class="input" <% nvram_match_x("", "cake_wash", "1", "checked"); %> /><#checkbox_Yes#>
<input type="radio" value="0" name="cake_wash" id="cake_wash_0" class="input" <% nvram_match_x("", "cake_wash", "0", "checked"); %> /><#checkbox_No#>
</div>
</td>
</tr>
<tr>
<th>Tuỳ chọn thêm cho tc (nâng cao)</th>
<td><input type="text" name="cake_custom" class="input" maxlength="64" size="30" value=""><br><small style="color:#888;">WAN quay số PPPoE: thử thêm <code>overhead 46</code> (ước tính, kiểm tra lại bằng bufferbloat test).</small></td>
</tr>
</table>
</div>

<div style="margin:10px;">
<center><input class="btn btn-primary" style="width:219px" type="button" value="<#CTL_apply#>" onclick="applyRule()" /></center>
</div>

</div>
<!-- /tab_cfg -->

<!-- ================= TAB 2: TỔNG HỢP ================= -->
<div class="tab-pane" id="tab_sum">

<table width="100%" cellpadding="4" cellspacing="0" class="table cake_sum">
<tr><th colspan="4" style="background-color:#756c78;">Cấu hình đang lưu</th></tr>
<tbody id="cfg_tbody"></tbody>
</table>

<table width="100%" cellpadding="4" cellspacing="0" class="table cake_sum">
<tr><th colspan="4" style="background-color:#756c78;">
Trạng thái đang chạy
<input class="btn btn-mini btn-info" style="float:right;" type="button" value="🔄 Làm mới" onclick="refresh_status();" />
</th></tr>
<tbody id="sum_head"></tbody>
<tr><td colspan="4"><small id="sum_msg" style="color:#888;"></small></td></tr>
</table>

<table width="100%" cellpadding="4" cellspacing="0" class="table">
<tbody id="sum_dirs"></tbody>
</table>

<table width="100%" cellpadding="4" cellspacing="0" class="table">
<tr><th style="background-color:#756c78;">
Dữ liệu thô (cake.sh status)
<input class="btn btn-mini" style="float:right;" type="button" value="Show/Hide" onclick="$j('#raw_row').toggle();" />
</th></tr>
<tr id="raw_row" style="display:none;"><td><pre id="cake_raw" class="cake_pre"></pre></td></tr>
</table>

</div>
<!-- /tab_sum -->

<!-- ================= TAB 3: CÔNG CỤ ================= -->
<div class="tab-pane" id="tab_tools">

<div class="alert" style="margin:10px 0;">
Nếu <b>Hardware NAT / Software offload</b> đang bật thì gói được offload sẽ <b>bỏ qua CAKE</b>. Chạy "Kiểm tra offload" khi đang tải file hoặc speedtest.
</div>

<table width="100%" cellpadding="4" cellspacing="0" class="table cake_tool">
<tr><th colspan="3" style="background-color:#756c78;">Bộ công cụ cake.sh</th></tr>
<tr>
	<td width="26%"><b>📋 Trạng thái nhanh</b></td>
	<td>In trạng thái dịch vụ, offload và thống kê tc của hai chiều (<code>cake.sh status</code>).</td>
	<td width="90" style="text-align:center;"><input class="btn btn-mini btn-primary" type="button" value="Chạy" onclick="run_tool('status')" /></td>
</tr>
<tr>
	<td><b>🔍 Kiểm tra offload</b></td>
	<td>Đo 5 giây: so số gói đi qua cổng WAN với số gói CAKE xử lý (<code>cake.sh check</code>). Chạy lúc đang tải.</td>
	<td style="text-align:center;"><input class="btn btn-mini btn-warning" type="button" value="Chạy" onclick="run_tool('check')" /></td>
</tr>
<tr>
	<td><b>🧪 Thử từng tuỳ chọn tc</b></td>
	<td>Thử từng tuỳ chọn CAKE trên cổng WAN để tìm tuỳ chọn kernel từ chối (<code>cake.sh test</code>). <b>Tạm dừng CAKE</b>, xong hãy khởi động lại.</td>
	<td style="text-align:center;"><input class="btn btn-mini btn-danger" type="button" value="Chạy" onclick="run_tool('test')" /></td>
</tr>
<tr>
	<td><b>🔄 Khởi động lại CAKE</b></td>
	<td>Dừng rồi chạy lại CAKE theo cấu hình đang lưu (<code>cake.sh restart</code>).</td>
	<td style="text-align:center;"><input class="btn btn-mini btn-success" type="button" value="Chạy" onclick="run_tool('restart')" /></td>
</tr>
</table>

<table width="100%" cellpadding="4" cellspacing="0" class="table">
<tr><th style="background-color:#756c78;">Kết quả <small id="tool_msg" style="margin-left:8px;"></small></th></tr>
<tr><td><pre id="tool_out" class="cake_pre" style="min-height:120px;"></pre></td></tr>
</table>

</div>
<!-- /tab_tools -->

									</div>
									<!-- /tab-content -->
								</div>
							</div>
						</div>
					</div>
				</div>
			</div>
		</div>
	</div>
	</form>

	<div id="footer"></div>
</div>
</body>
</html>
