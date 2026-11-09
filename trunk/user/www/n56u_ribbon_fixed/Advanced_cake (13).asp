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

<style>
.badge-lat { display:inline-block; min-width:45px; padding:2px 5px; border-radius:3px; font-weight:bold; font-size:11px; text-align:center; color:#fff; }
.lat-green { background-color:#28a745; }
.lat-yellow { background-color:#ffc107; color:#000; }
.lat-orange { background-color:#fd7e14; }
.lat-red { background-color:#dc3545; }
.table-dash th, .table-dash td { text-align:center; vertical-align:middle !important; font-size:11px; padding:4px 6px; }
</style>

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
<% login_state_hook(); %>

$j(document).ready(function(){
	init_itoggle('cake_enable');
	init_itoggle('cake_nat');
	init_itoggle('cake_wash');
	init_itoggle('cake_dscp_auto');
	updateUi();
	$j('#cake_enable_on_of').on('click', function(){ setTimeout(updateUi, 50); });
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
		var savedPreset = localStorage.getItem('cake_preset_val');
		var savedRatio = localStorage.getItem('cake_ratio_val');

		if (savedDown) $j('#raw_down').val(savedDown);
		if (savedUp) $j('#raw_up').val(savedUp);
		if (savedRatio) $j('#calc_ratio').val(savedRatio);
		if (savedPreset) $j('#preset_select').val(savedPreset);
	} catch(e) {}

	bindSummary();
	updateUi();
	setTimeout(updateUi, 100);
	setTimeout(updateUi, 500);

	refresh_status();
}

function cake_is_on(){
	return $j('#cake_enable_fake').is(':checked');
}

function updateUi(){
	document.getElementById("cake_settings").style.display = cake_is_on() ? "" : "none";
	updateSummary();
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

/* ==========================================================================
   BẢNG TỔNG HỢP TẢI XUỐNG / TẢI LÊN (TAB CẤU HÌNH)
   ========================================================================== */
function updateSummary(){
	var f = document.form;
	if (!f || !f.cake_down_bw) return;

	var dn = parseFloat(f.cake_down_bw.value) || 0;
	var up = parseFloat(f.cake_up_bw.value) || 0;
	var flow = f.cake_flow_mode.value;
	var diff = f.cake_diffserv.value;
	var ack = f.cake_ack_filter.value;
	var nat = $j('#cake_nat_fake').is(':checked');
	var wash = $j('#cake_wash_fake').is(':checked');
	var dscp = $j('#cake_dscp_auto_fake').is(':checked');
	var rtt = f.cake_rtt.value;
	var ovh = f.cake_overhead.value;

	var on = '<span class="label label-success">Bật</span>';
	var off = '<span class="label">Tắt</span>';
	var na = '<span style="color:#aaa;">Không áp dụng</span>';

	$j('#sum_down_mode').html(dn > 0
		? '<span class="label label-info">CAKE kiểm soát</span>'
		: '<span class="label label-warning">Thả nổi</span> HW_NAT chuyển tiếp, CAKE không can thiệp');
	$j('#sum_up_mode').html(up > 0
		? '<span class="label label-info">CAKE kiểm soát</span>'
		: '<span class="label label-warning">Thả nổi</span> không giới hạn');

	$j('#sum_down_bw').text(dn > 0 ? dn + ' Mbit/s' : '0 (không giới hạn)');
	$j('#sum_up_bw').text(up > 0 ? up + ' Mbit/s' : '0 (không giới hạn)');

	var flowDn = flow, flowUp = flow;
	if (flow === 'auto') { flowDn = 'dual-dsthost'; flowUp = 'dual-srchost'; }
	$j('#sum_down_flow').text(dn > 0 ? flowDn : '-');
	$j('#sum_up_flow').text(up > 0 ? flowUp : '-');

	$j('#sum_down_diff').text(dn > 0 ? diff : '-');
	$j('#sum_up_diff').text(up > 0 ? diff : '-');

	$j('#sum_down_ack').html(na);
	$j('#sum_up_ack').html(up > 0 ? (ack === 'none' ? off : ack) : '-');

	$j('#sum_down_wash').html(dn > 0 ? (wash ? on : off) : '-');
	$j('#sum_up_wash').html(na);

	$j('#sum_common').html(
		'NAT: ' + (nat ? 'Bật' : 'Tắt') +
		' &nbsp;|&nbsp; Tự gắn DSCP: ' + (dscp ? 'Bật' : 'Tắt') +
		' &nbsp;|&nbsp; RTT: ' + rtt +
		' &nbsp;|&nbsp; Overhead: ' + ovh);
}

function bindSummary(){
	$j('#ruleForm').on('change keyup click', 'input, select', function(){
		setTimeout(updateSummary, 80);
	});
}

function onPresetChange(){
	var preset = $j('#preset_select').val();

	try {
		localStorage.setItem('cake_preset_val', preset);
	} catch(e) {}

	if (preset === "mt7621_opt") {
		toggleAdvanced(false);
		sel("cake_flow_mode", "triple-isolate");
		sel("cake_diffserv", "diffserv3");
		sel("cake_rtt", "internet");
		sel("cake_overhead", "ethernet");
		sel("cake_ack_filter", "ack-filter");
		set_itoggle('cake_nat', 1);
		set_itoggle('cake_wash', 0);
		set_itoggle('cake_dscp_auto', 1);
		document.form.cake_custom.value = "";
	} else if (preset === "ping_opt") {
		toggleAdvanced(false);
		sel("cake_flow_mode", "triple-isolate");
		sel("cake_diffserv", "diffserv3");
		sel("cake_rtt", "internet");
		sel("cake_overhead", "ethernet");
		sel("cake_ack_filter", "ack-filter");
		set_itoggle('cake_nat', 1);
		set_itoggle('cake_wash', 1);
		set_itoggle('cake_dscp_auto', 1);
	} else if (preset === "stream_opt") {
		toggleAdvanced(false);
		sel("cake_flow_mode", "dual-srchost");
		sel("cake_diffserv", "diffserv4");
		sel("cake_rtt", "internet");
		sel("cake_overhead", "ethernet");
		sel("cake_ack_filter", "ack-filter");
		set_itoggle('cake_nat', 1);
		set_itoggle('cake_wash', 0);
		set_itoggle('cake_dscp_auto', 1);
	} else if (preset === "family_opt") {
		toggleAdvanced(false);
		sel("cake_flow_mode", "auto");
		sel("cake_diffserv", "diffserv3");
		sel("cake_rtt", "internet");
		sel("cake_overhead", "ethernet");
		sel("cake_ack_filter", "ack-filter");
		set_itoggle('cake_nat', 1);
		set_itoggle('cake_wash', 0);
		set_itoggle('cake_dscp_auto', 1);
	} else if (preset === "light_cpu") {
		toggleAdvanced(false);
		sel("cake_flow_mode", "flowblind");
		sel("cake_diffserv", "besteffort");
		sel("cake_rtt", "internet");
		sel("cake_overhead", "ethernet");
		sel("cake_ack_filter", "ack-filter");
		set_itoggle('cake_nat', 1);
		set_itoggle('cake_wash', 0);
		set_itoggle('cake_dscp_auto', 0);
	} else if (preset === "custom") {
		toggleAdvanced(true);
		var advTable = document.getElementById("cake_advanced_table");
		if (advTable) advTable.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
	}
}

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
	updateSummary();
	if (changed) {
		alert("✅ Đã tính toán và điền tốc độ Shaper (tỉ lệ " + Math.round(ratio*100) + "%).\nBạn có thể tự chỉnh lại số 0 hoặc số khác tùy ý!");
	} else {
		alert("Vui lòng nhập tốc độ vào ô Down thực hoặc Up thực trước khi tính!");
	}
}

/* ==========================================================================
   HÀM ĐỊNH DẠNG VÀ CẬP NHẬT BẢNG GIÁM SÁT (CHUẨN 4 CỘT)
   ========================================================================== */
function formatLatBadge(str){
	if (!str || str === "0us") return '<span class="badge-lat lat-green">' + (str||"0us") + '</span>';
	var ms = 0;
	if (str.indexOf("us") !== -1) ms = parseFloat(str) / 1000;
	else if (str.indexOf("ms") !== -1) ms = parseFloat(str);
	else ms = parseFloat(str);

	if (isNaN(ms) || ms <= 5) return '<span class="badge-lat lat-green">' + str + '</span>';
	if (ms <= 20) return '<span class="badge-lat lat-yellow">' + str + '</span>';
	if (ms <= 50) return '<span class="badge-lat lat-orange">' + str + '</span>';
	return '<span class="badge-lat lat-red">' + str + '</span>';
}

function formatBytes(b){
	b = parseInt(b) || 0;
	if (b < 1024) return b + ' B';
	if (b < 1048576) return (b / 1024).toFixed(1) + ' KB';
	if (b < 1073741824) return (b / 1048576).toFixed(1) + ' MB';
	return (b / 1073741824).toFixed(2) + ' GB';
}

// Hàm chuẩn tạo đúng 4 cột: Cột Tên hàng + Bulk + Best Effort + Voice
function makeRow(label, bulkVal, bestVal, voiceVal){
	return '<td style="text-align:left; font-weight:bold;">' + label + '</td>' +
	       '<td>' + (bulkVal !== undefined ? bulkVal : '-') + '</td>' +
	       '<td>' + (bestVal !== undefined ? bestVal : '-') + '</td>' +
	       '<td>' + (voiceVal !== undefined ? voiceVal : '-') + '</td>';
}

function parseSection(secText){
	var res = {};
	var mSent = secText.match(/Sent\s+(\d+)\s+bytes\s+(\d+)\s+pkt\s+\(dropped\s+(\d+),\s+overlimits\s+(\d+)/i);
	if (mSent) {
		res.bytes = parseInt(mSent[1]); res.pkts = parseInt(mSent[2]);
		res.dropped = parseInt(mSent[3]); res.overlimits = parseInt(mSent[4]);
	}
	var mMem = secText.match(/memory used:\s+(\d+)b\s+of\s+(\d+)b/i);
	if (mMem) { res.memUsed = mMem[1]; res.memMax = mMem[2]; }

	var lines = secText.split('\n');
	var inTins = false;
	res.tins = {};
	var fields = ["thresh", "target", "interval", "pk_delay", "av_delay", "sp_delay", "backlog", "pkts", "bytes", "drops", "marks", "ack_drop", "sp_flows", "bk_flows"];

	for (var i = 0; i < lines.length; i++){
		var l = lines[i].trim();
		if (/Bulk\s+Best Effort\s+Voice/i.test(l)) { inTins = true; continue; }
		if (inTins) {
			var parts = l.split(/\s+/);
			if (parts.length >= 4) {
				var key = parts[0].toLowerCase();
				if (fields.indexOf(key) !== -1) {
					res.tins[key] = { bulk: parts[1], best: parts[2], voice: parts[3] };
				}
			}
		}
	}
	return res;
}

function updateTinTables(upSec, downSec){
	var up = parseSection(upSec);
	var dn = parseSection(downSec);

	// 1. Điền bảng Tải lên (Đầy đủ 4 cột, không bị dồn lệch)
	if (up.tins && up.tins.thresh) {
		$j('#u_tr_thresh').html(makeRow('Ngưỡng tốc độ', up.tins.thresh.bulk, up.tins.thresh.best, up.tins.thresh.voice));
		$j('#u_tr_pkdel').html(makeRow('Trễ đỉnh', formatLatBadge(up.tins.pk_delay.bulk), formatLatBadge(up.tins.pk_delay.best), formatLatBadge(up.tins.pk_delay.voice)));
		$j('#u_tr_avdel').html(makeRow('Trễ trung bình', formatLatBadge(up.tins.av_delay.bulk), formatLatBadge(up.tins.av_delay.best), formatLatBadge(up.tins.av_delay.voice)));
		$j('#u_tr_spdel').html(makeRow('Trễ luồng thừa', formatLatBadge(up.tins.sp_delay.bulk), formatLatBadge(up.tins.sp_delay.best), formatLatBadge(up.tins.sp_delay.voice)));
		$j('#u_tr_pkts').html(makeRow('Số gói', up.tins.pkts.bulk, up.tins.pkts.best, up.tins.pkts.voice));
		$j('#u_tr_bytes').html(makeRow('Dữ liệu', formatBytes(up.tins.bytes.bulk), formatBytes(up.tins.bytes.best), formatBytes(up.tins.bytes.voice)));
		$j('#u_tr_drops').html(makeRow('Gói bị bỏ', up.tins.drops.bulk, up.tins.drops.best, up.tins.drops.voice));
		$j('#u_tr_spflows').html(makeRow('Luồng thừa', up.tins.sp_flows.bulk, up.tins.sp_flows.best, up.tins.sp_flows.voice));
		$j('#u_tr_bkflows').html(makeRow('Luồng nặng', up.tins.bk_flows.bulk, up.tins.bk_flows.best, up.tins.bk_flows.voice));
	}

	// 2. Điền bảng Tải xuống (Đầy đủ 4 cột)
	if (dn.tins && dn.tins.thresh) {
		$j('#d_tr_thresh').html(makeRow('Ngưỡng tốc độ', dn.tins.thresh.bulk, dn.tins.thresh.best, dn.tins.thresh.voice));
		$j('#d_tr_pkdel').html(makeRow('Trễ đỉnh', formatLatBadge(dn.tins.pk_delay.bulk), formatLatBadge(dn.tins.pk_delay.best), formatLatBadge(dn.tins.pk_delay.voice)));
		$j('#d_tr_avdel').html(makeRow('Trễ trung bình', formatLatBadge(dn.tins.av_delay.bulk), formatLatBadge(dn.tins.av_delay.best), formatLatBadge(dn.tins.av_delay.voice)));
		$j('#d_tr_spdel').html(makeRow('Trễ luồng thừa', formatLatBadge(dn.tins.sp_delay.bulk), formatLatBadge(dn.tins.sp_delay.best), formatLatBadge(dn.tins.sp_delay.voice)));
		$j('#d_tr_pkts').html(makeRow('Số gói', dn.tins.pkts.bulk, dn.tins.pkts.best, dn.tins.pkts.voice));
		$j('#d_tr_bytes').html(makeRow('Dữ liệu', formatBytes(dn.tins.bytes.bulk), formatBytes(dn.tins.bytes.best), formatBytes(dn.tins.bytes.voice)));
		$j('#d_tr_drops').html(makeRow('Gói bị bỏ', dn.tins.drops.bulk, dn.tins.drops.best, dn.tins.drops.voice));
		$j('#d_tr_spflows').html(makeRow('Luồng thừa', dn.tins.sp_flows.bulk, dn.tins.sp_flows.best, dn.tins.sp_flows.voice));
		$j('#d_tr_bkflows').html(makeRow('Luồng nặng', dn.tins.bk_flows.bulk, dn.tins.bk_flows.best, dn.tins.bk_flows.voice));
	}

	return { up: up, dn: dn };
}

function parseStatsBlock(text){
	var obj = {};
	var lines = text.split('\n');
	for (var i = 0; i < lines.length; i++){
		var p = lines[i].split('=');
		if (p.length === 2) obj[p[0].trim()] = p[1].trim();
	}
	return obj;
}

function fetchSample(callback, errCallback){
	$j.ajax({
		url: '/apply.cgi',
		type: 'POST',
		timeout: 4000,
		data: { 'action_mode': ' GetCakeStatus ' }
	}).done(function(raw){
		document.getElementById("cake_status").value = raw;
		var parts = raw.split(/--- [^ ]+ \(download\) ---/);
		var upSec = parts[0] || "";
		var downSec = (parts.length > 1) ? parts[1].split(/--- stats ---/)[0] : "";
		var statsSec = (raw.indexOf("--- stats ---") !== -1) ? raw.split(/--- stats ---/)[1] : "";

		var qdiscData = updateTinTables(upSec, downSec);
		var sysStats = parseStatsBlock(statsSec);

		var snap = {
			time: parseFloat(sysStats.up || "0"),
			wanTxPkts: parseInt(sysStats.wan_tx_packets || "0"),
			wanRxPkts: parseInt(sysStats.wan_rx_packets || "0"),
			cakeTxPkts: qdiscData.up.pkts || 0,
			cakeRxPkts: qdiscData.dn.pkts || 0,
			cakeTxBytes: qdiscData.up.bytes || 0,
			cakeRxBytes: qdiscData.dn.bytes || 0,
			load: sysStats.load || "0 0 0"
		};

		if (sysStats.cpu) {
			var cp = sysStats.cpu.split(/\s+/);
			if (cp.length >= 7) {
				snap.cpu = {
					usr: parseInt(cp[0]) + parseInt(cp[1]),
					sys: parseInt(cp[2]),
					idle: parseInt(cp[3]),
					io: parseInt(cp[4]),
					irq: parseInt(cp[5]),
					sirq: parseInt(cp[6])
				};
			}
		}
		if (callback) callback(snap);
	}).fail(function(){
		if (errCallback) errCallback();
	});
}

function refresh_status(){
	fetchSample();
}

/* ==========================================================================
   CÔNG CỤ ĐO TRỰC TIẾP TAB 3
   ========================================================================== */
var isMeasuring = false;
var measureTimer = null;
var measureSamplesCount = 0;
var lastSnap = null;

function toggleMeasure(){
	if (isMeasuring) stopMeasure();
	else startMeasure();
}

function startMeasure(){
	isMeasuring = true;
	measureSamplesCount = 0;
	lastSnap = null;
	$j('#btn_measure').val('⏹️ Dừng đo').removeClass('btn-success').addClass('btn-danger');
	$j('#measure_conclusion').html('<span class="label label-info">Đang lấy mẫu ban đầu...</span>');
	$j('#measure_lost_conn').hide();

	fetchSample(function(s0){
		lastSnap = s0;
		measureTimer = setInterval(takeLiveSample, 3000);
	}, function(){
		$j('#measure_lost_conn').show();
		stopMeasure();
	});
}

function stopMeasure(){
	isMeasuring = false;
	if (measureTimer) { clearInterval(measureTimer); measureTimer = null; }
	$j('#btn_measure').val('🟢 Đo trực tiếp').removeClass('btn-danger').addClass('btn-success');
}

function takeLiveSample(){
	measureSamplesCount++;
	if (measureSamplesCount > 20) {
		stopMeasure();
		$j('#measure_conclusion').append(' <span class="label">Đã dừng sau 60 giây.</span>');
		return;
	}

	fetchSample(function(sNow){
		$j('#measure_lost_conn').hide();
		if (!lastSnap || !lastSnap.time) { lastSnap = sNow; return; }

		var dt = sNow.time - lastSnap.time;
		if (dt <= 0.1) return;

		var dWanTx = (sNow.wanTxPkts - lastSnap.wanTxPkts) / dt;
		var dWanRx = (sNow.wanRxPkts - lastSnap.wanRxPkts) / dt;
		var dCakeTx = (sNow.cakeTxPkts - lastSnap.cakeTxPkts) / dt;
		var dCakeRx = (sNow.cakeRxPkts - lastSnap.cakeRxPkts) / dt;
		var mbpsTx = ((sNow.cakeTxBytes - lastSnap.cakeTxBytes) * 8) / (dt * 1000000);
		var mbpsRx = ((sNow.cakeRxBytes - lastSnap.cakeRxBytes) * 8) / (dt * 1000000);

		$j('#live_wan_tx_pps').text(Math.round(dWanTx));
		$j('#live_wan_rx_pps').text(Math.round(dWanRx));
		$j('#live_cake_tx_pps').text(Math.round(dCakeTx));
		$j('#live_cake_rx_pps').text(Math.round(dCakeRx));
		$j('#live_cake_tx_mbps').text(mbpsTx.toFixed(1) + ' Mbit/s');
		$j('#live_cake_rx_mbps').text(mbpsRx.toFixed(1) + ' Mbit/s');

		var rTx = (dWanTx > 10) ? Math.min(100, Math.round(dCakeTx * 100 / dWanTx)) : 0;
		var rRx = (dWanRx > 10) ? Math.min(100, Math.round(dCakeRx * 100 / dWanRx)) : 0;

		$j('#live_cake_tx_pct').html((dWanTx > 50) ? (rTx + '%') : '<span style="color:#aaa;">chưa có tải</span>');
		$j('#live_cake_rx_pct').html((dWanRx > 50) ? (rRx + '%') : '<span style="color:#aaa;">chưa có tải</span>');

		var idlePct = 100;
		if (sNow.cpu && lastSnap.cpu) {
			var du = sNow.cpu.usr - lastSnap.cpu.usr;
			var ds = sNow.cpu.sys - lastSnap.cpu.sys;
			var di = sNow.cpu.idle - lastSnap.cpu.idle;
			var dq = sNow.cpu.irq - lastSnap.cpu.irq;
			var dsq = sNow.cpu.sirq - lastSnap.cpu.sirq;
			var dTot = du + ds + di + dq + dsq;
			if (dTot > 0) {
				var uP = Math.round(du * 100 / dTot);
				var sP = Math.round(ds * 100 / dTot);
				var qP = Math.round(dq * 100 / dTot);
				var sqP = Math.round(dsq * 100 / dTot);
				idlePct = Math.round(di * 100 / dTot);

				$j('#live_cpu_usr').text(uP + '%');
				$j('#live_cpu_sys').text(sP + '%');
				$j('#live_cpu_irq').text(qP + '%');
				$j('#live_cpu_sirq').text(sqP + '%');
				$j('#live_cpu_idle').text(idlePct + '%');
				$j('#live_cpu_title').text('Mẫu ' + measureSamplesCount + ' (' + dt.toFixed(1) + 's), load: ' + sNow.load);
			}
		}

		if (dWanTx < 100 && dWanRx < 100) {
			$j('#measure_conclusion').html('<span class="label label-warning">Chưa có tải đủ lớn, hãy chạy speedtest trong lúc đo</span>');
		} else if (idlePct > 15 && (rTx > 70 || rRx > 70)) {
			$j('#measure_conclusion').html('<span class="label label-success">CAKE nhận đủ số gói, CPU còn dư (' + idlePct + '% idle)</span>');
		} else if (idlePct <= 10) {
			$j('#measure_conclusion').html('<span class="label label-important">CẢNH BÁO: CPU đang bị quá tải (idle &le; 10%)</span>');
		} else {
			$j('#measure_conclusion').html('<span class="label label-info">Đang kiểm soát lưu lượng bình thường</span>');
		}

		lastSnap = sNow;
	}, function(){
		$j('#measure_lost_conn').show();
		stopMeasure();
	});
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
		localStorage.setItem('cake_preset_val', $j('#preset_select').val());
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
							<h2 class="box_head round_top">CAKE SQM Bufferbloat Control</h2>
							<div class="round_bottom">

								<div class="alert alert-info" style="margin: 10px;">
									CAKE giảm triệt để Bufferbloat giúp ổn định Ping tuyệt đối khi mạng có tải.
									<div>Khuyên dùng: Đặt tốc độ bằng <b>85% - 90%</b> tốc độ thực tế. Đặt <b>0</b> cho tải xuống nếu muốn HW_NAT gánh max băng thông (tiết kiệm CPU cho MT7621).</div>
								</div>

								<!-- THANH ĐIỀU HƯỚNG 3 TAB CHUẨN XÁC -->
								<ul class="nav nav-tabs" style="margin: 10px 10px 0 10px;">
									<li class="active"><a href="#tab_cake_cfg" data-toggle="tab">⚙️ Cấu hình</a></li>
									<li><a href="#tab_cake_monitor" data-toggle="tab">📊 Giám sát</a></li>
									<li><a href="#tab_cake_live" data-toggle="tab">⚡ Đo trực tiếp</a></li>
								</ul>

								<div class="tab-content" style="padding: 0 10px;">
								
								<!-- ======================================================================
								     TAB 1: CẤU HÌNH (SETTINGS, PRESETS & SHAPER)
								     ====================================================================== -->
								<div class="tab-pane active" id="tab_cake_cfg">

									<!-- ĐIỀU KHIỂN CHÍNH -->
									<table width="100%" cellpadding="4" cellspacing="0" class="table">
									<tr><th colspan="2" style="background-color:#756c78;">Điều khiển chính</th></tr>
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

									<!-- 5 KỊCH BẢN THUẬT TOÁN -->
									<table width="100%" cellpadding="4" cellspacing="0" class="table">
									<tr><th colspan="2" style="background-color:#756c78;">Kịch bản cấu hình thuật toán</th></tr>
									<tr>
										<th width="30%">Chọn kịch bản</th>
										<td>
											<select id="preset_select" class="input" style="width:75%; font-weight:bold;" onchange="onPresetChange();">
												<option value="mt7621_opt">⭐ 1. Hiệu năng thực dụng (HW_NAT + CAKE Upload - Khuyên dùng)</option>
												<option value="ping_opt">🛡️ 2. Gaming Hardcore (Bufferbloat A+ cả 2 chiều)</option>
												<option value="stream_opt">🎥 3. Streamer & Họp trực tuyến (Diffserv4 4 làn)</option>
												<option value="family_opt">👨‍👩‍👧‍👦 4. Gia đình đông người (Chống tranh giành mạng)</option>
												<option value="light_cpu">⚡ 5. Tiết kiệm CPU tối đa (Siêu nhẹ)</option>
												<option value="custom">✏️ 6. Tuỳ chọn thủ công (Mở bảng thiết lập tay)</option>
											</select>
										</td>
									</tr>
									</table>

									<!-- GIỚI HẠN TỐC ĐỘ & MÁY TÍNH SHAPER -->
									<table width="100%" cellpadding="4" cellspacing="0" class="table">
									<tr><th colspan="2" style="background-color:#756c78;">Tốc độ Shaper áp dụng (Bandwidth Limit)</th></tr>
									<tr>
										<th width="30%">Tốc độ tải xuống (Mbit)</th>
										<td>
											<input type="text" name="cake_down_bw" id="cake_down_bw" class="input" maxlength="8" style="width:100px;" value="<% nvram_get_x("", "cake_down_bw"); %>">
											<span style="color:#aaa; margin-left:10px;">Mbit/s (Điền <b>0</b> = thả nổi không giới hạn, để HW_NAT gánh max tốc độ).</span>
										</td>
									</tr>
									<tr>
										<th>Tốc độ tải lên (Mbit)</th>
										<td>
											<input type="text" name="cake_up_bw" id="cake_up_bw" class="input" maxlength="8" style="width:100px;" value="<% nvram_get_x("", "cake_up_bw"); %>">
											<span style="color:#aaa; margin-left:10px;">Mbit/s (Nên đặt bằng 85% tốc độ Upload thực tế).</span>
										</td>
									</tr>
									<tr>
										<th>Máy tính Shaper (Tùy chọn)</th>
										<td>
											<input type="text" id="raw_down" class="input" style="width:75px;" placeholder="Down thực"> Mbit &nbsp;|&nbsp;
											<input type="text" id="raw_up" class="input" style="width:75px;" placeholder="Up thực"> Mbit
											<select id="calc_ratio" class="input" style="width:120px; margin-left:5px;">
												<option value="0.85">Trừ hao 85%</option>
												<option value="0.90">Trừ hao 90%</option>
												<option value="0.80">Trừ hao 80%</option>
											</select>
											<input class="btn btn-info btn-small" type="button" value="⚡ Tính & Điền tốc độ" onclick="calcShaperOnly();" style="margin-left:5px;">
										</td>
									</tr>
									</table>

									<!-- TỔNG HỢP CÁCH XỬ LÝ TẢI XUỐNG / TẢI LÊN (cập nhật tức thời theo form) -->
									<table width="100%" cellpadding="4" cellspacing="0" class="table table-bordered table-dash" id="cake_summary_table">
									<thead>
										<tr><th colspan="3" style="background-color:#756c78; color:#fff; text-align:left;">Tổng hợp cách kết nối Tải xuống / Tải lên (theo cấu hình đang chọn)</th></tr>
										<tr style="background-color:#5a525d; color:#fff;">
											<th width="28%" style="text-align:left;">Tiêu chí</th>
											<th width="36%">&#11015;&#65039; Tải xuống (Download)</th>
											<th width="36%">&#11014;&#65039; Tải lên (Upload)</th>
										</tr>
									</thead>
									<tbody>
										<tr><td style="text-align:left; font-weight:bold;">Cách xử lý</td><td id="sum_down_mode">-</td><td id="sum_up_mode">-</td></tr>
										<tr><td style="text-align:left; font-weight:bold;">Tốc độ Shaper</td><td id="sum_down_bw">-</td><td id="sum_up_bw">-</td></tr>
										<tr><td style="text-align:left; font-weight:bold;">Chia luồng</td><td id="sum_down_flow">-</td><td id="sum_up_flow">-</td></tr>
										<tr><td style="text-align:left; font-weight:bold;">Phân làn ưu tiên</td><td id="sum_down_diff">-</td><td id="sum_up_diff">-</td></tr>
										<tr><td style="text-align:left; font-weight:bold;">ACK filter</td><td id="sum_down_ack">-</td><td id="sum_up_ack">-</td></tr>
										<tr><td style="text-align:left; font-weight:bold;">Wash (xoá DSCP)</td><td id="sum_down_wash">-</td><td id="sum_up_wash">-</td></tr>
										<tr><td style="text-align:left; font-weight:bold;">Dùng chung 2 chiều</td><td colspan="2" id="sum_common">-</td></tr>
									</tbody>
									</table>
									<div style="font-size:11px; color:#aaa; margin:-5px 0 10px 0;">* Bảng này phản ánh các giá trị đang chọn trên form. Bấm <b>Áp dụng</b> để router thực thi.</div>

									<!-- BẢNG TUỲ CHỌN NÂNG CAO (TỰ BUNG KHI CHỌN KỊCH BẢN THỦ CÔNG) -->
									<table width="100%" cellpadding="4" cellspacing="0" class="table" id="cake_advanced_table">
									<thead>
										<tr>
											<th colspan="2" style="background-color:#756c78;">
												Tuỳ chọn nâng cao (Thiết lập tay)
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
											<span style="color:#aaa; margin-left:10px;">Tự động phân loại gói DNS, Voice vào EF/CS6, Game online vào CS5, Stream vào CS4 qua iptables.</span>
										</td>
									</tr>
									<tr>
										<th>Chế độ chia luồng (Flow Mode)</th>
										<td>
											<select name="cake_flow_mode" class="input">
												<option value="auto">auto (dual-srchost tải lên / dual-dsthost tải xuống)</option>
												<option value="triple-isolate">triple-isolate (Khuyên dùng - chia đều theo máy và luồng)</option>
												<option value="dual-srchost">dual-srchost</option>
												<option value="dual-dsthost">dual-dsthost</option>
												<option value="hosts">hosts</option>
												<option value="flows">flows</option>
												<option value="flowblind">flowblind</option>
											</select>
										</td>
									</tr>
									<tr>
										<th>Phân loại DSCP</th>
										<td>
											<select name="cake_diffserv" class="input">
												<option value="diffserv3">diffserv3 (3 làn: Bulk, Best Effort, Voice/Game)</option>
												<option value="diffserv4">diffserv4 (4 làn: Bulk, Best Effort, Video, Voice)</option>
												<option value="besteffort">besteffort (Không phân nhóm ưu tiên)</option>
											</select>
										</td>
									</tr>
									<tr>
										<th>RTT (Round-Trip Time)</th>
										<td>
											<select name="cake_rtt" class="input">
												<option value="internet">internet (Mặc định ~100ms)</option>
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
											<select name="cake_overhead" class="input">
												<option value="ethernet">ethernet (Chuẩn mạng LAN / Cáp quang thông thường)</option>
												<option value="ether-vlan">ether-vlan (Có VLAN tag)</option>
												<option value="pppoe-ptm">pppoe-ptm</option>
												<option value="raw">raw</option>
												<option value="conservative">conservative</option>
											</select>
										</td>
									</tr>
									<tr>
										<th>ACK filter (chiều tải lên)</th>
										<td>
											<select name="cake_ack_filter" class="input">
												<option value="ack-filter">ack-filter (Bật - Lọc thông minh gói ACK, khuyên dùng)</option>
												<option value="none">Tắt</option>
												<option value="ack-filter-aggressive">ack-filter-aggressive (Lọc gắt)</option>
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

									<div style="margin: 15px 0; text-align: center;">
										<input class="btn btn-primary" style="width:219px;" type="button" value="<#CTL_apply#>" onclick="applyRule();" />
									</div>

								</div>
								<!-- /tab_cake_cfg -->

								<!-- ======================================================================
								     TAB 2: GIÁM SÁT (PHÂN LÀN & DỮ LIỆU THỐNG KÊ)
								     ====================================================================== -->
								<div class="tab-pane" id="tab_cake_monitor">

									<!-- BẢNG TẢI LÊN THEO LÀN -->
									<table width="100%" cellpadding="3" cellspacing="0" class="table table-bordered table-striped table-dash" style="margin-top:10px;">
									<thead>
										<tr style="background-color:#5a525d; color:#fff;">
											<th width="28%" style="text-align:left;">Tải lên theo làn (Upload)</th>
											<th width="24%">Bulk</th>
											<th width="24%">Best Effort</th>
											<th width="24%">Voice</th>
										</tr>
									</thead>
									<tbody>
										<tr id="u_tr_thresh"><td style="text-align:left; font-weight:bold;">Ngưỡng tốc độ</td><td>-</td><td>-</td><td>-</td></tr>
										<tr id="u_tr_pkdel"><td style="text-align:left; font-weight:bold;">Trễ đỉnh</td><td>-</td><td>-</td><td>-</td></tr>
										<tr id="u_tr_avdel"><td style="text-align:left; font-weight:bold;">Trễ trung bình</td><td>-</td><td>-</td><td>-</td></tr>
										<tr id="u_tr_spdel"><td style="text-align:left; font-weight:bold;">Trễ luồng thừa</td><td>-</td><td>-</td><td>-</td></tr>
										<tr id="u_tr_pkts"><td style="text-align:left; font-weight:bold;">Số gói</td><td>-</td><td>-</td><td>-</td></tr>
										<tr id="u_tr_bytes"><td style="text-align:left; font-weight:bold;">Dữ liệu</td><td>-</td><td>-</td><td>-</td></tr>
										<tr id="u_tr_drops"><td style="text-align:left; font-weight:bold;">Gói bị bỏ</td><td>-</td><td>-</td><td>-</td></tr>
										<tr id="u_tr_spflows"><td style="text-align:left; font-weight:bold;">Luồng thừa</td><td>-</td><td>-</td><td>-</td></tr>
										<tr id="u_tr_bkflows"><td style="text-align:left; font-weight:bold;">Luồng nặng</td><td>-</td><td>-</td><td>-</td></tr>
									</tbody>
									</table>

									<!-- BẢNG TẢI XUỐNG THEO LÀN -->
									<table width="100%" cellpadding="3" cellspacing="0" class="table table-bordered table-striped table-dash">
									<thead>
										<tr style="background-color:#5a525d; color:#fff;">
											<th width="28%" style="text-align:left;">Tải xuống theo làn (Download)</th>
											<th width="24%">Bulk</th>
											<th width="24%">Best Effort</th>
											<th width="24%">Voice</th>
										</tr>
									</thead>
									<tbody>
										<tr id="d_tr_thresh"><td style="text-align:left; font-weight:bold;">Ngưỡng tốc độ</td><td>-</td><td>-</td><td>-</td></tr>
										<tr id="d_tr_pkdel"><td style="text-align:left; font-weight:bold;">Trễ đỉnh</td><td>-</td><td>-</td><td>-</td></tr>
										<tr id="d_tr_avdel"><td style="text-align:left; font-weight:bold;">Trễ trung bình</td><td>-</td><td>-</td><td>-</td></tr>
										<tr id="d_tr_spdel"><td style="text-align:left; font-weight:bold;">Trễ luồng thừa</td><td>-</td><td>-</td><td>-</td></tr>
										<tr id="d_tr_pkts"><td style="text-align:left; font-weight:bold;">Số gói</td><td>-</td><td>-</td><td>-</td></tr>
										<tr id="d_tr_bytes"><td style="text-align:left; font-weight:bold;">Dữ liệu</td><td>-</td><td>-</td><td>-</td></tr>
										<tr id="d_tr_drops"><td style="text-align:left; font-weight:bold;">Gói bị bỏ</td><td>-</td><td>-</td><td>-</td></tr>
										<tr id="d_tr_spflows"><td style="text-align:left; font-weight:bold;">Luồng thừa</td><td>-</td><td>-</td><td>-</td></tr>
										<tr id="d_tr_bkflows"><td style="text-align:left; font-weight:bold;">Luồng nặng</td><td>-</td><td>-</td><td>-</td></tr>
									</tbody>
									</table>

									<div style="font-size:11px; color:#aaa; margin-bottom:10px;">
										* Màu độ trễ: <span class="badge-lat lat-green">&le; 5ms</span> (Mục tiêu CAKE) | <span class="badge-lat lat-yellow">&le; 20ms</span> | <span class="badge-lat lat-red">&gt; 20ms</span>.
									</div>

									<div style="margin: 15px 0; text-align: center;">
										<input class="btn btn-warning" style="width:150px; margin-right:10px;" type="button" value="🔄 Làm mới bảng" onclick="refresh_status();" />
										<input class="btn btn-info" style="width:180px;" type="button" value="🔍 Hiện/Ẩn dữ liệu thô (tc -s)" onclick="toggleRawLog();" />
									</div>

									<div id="cake_raw_box" style="display:none; margin-top:8px;">
										<textarea id="cake_status" rows="16" wrap="off" readonly style="width:98%; font-family:'Courier New',monospace; font-size:11px; background:#1e1e1e; color:#00ff66;"></textarea>
									</div>

								</div>
								<!-- /tab_cake_monitor -->

								<!-- ======================================================================
								     TAB 3: ĐO TRỰC TIẾP (THỜI GIAN THỰC & CHẨN ĐOÁN TẢI)
								     ====================================================================== -->
								<div class="tab-pane" id="tab_cake_live">

									<!-- BẢNG CHỈ SỐ GÓI VÀ TỐC ĐỘ THỰC TẾ -->
									<table width="100%" cellpadding="4" cellspacing="0" class="table table-bordered table-dash" style="margin-top:10px;">
									<thead>
										<tr style="background-color:#756c78; color:#fff;">
											<th colspan="3" style="text-align:left; font-size:12px;">Đo trực tiếp (CAKE có nhận đủ gói không, CPU còn dư không)</th>
										</tr>
										<tr style="background-color:#5a525d; color:#fff;">
											<th width="34%" style="text-align:left;">Chỉ số</th>
											<th width="33%">Tải lên</th>
											<th width="33%">Tải xuống</th>
										</tr>
									</thead>
									<tbody>
										<tr><td style="text-align:left;">Gói/giây trên WAN</td><td id="live_wan_tx_pps">0</td><td id="live_wan_rx_pps">0</td></tr>
										<tr><td style="text-align:left;">Gói/giây qua CAKE</td><td id="live_cake_tx_pps">0</td><td id="live_cake_rx_pps">0</td></tr>
										<tr><td style="text-align:left;">Tỉ lệ CAKE nhìn thấy</td><td id="live_cake_tx_pct">-</td><td id="live_cake_rx_pct">-</td></tr>
										<tr><td style="text-align:left;">Tốc độ qua CAKE</td><td id="live_cake_tx_mbps">0.0 Mbit/s</td><td id="live_cake_rx_mbps">0.0 Mbit/s</td></tr>
									</tbody>
									</table>

									<!-- BẢNG CPU THEO LẦN LẤY MẪU -->
									<table width="100%" cellpadding="4" cellspacing="0" class="table table-bordered table-dash">
									<thead>
										<tr style="background-color:#5a525d; color:#fff;">
											<th width="50%" style="text-align:left;" id="live_cpu_title">CPU (giữa hai lần lấy mẫu)</th>
											<th width="10%">usr</th>
											<th width="10%">sys</th>
											<th width="10%">irq</th>
											<th width="10%">sirq</th>
											<th width="10%">idle</th>
										</tr>
									</thead>
									<tbody>
										<tr>
											<td style="text-align:left;">Mức sử dụng</td>
											<td id="live_cpu_usr">-</td>
											<td id="live_cpu_sys">-</td>
											<td id="live_cpu_irq">-</td>
											<td id="live_cpu_sirq">-</td>
											<td id="live_cpu_idle" style="font-weight:bold; color:#5cb85c;">-</td>
										</tr>
									</tbody>
									</table>

									<div style="margin: 10px 0;">
										<b>Kết luận:</b> <span id="measure_conclusion"><span class="label label-info">Bấm "Đo trực tiếp" rồi chạy Speedtest</span></span>
										<span id="measure_lost_conn" style="display:none; margin-left:8px;" class="label label-important">Mất kết nối với router</span>
									</div>
									<div style="font-size:11px; color:#888; margin-bottom:12px;">
										Bấm "Đo trực tiếp", rồi chạy speedtest hoặc tải một file lớn. Cứ 3 giây lấy một mẫu, tự dừng sau 60 giây.
									</div>

									<div style="margin: 15px 0; text-align:center;">
										<input class="btn btn-success" id="btn_measure" style="width:160px; font-weight:bold;" type="button" value="🟢 Đo trực tiếp" onclick="toggleMeasure();" />
										<input class="btn btn-warning" style="width:150px; margin-left:10px;" type="button" value="🔄 Làm mới trạng thái" onclick="refresh_status();" />
									</div>

								</div>
								<!-- /tab_cake_live -->

								</div>
								<!-- /tab-content -->

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
