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
<script>
var $j = jQuery.noConflict();
<% login_state_hook(); %>

$j(document).ready(function(){
	init_itoggle('cake_enable');
	init_itoggle('cake_nat');
	init_itoggle('cake_wash');
	updateUi();
	// itoggle bind click vao div wrapper; doi 50ms de plugin cap nhat xong checkbox that
	$j('#cake_enable_on_of').on('click', function(){ setTimeout(updateUi, 50); });
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

	document.form.cake_down_bw.value = "<% nvram_get_x("", "cake_down_bw"); %>";
	document.form.cake_up_bw.value   = "<% nvram_get_x("", "cake_up_bw"); %>";
	document.form.cake_custom.value  = "<% nvram_get_x("", "cake_custom"); %>";
	sel("cake_flow_mode",  "<% nvram_get_x("", "cake_flow_mode"); %>");
	sel("cake_diffserv",   "<% nvram_get_x("", "cake_diffserv"); %>");
	sel("cake_rtt",        "<% nvram_get_x("", "cake_rtt"); %>");
	sel("cake_overhead",   "<% nvram_get_x("", "cake_overhead"); %>");
	sel("cake_ack_filter", "<% nvram_get_x("", "cake_ack_filter"); %>");

	updateUi();
	setTimeout(updateUi, 100);
	setTimeout(updateUi, 500);

	refresh_status();
}

function cake_is_on(){
	return $j('#cake_enable_fake').is(':checked');
}

// Tắt CAKE: ẩn các bảng cấu hình (giá trị vẫn được giữ nguyên)
function updateUi(){
	document.getElementById("cake_settings").style.display = cake_is_on() ? "" : "none";
}

function refresh_status(){
	var x = new XMLHttpRequest();
	x.open("POST", "/apply.cgi", true);
	x.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
	x.onreadystatechange = function(){
		if (x.readyState == 4)
			document.getElementById("cake_status").value = (x.status == 200) ? x.responseText : "Không đọc được trạng thái";
	};
	x.send("action_mode=%20GetCakeStatus%20");
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
							<h2 class="box_head round_top">CAKE SQM</h2>
							<div class="round_bottom">
								<div class="row-fluid">
									<div id="tabMenu" class="submenuBlock"></div>

									<div class="alert alert-info" style="margin: 10px;">
										CAKE giảm bufferbloat: đặt tốc độ khoảng 90–95% tốc độ đường truyền thật. Đặt 0 để không giới hạn chiều đó (tải xuống = 0 thì không dùng ingress/IFB, đỡ tốn CPU).<br>Lưu ý: nếu <b>Hardware NAT / Software offload</b> đang bật thì gói được offload sẽ <b>bỏ qua CAKE</b>. Hãy tắt chúng, rồi nhấn &quot;Làm mới trạng thái&quot; khi đang tải: số gói &quot;Sent&quot; phải tăng nhanh. Kiểm tra chi tiết qua SSH: <code>cake.sh check</code>.<br>WAN quay số PPPoE: thêm <code>overhead 46</code> vào ô tuỳ chọn thêm (ước tính, kiểm tra lại bằng bufferbloat test).
									</div>

									<table width="100%" align="center" cellpadding="4" cellspacing="0" class="table">
<tr><th colspan="2" style="background-color: #E3E3E3;">CAKE SQM</th></tr>
<tr>
<th width="50%">Bật CAKE</th>
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
<tr><th colspan="2" style="background-color: #E3E3E3;">Giới hạn tốc độ</th></tr>
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
<tr><th colspan="2" style="background-color: #E3E3E3;">Tuỳ chọn nâng cao</th></tr>
<tr><th>Chế độ chia luồng</th><td><select name="cake_flow_mode" class="input"><option value="auto">auto (dual-srchost tải lên / dual-dsthost tải xuống, nếu bật NAT)</option><option value="triple-isolate">triple-isolate</option><option value="dual-srchost">dual-srchost</option><option value="dual-dsthost">dual-dsthost</option><option value="hosts">hosts</option><option value="srchost">srchost</option><option value="dsthost">dsthost</option><option value="flows">flows</option><option value="flowblind">flowblind</option></select></td></tr>
<tr><th>Phân loại DSCP</th><td><select name="cake_diffserv" class="input"><option value="besteffort">besteffort</option><option value="diffserv3">diffserv3</option><option value="diffserv4">diffserv4</option><option value="diffserv8">diffserv8</option></select></td></tr>
<tr><th>RTT</th><td><select name="cake_rtt" class="input"><option value="datacentre">datacentre</option><option value="lan">lan</option><option value="metro">metro</option><option value="regional">regional</option><option value="internet">internet</option><option value="oceanic">oceanic</option><option value="satellite">satellite</option></select></td></tr>
<tr><th>Overhead (loại đường truyền)</th><td><select name="cake_overhead" class="input"><option value="raw">raw</option><option value="ethernet">ethernet</option><option value="ether-vlan">ether-vlan</option><option value="pppoe-ptm">pppoe-ptm</option><option value="bridged-ptm">bridged-ptm</option><option value="docsis">docsis</option><option value="conservative">conservative</option></select></td></tr>
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
<td><input type="text" name="cake_custom" class="input" maxlength="64" size="30" value=""></td>
</tr>
</table>
</div>

<table width="100%" align="center" cellpadding="4" cellspacing="0" class="table">
<tr><th style="background-color: #E3E3E3;">Trạng thái</th></tr>
<tr>
<td>
<textarea id="cake_status" rows="22" wrap="off" readonly style="width:97%; font-family:'Courier New', Courier, mono; font-size:12px;"></textarea>
</td>
</tr>
<tr>
<td style="text-align: center;">
<input class="btn btn-primary" style="width: 219px" type="button" value="<#CTL_apply#>" onclick="applyRule()" />
<input class="btn" style="width: 140px" type="button" value="Làm mới trạng thái" onclick="refresh_status()" />
</td>
</tr>
</table>
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
