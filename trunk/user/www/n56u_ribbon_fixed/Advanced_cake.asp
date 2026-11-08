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
#cake_tabs { margin: 10px 10px 0 10px; border-bottom: 1px solid #756c78; }
#cake_tabs > li > a { color:#fff; background:#5a525d; border:1px solid #5a525d; margin-right:3px; cursor:pointer; }
#cake_tabs > li > a:hover { background:#756c78; border-color:#756c78; color:#fff; }
#cake_tabs > li.active > a, #cake_tabs > li.active > a:hover { background:#756c78; border-color:#756c78; color:#fff; font-weight:bold; }
</style>

<script>
var $j = jQuery.noConflict();
<% login_state_hook(); %>

$j(document).ready(function(){
	init_itoggle('cake_enable');
	init_itoggle('cake_nat');
	init_itoggle('cake_wash');
	init_itoggle('cake_dscp_auto');
	init_itoggle('cake_dscp_small_udp');
	updateUi();
	$j('#cake_enable_on_of').on('click', function(){ setTimeout(updateUi, 50); });
	$j('#cake_nat_on_of, #cake_wash_on_of, #cake_dscp_auto_on_of, #cake_dscp_small_udp_on_of').on('click', function(){ setTimeout(syncPreset, 80); });
	$j(window).on('beforeunload', function(){ liveStop(); });
});

function sel(n, v){
	var e = document.form[n];
	if (!e) return;
	for (var i = 0; i < e.options.length; i++){
		if (e.options[i].value == v){ e.selectedIndex = i; return; }
	}
}

function initial(){
	show_banner(1);
	show_menu(7, 37, 1);
	show_footer();

	sel("cake_flow_mode",  "<% nvram_get_x("", "cake_flow_mode"); %>");
	sel("cake_diffserv",   "<% nvram_get_x("", "cake_diffserv"); %>");
	sel("cake_rtt",        "<% nvram_get_x("", "cake_rtt"); %>");
	sel("cake_overhead",   "<% nvram_get_x("", "cake_overhead"); %>");
	sel("cake_ack_filter", "<% nvram_get_x("", "cake_ack_filter"); %>");

	try {
		var savedDown = localStorage.getItem('cake_raw_down');
		var savedUp = localStorage.getItem('cake_raw_up');
		var savedRatio = localStorage.getItem('cake_ratio_val');
		if (savedDown) $j('#raw_down').val(savedDown);
		if (savedUp) $j('#raw_up').val(savedUp);
		if (savedRatio) $j('#calc_ratio').val(savedRatio);
	} catch(e) {}

	updateUi();
	setTimeout(updateUi, 100);
	setTimeout(updateUi, 500);
	setTimeout(syncPreset, 150);

	refresh_status();

	// khôi phục tab lần trước (đợi itoggle khởi tạo xong khi tab Cấu hình còn hiển thị)
	try { if (localStorage.getItem("cake_tab") === "mon") setTimeout(function(){ showTab("mon"); }, 300); } catch(e) {}
}

// ===== TAB: cfg = Cấu hình, mon = Tổng quan & Giám sát =====
var cake_tab = "cfg";
function showTab(name){
	if (name !== "mon") name = "cfg";
	var cfg = document.getElementById("tab_cfg"), mon = document.getElementById("tab_mon");
	if (!cfg || !mon) return;
	cfg.style.display = (name === "cfg") ? "" : "none";
	mon.style.display = (name === "mon") ? "" : "none";
	document.getElementById("tabli_cfg").className = (name === "cfg") ? "active" : "";
	document.getElementById("tabli_mon").className = (name === "mon") ? "active" : "";
	cake_tab = name;
	try { localStorage.setItem("cake_tab", name); } catch(e) {}
	if (name === "mon") refresh_status();   // mở tab Tổng quan: lấy số liệu mới
	else liveStop();                         // rời tab: dừng đo trực tiếp, đỡ tốn CPU router
}

function cake_is_on(){
	return $j('#cake_enable_fake').is(':checked');
}

function updateUi(){
	document.getElementById("cake_settings").style.display = cake_is_on() ? "" : "none";
}

function toggleAdvanced(forceState){
	var tb = document.getElementById("cake_advanced_tbody");
	if (!tb) return;
	if (forceState === true) {
		tb.style.display = "";
	} else if (forceState === false) {
		tb.style.display = "none";
	} else {
		tb.style.display = (tb.style.display === "none") ? "" : "none";
	}
}

function toggleRawLog(){
	var box = document.getElementById("cake_raw_box");
	if (box) box.style.display = (box.style.display === "none") ? "" : "none";
}

function set_itoggle(name, val){
	var chk = $j('#' + name + '_fake');
	var r1 = $j('#' + name + '_1');
	var r0 = $j('#' + name + '_0');
	if (val == 1) {
		chk.attr("checked", "checked").attr("value", 1);
		r1.attr("checked", "checked");
		r0.removeAttr("checked");
		$j('#' + name + '_on_of label.itoggle').css("background-position", '0% -27px');
	} else {
		chk.removeAttr("checked").attr("value", 0);
		r0.attr("checked", "checked");
		r1.removeAttr("checked");
		$j('#' + name + '_on_of label.itoggle').css("background-position", '0% 0%');
	}
}

// ===== KỊCH BẢN (dữ liệu dùng chung cho áp dụng và nhận diện lại) =====
// Không đụng tới tốc độ và ô "Tuỳ chọn thêm cho tc".
var PRESETS = {
	mt7621_opt: {flow:"triple-isolate", ds:"diffserv3", rtt:"internet", oh:"ethernet", ack:"none", nat:1, wash:0, dscp:1},
	ping_opt:   {flow:"triple-isolate", ds:"diffserv3", rtt:"internet", oh:"ethernet", ack:"none", nat:1, wash:1, dscp:1},
	stream_opt: {flow:"dual-srchost",   ds:"diffserv4", rtt:"internet", oh:"ethernet", ack:"none", nat:1, wash:0, dscp:1},
	family_opt: {flow:"auto",           ds:"diffserv3", rtt:"internet", oh:"ethernet", ack:"none", nat:1, wash:0, dscp:1},
	light_cpu:  {flow:"flowblind",      ds:"besteffort", rtt:"internet", oh:"ethernet", ack:"none", nat:0, wash:0, dscp:0}
};

function itoggleVal(n){ return $j('#' + n + '_fake').is(':checked') ? 1 : 0; }

function detectPreset(){
	var f = document.form;
	for (var k in PRESETS) {
		var p = PRESETS[k];
		if (f.cake_flow_mode.value == p.flow && f.cake_diffserv.value == p.ds && f.cake_rtt.value == p.rtt &&
			f.cake_overhead.value == p.oh && f.cake_ack_filter.value == p.ack &&
			itoggleVal('cake_nat') == p.nat && itoggleVal('cake_wash') == p.wash && itoggleVal('cake_dscp_auto') == p.dscp)
			return k;
	}
	return "custom";
}

// chọn lại ô kịch bản cho khớp với giá trị đang có trên form
function syncPreset(){
	var k = detectPreset();
	$j('#preset_select').val(k);
	if (k === "custom") toggleAdvanced(true);
}

function onPresetChange(){
	var k = $j('#preset_select').val();
	if (k === "custom") {
		toggleAdvanced(true);
		var advTable = document.getElementById("cake_advanced_table");
		if (advTable && advTable.scrollIntoView) advTable.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
		return;
	}
	var p = PRESETS[k];
	if (!p) return;
	toggleAdvanced(false);
	sel("cake_flow_mode", p.flow);
	sel("cake_diffserv", p.ds);
	sel("cake_rtt", p.rtt);
	sel("cake_overhead", p.oh);
	sel("cake_ack_filter", p.ack);
	set_itoggle('cake_nat', p.nat);
	set_itoggle('cake_wash', p.wash);
	set_itoggle('cake_dscp_auto', p.dscp);
}

// ===== CÔNG CỤ TÍNH TỐC ĐỘ (chỉ chạy khi bấm nút) =====
function calcShaperOnly(){
	var rawDown = parseFloat($j('#raw_down').val());
	var rawUp = parseFloat($j('#raw_up').val());
	var ratio = parseFloat($j('#calc_ratio').val());

	try {
		if (!isNaN(rawDown)) localStorage.setItem('cake_raw_down', rawDown);
		if (!isNaN(rawUp)) localStorage.setItem('cake_raw_up', rawUp);
		localStorage.setItem('cake_ratio_val', ratio);
	} catch(e) {}

	var changed = false;
	if (!isNaN(rawDown) && rawDown > 0) {
		document.form.cake_down_bw.value = Math.round(rawDown * ratio);
		changed = true;
	}
	if (!isNaN(rawUp) && rawUp > 0) {
		document.form.cake_up_bw.value = Math.round(rawUp * ratio);
		changed = true;
	}
	if (changed) {
		alert("Đã điền tốc độ Shaper (tỉ lệ " + Math.round(ratio*100) + "%).\nBạn có thể chỉnh lại số này, hoặc điền 0 để bỏ giới hạn chiều đó.");
	} else {
		alert("Vui lòng nhập tốc độ vào ô Down thực hoặc Up thực trước khi tính!");
	}
}

// ===== Ping HTTPS từ trình duyệt (không phải ICMP). Bỏ mẫu đầu vì gồm bắt tay kết nối/TLS =====
function runQuickPing(){
	var btn = $j('#btn_ping'), res = $j('#ping_result');
	btn.prop('disabled', true).val('Đang đo...');
	res.html('<span style="color:#f0ad4e;">Đang đo 8 mẫu...</span>');
	var samples = [], i = 0, N = 9;

	function finish(){
		samples.shift();
		var sum = 0, mn = 1e9, mx = 0, jit = 0, k;
		for (k = 0; k < samples.length; k++) {
			sum += samples[k];
			if (samples[k] < mn) mn = samples[k];
			if (samples[k] > mx) mx = samples[k];
			if (k > 0) jit += Math.abs(samples[k] - samples[k-1]);
		}
		var avg = Math.round(sum / samples.length), jitter = Math.round(jit / (samples.length - 1));
		res.html('<b style="color:#5cb85c;">TB ' + avg + ' ms</b> | min ' + mn + ' | max ' + mx + ' | <b style="color:#5bc0de;">jitter ' + jitter + ' ms</b>');
		btn.prop('disabled', false).val('Đo ping HTTPS');
	}
	function next(){
		if (i >= N) { finish(); return; }
		var t0 = performance.now();
		function fin(){ samples.push(Math.round(performance.now() - t0)); i++; setTimeout(next, 150); }
		fetch('https://1.1.1.1/cdn-cgi/trace?_=' + Math.random(), { mode: 'no-cors', cache: 'no-store' }).then(fin).catch(fin);
	}
	next();
}

// ===== ĐỌC & HIỂN THỊ TRẠNG THÁI (bảng) =====
function esc(s){
	return String(s).replace(/[&<>"']/g, function(c){
		return {"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#39;"}[c];
	});
}
function fmtNum(n){ n = Math.round(Number(n)); if (isNaN(n)) return "-"; return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, "."); }
function fmtBytes(b){
	b = Number(b); if (isNaN(b)) return "-";
	var u = ["B","KB","MB","GB","TB"], i = 0;
	while (b >= 1024 && i < 4) { b /= 1024; i++; }
	return (i ? b.toFixed(b >= 100 ? 0 : 1) : String(b)) + " " + u[i];
}
function lbl(cls, txt){ return '<span class="label' + (cls ? ' label-' + cls : '') + '">' + esc(txt) + '</span>'; }
function toMs(s){
	var m = String(s).match(/^([\d.]+)\s*(us|ms|s)$/);
	if (!m) return null;
	var v = parseFloat(m[1]);
	return m[2] == "us" ? v / 1000 : (m[2] == "s" ? v * 1000 : v);
}
function delayLbl(s){
	var ms = toMs(s);
	if (ms === null) return esc(s);
	return lbl(ms <= 5 ? "success" : (ms <= 20 ? "warning" : "important"), s);
}
function numCell(s){ return fmtNum(s); }
function bytesCell(s){ return fmtBytes(s); }
function dropCell(s){ return Number(s) > 0 ? lbl("warning", fmtNum(s)) : fmtNum(s); }
function setHtml(id, h){ var e = document.getElementById(id); if (e) e.innerHTML = h; }

function tinNames(ds, n){
	if (ds == "diffserv3" && n == 3) return ["Bulk", "Best Effort", "Voice"];
	if (ds == "diffserv4" && n == 4) return ["Bulk", "Best Effort", "Video", "Voice"];
	if (ds == "besteffort" && n == 1) return ["Best Effort"];
	var a = [], i;
	for (i = 0; i < n; i++) a.push("Tin " + i);
	return a;
}

// lấy khối "qdisc cake ..." đầu tiên (dừng ở dòng "qdisc ..." kế tiếp, ví dụ qdisc ingress)
function parseCake(lines){
	var s = -1, e = lines.length, i, m;
	for (i = 0; i < lines.length; i++) { if (/^qdisc cake /.test(lines[i])) { s = i; break; } }
	if (s < 0) return null;
	for (i = s + 1; i < lines.length; i++) { if (/^qdisc /.test(lines[i])) { e = i; break; } }
	var b = lines.slice(s, e), h = b[0], q = { rows: {} };
	q.bw = (m = h.match(/bandwidth (\S+)/)) ? m[1] : "-";
	q.diffserv = (m = h.match(/\b(besteffort|diffserv3|diffserv4|diffserv8|precedence)\b/)) ? m[1] : "-";
	q.flow = (m = h.match(/\b(flowblind|dual-srchost|dual-dsthost|triple-isolate|srchost|dsthost|hosts|flows)\b/)) ? m[1] : "-";
	q.nat = /\bnat\b/.test(h);
	q.wash = /\bwash\b/.test(h);
	q.ingress = /\bingress\b/.test(h);
	q.ack = /no-ack-filter/.test(h) ? "tắt" : (/ack-filter-aggressive/.test(h) ? "mạnh" : (/ack-filter/.test(h) ? "bật" : "-"));
	q.rtt = (m = h.match(/\brtt (\S+)/)) ? m[1] : "-";
	q.overhead = (m = h.match(/\boverhead (\d+)/)) ? m[1] : "-";
	q.mpu = (m = h.match(/\bmpu (\d+)/)) ? m[1] : "-";
	for (i = 1; i < b.length; i++) {
		var l = b[i];
		if ((m = l.match(/Sent (\d+) bytes (\d+) pkt \(dropped (\d+), overlimits (\d+)/))) {
			q.bytes = Number(m[1]); q.pkts = Number(m[2]); q.dropped = Number(m[3]); q.over = Number(m[4]);
		} else if ((m = l.match(/memory used: (\S+) of (\S+)/))) {
			q.mem = m[1] + " / " + m[2];
		} else if ((m = l.match(/^\s{2}(thresh|target|interval|pk_delay|av_delay|sp_delay|backlog|pkts|bytes|way_inds|way_miss|way_cols|drops|marks|ack_drop|sp_flows|bk_flows|un_flows|max_len|quantum)\s+(.+)$/))) {
			q.rows[m[1]] = m[2].replace(/\s+$/, "").split(/\s+/);
		}
	}
	return q;
}

function parseStatus(text){
	var lines = String(text).split(/\r?\n/), secs = { hdr: [], up: [], down: [], stats: [] }, cur = "hdr", m, i;
	for (i = 0; i < lines.length; i++) {
		if ((m = lines[i].match(/^---\s+(.*?)\s+---\s*$/))) {
			cur = /\(upload\)/.test(m[1]) ? "up" : (/\(download\)/.test(m[1]) ? "down" : (/stats/.test(m[1]) ? "stats" : "other"));
			if (!secs[cur]) secs[cur] = [];
			continue;
		}
		secs[cur].push(lines[i]);
	}
	var p = { raw: text, ts: Date.now(), hdr: {}, hw: {}, stats: {}, up: null, down: null, ok: false };
	var hs = secs.hdr.join("\n");
	if ((m = hs.match(/enable=(\S*)/))) { p.hdr.enable = m[1]; p.ok = true; }
	if ((m = hs.match(/\bwan=(\S*)/))) p.hdr.wan = m[1];
	if ((m = hs.match(/daemon=(\S*)/))) p.hdr.daemon = m[1];
	if ((m = hs.match(/dscp_auto=(\S*)/))) p.hdr.dscp = m[1];
	if ((m = hs.match(/module=(.*?)\s+hw_nat_mode=(\S*)\s+sfe_enable=(\S*)/))) p.hw = { module: m[1], mode: m[2], sfe: m[3] };
	for (i = 0; i < secs.stats.length; i++) {
		if ((m = secs.stats[i].match(/^(\w+)=(.*)$/))) p.stats[m[1]] = m[2].replace(/\s+$/, "");
	}
	p.up = parseCake(secs.up);
	p.down = parseCake(secs.down);
	return p;
}

function renderOverview(p){
	var h = p.hdr, en = (h.enable == "1"), run = (h.daemon == "chay"), st;
	if (!p.ok) st = lbl("important", "Không đọc được trạng thái");
	else if (!en) st = lbl("", "Đang tắt");
	else if (p.up && run) st = lbl("success", "Đang chạy");
	else if (!p.up) st = lbl("warning", "Chưa gắn qdisc (xem log thẻ cake)");
	else st = lbl("warning", "Daemon đang dừng");
	setHtml("ov_state", st);
	setHtml("ov_wan", esc(h.wan || "-"));
	setHtml("ov_daemon", run ? lbl("success", "Đang chạy") : (en ? lbl("important", "Dừng") : lbl("", "Dừng")));

	var dscp;
	if (h.dscp == "1") dscp = (p.stats.dscp_hook == "ok") ? lbl("success", "Bật, luật đang gắn") : lbl("warning", "Bật nhưng luật chưa gắn");
	else dscp = lbl("", "Tắt");
	setHtml("ov_dscp", dscp);

	var hw = "-";
	if (p.hw.module !== undefined) {
		var loaded = /nap/.test(p.hw.module);
		hw = (loaded ? lbl("warning", "hw_nat đã nạp") : lbl("success", "hw_nat không nạp")) +
			' <span style="color:#aaa;">mode ' + esc(p.hw.mode) + ', sfe ' + esc(p.hw.sfe) + '</span>';
	}
	setHtml("ov_hw", hw);

	var mem = "-", t = (p.stats.tmp_kb || "").split(/\s+/);
	if (t.length >= 2 && Number(t[0]) > 0) {
		var pct = Number(t[1]) * 100 / Number(t[0]);
		mem = lbl(pct >= 90 ? "important" : (pct >= 75 ? "warning" : "success"),
			"/tmp " + fmtBytes(Number(t[1]) * 1024) + " / " + fmtBytes(Number(t[0]) * 1024));
	}
	if (p.stats.memfree_kb) mem += ' <span style="color:#aaa;">RAM trống ' + fmtBytes(Number(p.stats.memfree_kb) * 1024) + '</span>';
	setHtml("ov_mem", mem);
}

function renderDirs(p){
	function row(label, fn){
		var u = p.up ? fn(p.up) : "-", d = p.down ? fn(p.down) : "-";
		return '<tr><td>' + esc(label) + '</td><td style="text-align:center;">' + u + '</td><td style="text-align:center;">' + d + '</td></tr>';
	}
	var flags = function(q){
		return "NAT " + (q.nat ? "bật" : "tắt") + ", wash " + (q.wash ? "bật" : "tắt") + ", ACK " + q.ack;
	};
	var h = row("Băng thông", function(q){ return "<b>" + esc(q.bw) + "</b>"; }) +
		row("Phân loại (diffserv)", function(q){ return esc(q.diffserv); }) +
		row("Chia luồng", function(q){ return esc(q.flow) + (q.ingress ? " (ingress)" : ""); }) +
		row("NAT / wash / ACK", function(q){ return esc(flags(q)); }) +
		row("RTT / overhead", function(q){ return esc(q.rtt) + ", " + esc(q.overhead) + " (mpu " + esc(q.mpu) + ")"; }) +
		row("Đã xử lý", function(q){ return q.pkts === undefined ? "-" : fmtNum(q.pkts) + " gói / " + fmtBytes(q.bytes); }) +
		row("Gói bỏ / overlimit", function(q){ return q.dropped === undefined ? "-" : dropCell(q.dropped) + " / " + fmtNum(q.over); }) +
		row("Bộ nhớ qdisc", function(q){ return esc(q.mem || "-"); });
	setHtml("dir_body", h);
}

var TIN_ROWS = [
	["thresh",   "Ngưỡng tốc độ",       null],
	["pk_delay", "Trễ đỉnh",            delayLbl],
	["av_delay", "Trễ trung bình",      delayLbl],
	["sp_delay", "Trễ luồng thưa",      delayLbl],
	["pkts",     "Số gói",              numCell],
	["bytes",    "Dữ liệu",             bytesCell],
	["drops",    "Gói bị bỏ",           dropCell],
	["marks",    "ECN marks",           numCell],
	["ack_drop", "ACK bị lọc",          numCell],
	["sp_flows", "Luồng thưa",          numCell],
	["bk_flows", "Luồng nặng",          numCell]
];

function renderTins(id, q, title){
	var el = document.getElementById(id);
	if (!el) return;
	if (!q || !q.rows.thresh) {
		el.innerHTML = '<div style="margin:6px 0; color:#aaa;">' + esc(title) + ': chưa có CAKE hoặc chưa có dữ liệu.</div>';
		return;
	}
	var n = q.rows.thresh.length, names = tinNames(q.diffserv, n), i, r;
	var h = '<table class="table table-bordered table-condensed" style="margin-bottom:8px;"><thead><tr style="background-color:#5a525d; color:#fff;"><th>' + esc(title) + ' theo làn</th>';
	for (i = 0; i < n; i++) h += '<th style="text-align:center;">' + esc(names[i]) + '</th>';
	h += '</tr></thead><tbody>';
	for (r = 0; r < TIN_ROWS.length; r++) {
		var key = TIN_ROWS[r][0], vals = q.rows[key];
		if (!vals) continue;
		if (key == "ack_drop") {
			var any = false;
			for (i = 0; i < vals.length; i++) if (Number(vals[i]) > 0) any = true;
			if (!any) continue;
		}
		h += '<tr><td>' + esc(TIN_ROWS[r][1]) + '</td>';
		for (i = 0; i < n; i++) {
			var v = vals[i] === undefined ? "-" : vals[i], f = TIN_ROWS[r][2];
			h += '<td style="text-align:center;">' + (f ? f(v) : esc(v)) + '</td>';
		}
		h += '</tr>';
	}
	el.innerHTML = h + '</tbody></table>';
}

function renderAll(p){
	renderOverview(p);
	renderDirs(p);
	renderTins("tins_up", p.up, "Tải lên");
	renderTins("tins_down", p.down, "Tải xuống");
	var raw = document.getElementById("cake_raw");
	if (raw) raw.textContent = p.raw;
}

function fetchStatus(cb){
	var x = new XMLHttpRequest();
	x.open("POST", "/apply.cgi", true);
	x.timeout = 10000;
	x.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
	x.onreadystatechange = function(){
		if (x.readyState == 4) cb(x.status == 200 ? x.responseText : null);
	};
	x.send("action_mode=%20GetCakeStatus%20");
}

function refresh_status(){
	fetchStatus(function(t){
		if (t === null) {
			setHtml("ov_state", lbl("important", "Không đọc được trạng thái"));
			return;
		}
		renderAll(parseStatus(t));
	});
}

// ===== ĐO TRỰC TIẾP: so số gói WAN với số gói CAKE xử lý, và tải CPU =====
var live_timer = null, live_prev = null, live_n = 0, live_busy = false;
var LIVE_MS = 3000, LIVE_MAX = 20;

function liveToggle(){ if (live_timer) liveStop(); else liveStart(); }

function liveStart(){
	live_prev = null; live_n = 0;
	live_timer = setInterval(liveTick, LIVE_MS);
	var b = document.getElementById("btn_live"); if (b) b.value = "Dừng đo";
	setHtml("live_msg", lbl("info", "Đang đo, hãy chạy speedtest hoặc tải một file lớn"));
	liveTick();
}

function liveStop(msg){
	if (live_timer) { clearInterval(live_timer); live_timer = null; }
	var b = document.getElementById("btn_live"); if (b) b.value = "Đo trực tiếp";
	if (msg) setHtml("live_msg", msg);
}

function liveTick(){
	if (live_busy) return;
	live_busy = true;
	fetchStatus(function(t){
		live_busy = false;
		if (t === null) { liveStop(lbl("important", "Mất kết nối với router")); return; }
		var p = parseStatus(t);
		renderAll(p);
		if (live_prev) renderLive(live_prev, p);
		live_prev = p;
		live_n++;
		if (live_n >= LIVE_MAX) liveStop(lbl("", "Đã dừng sau " + (LIVE_MAX * LIVE_MS / 1000) + " giây. Bấm lại để đo tiếp."));
	});
}

function dnum(x, y){
	var u = parseFloat(x), v = parseFloat(y);
	return (isNaN(u) || isNaN(v)) ? null : v - u;
}

function liveDir(qa, qb, wa, wb, dt){
	if (!qa || !qb || qa.pkts === undefined || qb.pkts === undefined) return null;
	var wan = dnum(wa, wb), cp = qb.pkts - qa.pkts, cb = qb.bytes - qa.bytes;
	if (cp < 0 || cb < 0 || (wan !== null && wan < 0)) return null;   // bộ đếm bị đặt lại (CAKE vừa gắn lại)
	return {
		wanPps: wan === null ? null : wan / dt,
		cakePps: cp / dt,
		cov: (wan !== null && wan > 0) ? cp * 100 / wan : null,
		mbit: cb * 8 / dt / 1e6,
		idle: (wan !== null ? wan / dt : cp / dt) < 50
	};
}

function covCell(d){
	if (!d) return "-";
	if (d.idle) return lbl("", "chưa có tải");
	if (d.cov === null) return "-";
	return lbl(d.cov >= 90 ? "success" : (d.cov >= 60 ? "warning" : "important"), d.cov.toFixed(0) + "%");
}

function cpuDelta(a, b){
	var x = (a || "").split(/\s+/), y = (b || "").split(/\s+/), d = [], i, t = 0;
	if (x.length < 7 || y.length < 7) return null;
	for (i = 0; i < 7; i++) { d[i] = Number(y[i]) - Number(x[i]); t += d[i]; }
	if (!(t > 0)) return null;
	return { usr: (d[0] + d[1]) * 100 / t, sys: d[2] * 100 / t, idle: d[3] * 100 / t, io: d[4] * 100 / t, irq: d[5] * 100 / t, sirq: d[6] * 100 / t };
}

function renderLive(a, b){
	var dt = dnum(a.stats.up, b.stats.up);
	if (dt === null || dt <= 0.2) dt = (b.ts - a.ts) / 1000;
	var up = liveDir(a.up, b.up, a.stats.wan_tx_packets, b.stats.wan_tx_packets, dt);
	var dn = liveDir(a.down, b.down, a.stats.wan_rx_packets, b.stats.wan_rx_packets, dt);

	function pps(d, k){ return d && d[k] !== null ? fmtNum(d[k]) : "-"; }
	setHtml("lv_up_wan", pps(up, "wanPps"));
	setHtml("lv_up_cake", pps(up, "cakePps"));
	setHtml("lv_up_cov", covCell(up));
	setHtml("lv_up_mbit", up ? up.mbit.toFixed(1) + " Mbit/s" : "-");
	if (!b.down) {
		setHtml("lv_dn_wan", "-"); setHtml("lv_dn_cake", "-"); setHtml("lv_dn_mbit", "-");
		setHtml("lv_dn_cov", lbl("", "chưa đặt giới hạn tải xuống, không qua CAKE"));
	} else {
		setHtml("lv_dn_wan", pps(dn, "wanPps"));
		setHtml("lv_dn_cake", pps(dn, "cakePps"));
		setHtml("lv_dn_cov", covCell(dn));
		setHtml("lv_dn_mbit", dn ? dn.mbit.toFixed(1) + " Mbit/s" : "-");
	}

	var c = cpuDelta(a.stats.cpu, b.stats.cpu);
	function pc(v){ return c ? c[v].toFixed(0) + "%" : "-"; }
	setHtml("lv_cpu_usr", pc("usr")); setHtml("lv_cpu_sys", pc("sys")); setHtml("lv_cpu_irq", pc("irq"));
	setHtml("lv_cpu_sirq", pc("sirq")); setHtml("lv_cpu_idle", pc("idle"));
	setHtml("lv_meta", "Mẫu " + live_n + " (khoảng " + dt.toFixed(1) + " giây)" + (b.stats.load ? ", load " + esc(b.stats.load) : ""));

	var bad = [], level = "success", busyDirs = 0;
	if (up && !up.idle) busyDirs++;
	if (dn && !dn.idle) busyDirs++;
	var covs = [];
	if (up && !up.idle && up.cov !== null) covs.push(up.cov);
	if (dn && !dn.idle && dn.cov !== null) covs.push(dn.cov);
	var minCov = covs.length ? Math.min.apply(null, covs) : null;
	if (busyDirs === 0) {
		setHtml("live_verdict", lbl("info", "Chưa có tải đủ lớn, hãy chạy speedtest trong lúc đo"));
		return;
	}
	if (minCov !== null && minCov < 60) { bad.push("CAKE chỉ nhận " + minCov.toFixed(0) + "% số gói: có thể HW NAT/SFE đang cho gói đi tắt qua CAKE"); level = "important"; }
	else if (minCov !== null && minCov < 90) { bad.push("CAKE nhận " + minCov.toFixed(0) + "% số gói: một phần lưu lượng đi tắt"); level = "warning"; }
	if (c && (c.idle < 10 || c.sys + c.sirq > 85)) { bad.push("CPU gần chạm trần: hạ tốc độ hoặc đặt tải xuống = 0"); if (level == "success") level = "warning"; }
	setHtml("live_verdict", bad.length ? lbl(level, bad.join(". ")) : lbl("success", "CAKE nhận gần đủ số gói, CPU còn dư"));
}

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

	try {
		localStorage.setItem('cake_raw_down', $j('#raw_down').val());
		localStorage.setItem('cake_raw_up', $j('#raw_up').val());
		localStorage.setItem('cake_ratio_val', $j('#calc_ratio').val());
	} catch(e) {}

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
					<ul class="clearfix"><li><div id="subMenu" class="accordion"></div></li></ul>
				</div>
			</div>

			<div class="span9">
				<div class="row-fluid">
					<div class="span12">
						<div class="box well grad_colour_dark_blue">
							<div id="tabMenu" class="submenuBlock"></div>
							<h2 class="box_head round_top">CAKE SQM Bufferbloat Control</h2>
							<div class="round_bottom">

								<div class="alert alert-info" style="margin: 10px;">
									CAKE giảm bufferbloat: ping ổn định khi đường truyền có tải. Đặt tốc độ khoảng <b>85% - 95%</b> tốc độ thực tế.
									<div>Đặt <b>0</b> cho tải xuống để bỏ ingress/IFB (tiết kiệm CPU); khi đó chiều tải xuống không được CAKE kiểm soát. Dùng mục "Đo trực tiếp" ở tab "Tổng quan &amp; Giám sát" để xem CAKE có nhận đủ gói hay không.</div>
								</div>

								<!-- TAB -->
								<ul class="nav nav-tabs" id="cake_tabs">
									<li id="tabli_cfg" class="active"><a href="javascript:void(0)" onclick="showTab('cfg');">Cấu hình</a></li>
									<li id="tabli_mon"><a href="javascript:void(0)" onclick="showTab('mon');">Tổng quan &amp; Giám sát</a></li>
								</ul>

								<div id="tab_cfg">

								<!-- BẢNG 1: ĐIỀU KHIỂN CHÍNH -->
								<table width="100%" cellpadding="4" cellspacing="0" class="table">
								<tr><th colspan="2" style="background-color:#756c78;">Điều khiển & Thiết lập nhanh</th></tr>
								<tr>
									<th width="30%">Bật CAKE</th>
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

								<!-- BẢNG 2: KỊCH BẢN -->
								<table width="100%" cellpadding="4" cellspacing="0" class="table">
								<tr><th colspan="2" style="background-color:#756c78;">Kịch bản cấu hình thuật toán</th></tr>
								<tr>
									<th width="30%">Chọn kịch bản</th>
									<td>
										<select id="preset_select" class="input" style="width:75%; font-weight:bold;" onchange="onPresetChange();">
											<option value="mt7621_opt">1. Cân bằng CPU / ping (khuyên dùng)</option>
											<option value="ping_opt">2. Gaming (wash + DSCP tự động)</option>
											<option value="stream_opt">3. Streamer và họp trực tuyến (diffserv4)</option>
											<option value="family_opt">4. Gia đình đông người (chia đều theo máy, cả hai chiều)</option>
											<option value="light_cpu">5. Tiết kiệm CPU tối đa</option>
											<option value="custom">6. Tuỳ chọn thủ công (mở bảng thiết lập tay)</option>
										</select>
										<div style="color:#aaa; margin-top:4px; font-size:12px;">Kịch bản chỉ đổi thuật toán, không đổi tốc độ và ô "Tuỳ chọn thêm cho tc". Ô này tự chọn lại cho khớp với các giá trị đang đặt. Các kịch bản để ACK filter tắt (hợp với đường truyền đối xứng như cáp quang); chỉ bật thủ công nếu upload nhỏ hơn khoảng 1/10 download.</div>
									</td>
								</tr>
								</table>

								<!-- BẢNG 3: TỐC ĐỘ -->
								<table width="100%" cellpadding="4" cellspacing="0" class="table">
								<tr><th colspan="2" style="background-color:#756c78;">Tốc độ Shaper áp dụng (Bandwidth Limit)</th></tr>
								<tr>
									<th width="30%">Tốc độ tải xuống (Mbit)</th>
									<td>
										<input type="text" name="cake_down_bw" id="cake_down_bw" class="input" maxlength="8" style="width:100px;" value="<% nvram_get_x("", "cake_down_bw"); %>">
										<span style="color:#aaa; margin-left:10px;">Mbit/s. Điền <b>0</b> = không giới hạn và không dùng IFB (nhẹ CPU).</span>
									</td>
								</tr>
								<tr>
									<th>Tốc độ tải lên (Mbit)</th>
									<td>
										<input type="text" name="cake_up_bw" id="cake_up_bw" class="input" maxlength="8" style="width:100px;" value="<% nvram_get_x("", "cake_up_bw"); %>">
										<span style="color:#aaa; margin-left:10px;">Mbit/s. Nên đặt khoảng 85-95% tốc độ upload thực tế.</span>
									</td>
								</tr>
								<tr>
									<th>Máy tính Shaper (tuỳ chọn)</th>
									<td>
										<input type="text" id="raw_down" class="input" style="width:75px;" placeholder="Down thực"> Mbit &nbsp;|&nbsp;
										<input type="text" id="raw_up" class="input" style="width:75px;" placeholder="Up thực"> Mbit
										<select id="calc_ratio" class="input" style="width:120px; margin-left:5px;">
											<option value="0.85">Trừ hao 85%</option>
											<option value="0.90">Trừ hao 90%</option>
											<option value="0.80">Trừ hao 80%</option>
										</select>
										<input class="btn btn-info btn-small" type="button" value="Tính và điền tốc độ" onclick="calcShaperOnly();" style="margin-left:5px;">
									</td>
								</tr>
								<tr>
									<th>Ping HTTPS nhanh</th>
									<td>
										<input class="btn btn-success btn-small" id="btn_ping" type="button" value="Đo ping HTTPS" onclick="runQuickPing();">
										<span id="ping_result" style="margin-left:12px; font-size:13px; font-weight:bold;">Chưa đo</span>
										<div style="color:#aaa; font-size:12px; margin-top:3px;">Đo từ trình duyệt tới 1.1.1.1 qua HTTPS (không phải ICMP), bỏ mẫu đầu. Dùng để so sánh trước/sau khi bật CAKE.</div>
									</td>
								</tr>
								</table>

								<!-- BẢNG 4: NÂNG CAO -->
								<table width="100%" cellpadding="4" cellspacing="0" class="table" id="cake_advanced_table">
								<thead>
									<tr>
										<th colspan="2" style="background-color:#756c78;">
											Tuỳ chọn nâng cao (thiết lập tay)
											<input class="btn btn-mini" style="float:right;" type="button" value="Hiện / Ẩn" onclick="toggleAdvanced();" />
										</th>
									</tr>
								</thead>
								<tbody id="cake_advanced_tbody" style="display:none;">
								<tr>
									<th width="30%">Tự động gắn nhãn DSCP</th>
									<td>
										<div class="main_itoggle">
											<div id="cake_dscp_auto_on_of">
												<input type="checkbox" id="cake_dscp_auto_fake" <% nvram_match_x("", "cake_dscp_auto", "1", "value=1 checked"); %><% nvram_match_x("", "cake_dscp_auto", "0", "value=0"); %>>
											</div>
										</div>
										<div style="position: absolute; margin-left: -10000px;">
											<input type="radio" value="1" name="cake_dscp_auto" id="cake_dscp_auto_1" class="input" <% nvram_match_x("", "cake_dscp_auto", "1", "checked"); %> /><#checkbox_Yes#>
											<input type="radio" value="0" name="cake_dscp_auto" id="cake_dscp_auto_0" class="input" <% nvram_match_x("", "cake_dscp_auto", "0", "checked"); %> /><#checkbox_No#>
										</div>
										<span style="color:#aaa; margin-left:10px;">Gắn DSCP cho gói từ LAN (DNS, voice, game, livestream, torrent) bằng iptables. Chỉ có tác dụng chiều tải lên.</span>
									</td>
								</tr>
								<tr>
									<th>DSCP cho UDP nhỏ (&le; 256 byte)</th>
									<td>
										<div class="main_itoggle">
											<div id="cake_dscp_small_udp_on_of">
												<input type="checkbox" id="cake_dscp_small_udp_fake" <% nvram_match_x("", "cake_dscp_small_udp", "1", "value=1 checked"); %><% nvram_match_x("", "cake_dscp_small_udp", "0", "value=0"); %>>
											</div>
										</div>
										<div style="position: absolute; margin-left: -10000px;">
											<input type="radio" value="1" name="cake_dscp_small_udp" id="cake_dscp_small_udp_1" class="input" <% nvram_match_x("", "cake_dscp_small_udp", "1", "checked"); %> /><#checkbox_Yes#>
											<input type="radio" value="0" name="cake_dscp_small_udp" id="cake_dscp_small_udp_0" class="input" <% nvram_match_x("", "cake_dscp_small_udp", "0", "checked"); %> /><#checkbox_No#>
										</div>
										<span style="color:#aaa; margin-left:10px;">Coi mọi UDP nhỏ là game (CS5). Có thể làm loãng làn Voice (VPN, proxy, IoT cũng bị tính). Mặc định tắt.</span>
									</td>
								</tr>
								<tr>
									<th>Chế độ chia luồng (Flow Mode)</th>
									<td>
										<select name="cake_flow_mode" class="input" onchange="syncPreset();">
											<option value="auto">auto (dual-srchost tải lên / dual-dsthost tải xuống)</option>
											<option value="triple-isolate">triple-isolate (tải lên: chia theo máy và luồng; tải xuống: không chia luồng, nhẹ CPU)</option>
											<option value="triple-isolate-both">triple-isolate-both (chia theo máy và luồng cả hai chiều, tốn CPU hơn)</option>
											<option value="dual-srchost">dual-srchost (tải lên: theo máy nguồn; tải xuống: theo máy đích)</option>
											<option value="dual-dsthost">dual-dsthost</option>
											<option value="hosts">hosts</option>
											<option value="flows">flows</option>
											<option value="flowblind">flowblind (không chia, nhẹ nhất)</option>
										</select>
									</td>
								</tr>
								<tr>
									<th>Phân loại DSCP</th>
									<td>
										<select name="cake_diffserv" class="input" onchange="syncPreset();">
											<option value="diffserv3">diffserv3 (3 làn: Bulk, Best Effort, Voice)</option>
											<option value="diffserv4">diffserv4 (4 làn: Bulk, Best Effort, Video, Voice)</option>
											<option value="besteffort">besteffort (không phân nhóm ưu tiên)</option>
										</select>
									</td>
								</tr>
								<tr>
									<th>RTT (Round-Trip Time)</th>
									<td>
										<select name="cake_rtt" class="input" onchange="syncPreset();">
											<option value="internet">internet (mặc định ~100ms)</option>
											<option value="metro">metro (~10ms)</option>
											<option value="regional">regional (~30ms)</option>
											<option value="oceanic">oceanic (~300ms)</option>
											<option value="lan">lan (~1ms)</option>
										</select>
									</td>
								</tr>
								<tr>
									<th>Overhead (loại đường truyền)</th>
									<td>
										<select name="cake_overhead" class="input" onchange="syncPreset();">
											<option value="ethernet">ethernet (chuẩn LAN / cáp quang thông thường)</option>
											<option value="ether-vlan">ether-vlan (có VLAN tag)</option>
											<option value="pppoe-ptm">pppoe-ptm</option>
											<option value="raw">raw</option>
											<option value="conservative">conservative</option>
										</select>
									</td>
								</tr>
								<tr>
									<th>ACK filter (chiều tải lên)</th>
									<td>
										<select name="cake_ack_filter" class="input" onchange="syncPreset();">
											<option value="none">Tắt</option>
											<option value="ack-filter">ack-filter (lọc gói ACK thừa)</option>
											<option value="ack-filter-aggressive">ack-filter-aggressive (lọc mạnh)</option>
										</select>
									</td>
								</tr>
								<tr>
									<th>NAT</th>
									<td>
										<div class="main_itoggle"><div id="cake_nat_on_of"><input type="checkbox" id="cake_nat_fake" <% nvram_match_x("", "cake_nat", "1", "value=1 checked"); %><% nvram_match_x("", "cake_nat", "0", "value=0"); %>></div></div>
										<div style="position: absolute; margin-left: -10000px;">
											<input type="radio" value="1" name="cake_nat" id="cake_nat_1" class="input" <% nvram_match_x("", "cake_nat", "1", "checked"); %> /><#checkbox_Yes#>
											<input type="radio" value="0" name="cake_nat" id="cake_nat_0" class="input" <% nvram_match_x("", "cake_nat", "0", "checked"); %> /><#checkbox_No#>
										</div>
										<span style="color:#aaa; margin-left:10px;">Nhận diện máy trong LAN sau NAT. Tự bỏ qua ở chiều đang dùng flowblind.</span>
									</td>
								</tr>
								<tr>
									<th>Wash (xoá DSCP gói tải xuống)</th>
									<td>
										<div class="main_itoggle"><div id="cake_wash_on_of"><input type="checkbox" id="cake_wash_fake" <% nvram_match_x("", "cake_wash", "1", "value=1 checked"); %><% nvram_match_x("", "cake_wash", "0", "value=0"); %>></div></div>
										<div style="position: absolute; margin-left: -10000px;">
											<input type="radio" value="1" name="cake_wash" id="cake_wash_1" class="input" <% nvram_match_x("", "cake_wash", "1", "checked"); %> /><#checkbox_Yes#>
											<input type="radio" value="0" name="cake_wash" id="cake_wash_0" class="input" <% nvram_match_x("", "cake_wash", "0", "checked"); %> /><#checkbox_No#>
										</div>
									</td>
								</tr>
								<tr>
									<th>Tuỳ chọn thêm cho tc</th>
									<td><input type="text" name="cake_custom" class="input" maxlength="64" size="30" value="<% nvram_get_x("", "cake_custom"); %>" placeholder="overhead 46 ..."></td>
								</tr>
								</tbody>
								</table>

								</div>

								<!-- NÚT ÁP DỤNG (tab Cấu hình) -->
								<div style="margin:15px; text-align:center;">
									<input class="btn btn-primary" style="width:219px;" type="button" value="<#CTL_apply#>" onclick="applyRule();" />
								</div>

								</div><!-- /tab_cfg -->

								<div id="tab_mon" style="display:none;">

								<!-- BẢNG 5: TỔNG QUAN -->
								<table width="100%" cellpadding="4" cellspacing="0" class="table">
								<thead><tr><th colspan="4" style="background-color:#756c78;">Tổng quan CAKE</th></tr></thead>
								<tbody>
								<tr>
									<th width="20%">Trạng thái</th><td id="ov_state" width="30%">Đang kiểm tra...</td>
									<th width="20%">Interface WAN</th><td id="ov_wan">-</td>
								</tr>
								<tr>
									<th>Daemon giám sát</th><td id="ov_daemon">-</td>
									<th>DSCP tự động</th><td id="ov_dscp">-</td>
								</tr>
								<tr>
									<th>HW NAT / SFE</th><td id="ov_hw">-</td>
									<th>Bộ nhớ</th><td id="ov_mem">-</td>
								</tr>
								</tbody>
								</table>

								<!-- BẢNG 6: SỐ LIỆU THEO CHIỀU VÀ THEO LÀN -->
								<table width="100%" cellpadding="4" cellspacing="0" class="table">
								<thead><tr><th style="background-color:#756c78;">Số liệu CAKE theo chiều và theo làn</th></tr></thead>
								<tbody><tr><td style="padding:10px;">
									<table class="table table-bordered table-striped" style="margin-bottom:8px;">
										<thead><tr style="background-color:#5a525d; color:#fff;">
											<th width="28%">Chỉ số</th>
											<th width="36%" style="text-align:center;">Tải lên (upload)</th>
											<th width="36%" style="text-align:center;">Tải xuống (download)</th>
										</tr></thead>
										<tbody id="dir_body"><tr><td colspan="3">Đang tải...</td></tr></tbody>
									</table>
									<div id="tins_up"></div>
									<div id="tins_down"></div>
									<div style="color:#aaa; font-size:12px;">Màu độ trễ: xanh &le; 5ms (mục tiêu của CAKE), vàng &le; 20ms, đỏ cao hơn. Làn Bulk hay có độ trễ cao là bình thường vì nó nhường các làn khác.</div>
								</td></tr></tbody>
								</table>

								<!-- BẢNG 7: ĐO TRỰC TIẾP -->
								<table width="100%" cellpadding="4" cellspacing="0" class="table">
								<thead><tr><th style="background-color:#756c78;">Đo trực tiếp (CAKE có nhận đủ gói không, CPU còn dư không)</th></tr></thead>
								<tbody><tr><td style="padding:10px;">
									<table class="table table-bordered table-striped" style="margin-bottom:8px;">
										<thead><tr style="background-color:#5a525d; color:#fff;">
											<th width="34%">Chỉ số</th>
											<th width="33%" style="text-align:center;">Tải lên</th>
											<th width="33%" style="text-align:center;">Tải xuống</th>
										</tr></thead>
										<tbody>
											<tr><td>Gói/giây trên WAN</td><td id="lv_up_wan" style="text-align:center;">-</td><td id="lv_dn_wan" style="text-align:center;">-</td></tr>
											<tr><td>Gói/giây qua CAKE</td><td id="lv_up_cake" style="text-align:center;">-</td><td id="lv_dn_cake" style="text-align:center;">-</td></tr>
											<tr><td>Tỉ lệ CAKE nhìn thấy</td><td id="lv_up_cov" style="text-align:center;">-</td><td id="lv_dn_cov" style="text-align:center;">-</td></tr>
											<tr><td>Tốc độ qua CAKE</td><td id="lv_up_mbit" style="text-align:center;">-</td><td id="lv_dn_mbit" style="text-align:center;">-</td></tr>
										</tbody>
									</table>
									<table class="table table-bordered" style="margin-bottom:8px;">
										<thead><tr style="background-color:#5a525d; color:#fff;">
											<th>CPU (giữa hai lần lấy mẫu)</th>
											<th style="text-align:center;">usr</th><th style="text-align:center;">sys</th><th style="text-align:center;">irq</th><th style="text-align:center;">sirq</th><th style="text-align:center;">idle</th>
										</tr></thead>
										<tbody><tr>
											<td id="lv_meta">-</td>
											<td id="lv_cpu_usr" style="text-align:center;">-</td><td id="lv_cpu_sys" style="text-align:center;">-</td><td id="lv_cpu_irq" style="text-align:center;">-</td><td id="lv_cpu_sirq" style="text-align:center;">-</td><td id="lv_cpu_idle" style="text-align:center;">-</td>
										</tr></tbody>
									</table>
									<div style="margin:6px 0;">Kết luận: <span id="live_verdict">chưa đo</span></div>
									<div style="margin:6px 0;" id="live_msg"></div>
									<div style="color:#aaa; font-size:12px;">Bấm "Đo trực tiếp", rồi chạy speedtest hoặc tải một file lớn. Cứ 3 giây lấy một mẫu, tự dừng sau 60 giây.</div>
								</td></tr></tbody>
								</table>

								<div style="margin: 8px 15px; text-align:right;">
									<input class="btn btn-mini btn-info" type="button" value="Hiện / Ẩn dữ liệu thô (tc -s)" onclick="toggleRawLog();" />
								</div>
								<div id="cake_raw_box" style="display:none; margin:0 15px 10px;">
									<pre id="cake_raw" style="max-height:260px; overflow:auto; font-size:11px;"></pre>
								</div>

								<!-- NÚT (tab Tổng quan) -->
								<div style="margin:15px; text-align:center;">
									<input class="btn btn-warning" style="width:150px;" type="button" value="Làm mới trạng thái" onclick="refresh_status();" />
									<input class="btn btn-success" style="width:150px; margin-left:10px;" id="btn_live" type="button" value="Đo trực tiếp" onclick="liveToggle();" />
								</div>

								</div><!-- /tab_mon -->

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
