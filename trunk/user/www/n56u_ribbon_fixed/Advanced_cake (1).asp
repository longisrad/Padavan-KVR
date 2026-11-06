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

var hw_nat_mode = '<% nvram_get_x("", "hw_nat_mode"); %>';
var sfe_enable = '<% nvram_get_x("", "sfe_enable"); %>';

$j(document).ready(function() {
	init_itoggle('cake_enable', change_cake_enable);
	init_itoggle('cake_nat');
	init_itoggle('cake_wash');
});

function initial(){
	show_banner(1);
	show_menu(5, 37, 1);
	show_footer();
	change_cake_enable();
}

function offload_active(){
	// hw_nat_mode: 2 = Hardware NAT tắt (theo defaults.c); các giá trị khác = đang bật
	var hw = (hw_nat_mode != '' && hw_nat_mode != '2');
	var sfe = (sfe_enable != '' && sfe_enable != '0');
	return (hw || sfe);
}

function change_cake_enable(){
	var en = document.form.cake_enable[0].checked;
	showhide_div('row_cake_settings', en);
	showhide_div('row_cake_stats', en);
	showhide_div('hwnat_warning', en && offload_active());
}

function validForm(){
	if (!document.form.cake_enable[0].checked)
		return true;

	var dl = document.form.cake_down_bw;
	var ul = document.form.cake_up_bw;

	if (dl.value == "") dl.value = "0";
	if (ul.value == "") ul.value = "0";

	if (!validate_range(dl, 0, 10000000)) {
		alert("Tốc độ Download không hợp lệ (0 - 10000000 Kbps).");
		dl.focus();
		return false;
	}
	if (!validate_range(ul, 0, 10000000)) {
		alert("Tốc độ Upload không hợp lệ (0 - 10000000 Kbps).");
		ul.focus();
		return false;
	}
	if (parseInt(dl.value, 10) == 0 && parseInt(ul.value, 10) == 0) {
		alert("Cần đặt tốc độ Download hoặc Upload lớn hơn 0.");
		dl.focus();
		return false;
	}

	var cu = document.form.cake_custom;
	if (cu.value.length > 64 || !/^[A-Za-z0-9 ._-]*$/.test(cu.value)) {
		alert("Tham số tùy biến chỉ gồm chữ, số, khoảng trắng, dấu . _ - và tối đa 64 ký tự.");
		cu.focus();
		return false;
	}
	return true;
}

function applyRule(){
	if (validForm()) {
		showLoading();
		document.form.action_mode.value = " Apply ";
		document.form.current_page.value = "/Advanced_cake.asp";
		document.form.next_page.value = "";
		document.form.submit();
	}
}

function get_cake_status(){
	$j('#btn_refresh_stat').attr('disabled', true);
	$j('#cake_stats_area').text("Đang tải thống kê...");
	$j.ajax({
		type: "POST",
		url: "/apply.cgi",
		data: { action_mode: " GetCakeStatus ", current_page: "Advanced_cake.asp" },
		dataType: "text",
		cache: false,
		success: function(data){
			$j('#cake_stats_area').text($j.trim(data) || "CAKE chưa hoạt động hoặc chưa có dữ liệu.");
		},
		error: function(){
			$j('#cake_stats_area').text("Không lấy được thống kê.");
		},
		complete: function(){
			$j('#btn_refresh_stat').attr('disabled', false);
		}
	});
}
</script>
</head>

<body onload="initial();" onunload="return unload_body();">

<div class="wrapper">
	<div class="container-fluid" style="padding-right: 0px">
		<div class="row-fluid">
			<div class="span3"><center><div id="logo"></div></center></div>
			<div class="span9">
				<div id="TopBanner"></div>
			</div>
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
						<li>
							<div id="subMenu" class="accordion"></div>
						</li>
					</ul>
				</div>
			</div>

			<div class="span9">
				<div class="row-fluid">
					<div class="span12">
						<div class="box well grad_colour_dark_blue">
							<div id="tabMenu" class="submenuBlock"></div>
							<h2 class="box_head round_top">CAKE SQM</h2>
							<div class="round_bottom">
								<div class="row-fluid">
									<div class="alert alert-info" style="margin: 10px;">
										CAKE là bộ quản lý hàng đợi giúp giảm bufferbloat: ping thấp ổn định khi đường truyền đầy tải. Đặt tốc độ thấp hơn tốc độ thực của gói cước một chút để CAKE là điểm nghẽn.
									</div>

									<div id="hwnat_warning" class="alert alert-error" style="margin: 10px; display: none;">
										Hardware NAT hoặc SFE đang bật. Gói tin đi qua đường tăng tốc phần cứng sẽ <b>bỏ qua CAKE</b>, nên tốc độ giới hạn và độ trễ sẽ không chính xác. Hãy tắt Hardware NAT/SFE ở trang Tường lửa (NAT) rồi áp dụng lại.
									</div>

									<table width="100%" align="center" cellpadding="4" cellspacing="0" class="table">
										<tr>
											<th width="50%">Kích hoạt CAKE SQM</th>
											<td>
												<div class="main_itoggle">
													<div id="cake_enable_on_of">
														<input type="checkbox" id="cake_enable_fake" <% nvram_match_x("", "cake_enable", "1", "value=1 checked"); %><% nvram_match_x("", "cake_enable", "0", "value=0"); %>>
													</div>
												</div>
												<div style="position: absolute; margin-left: -10000px;">
													<input type="radio" value="1" name="cake_enable" id="cake_enable_1" class="input" onclick="change_cake_enable();" <% nvram_match_x("", "cake_enable", "1", "checked"); %>><#checkbox_Yes#>
													<input type="radio" value="0" name="cake_enable" id="cake_enable_0" class="input" onclick="change_cake_enable();" <% nvram_match_x("", "cake_enable", "0", "checked"); %>><#checkbox_No#>
												</div>
											</td>
										</tr>
									</table>

									<div id="row_cake_settings">
									<table width="100%" align="center" cellpadding="4" cellspacing="0" class="table">
										<tr>
											<th colspan="2" style="background-color: #E3E3E3;">Băng thông</th>
										</tr>
										<tr>
											<th width="50%">Tốc độ Download (Kbps)</th>
											<td>
												<input type="text" maxlength="8" class="input" size="10" name="cake_down_bw" value="<% nvram_get_x("", "cake_down_bw"); %>" onkeypress="return is_number(this,event);"/>
												&nbsp;<span style="color:#888;">0 = không giới hạn chiều này</span>
											</td>
										</tr>
										<tr>
											<th>Tốc độ Upload (Kbps)</th>
											<td>
												<input type="text" maxlength="8" class="input" size="10" name="cake_up_bw" value="<% nvram_get_x("", "cake_up_bw"); %>" onkeypress="return is_number(this,event);"/>
												&nbsp;<span style="color:#888;">khuyên đặt 85-95% tốc độ gói</span>
											</td>
										</tr>

										<tr>
											<th colspan="2" style="background-color: #E3E3E3;">Tham số CAKE</th>
										</tr>
										<tr>
											<th>Cách ly luồng</th>
											<td>
												<select class="input" name="cake_flow_mode">
													<option value="auto" <% nvram_match_x("", "cake_flow_mode", "auto", "selected"); %>>Tự động (upload: theo IP nguồn, download: theo IP đích)</option>
													<option value="triple-isolate" <% nvram_match_x("", "cake_flow_mode", "triple-isolate", "selected"); %>>Triple-isolate</option>
													<option value="flows" <% nvram_match_x("", "cake_flow_mode", "flows", "selected"); %>>Flows (theo từng luồng)</option>
													<option value="hosts" <% nvram_match_x("", "cake_flow_mode", "hosts", "selected"); %>>Hosts (theo từng IP)</option>
													<option value="flowblind" <% nvram_match_x("", "cake_flow_mode", "flowblind", "selected"); %>>Không cách ly</option>
												</select>
											</td>
										</tr>
										<tr>
											<th>Ưu tiên gói (Diffserv)</th>
											<td>
												<select class="input" name="cake_diffserv">
													<option value="diffserv3" <% nvram_match_x("", "cake_diffserv", "diffserv3", "selected"); %>>Diffserv3 (3 lớp, mặc định)</option>
													<option value="diffserv4" <% nvram_match_x("", "cake_diffserv", "diffserv4", "selected"); %>>Diffserv4 (4 lớp)</option>
													<option value="diffserv8" <% nvram_match_x("", "cake_diffserv", "diffserv8", "selected"); %>>Diffserv8 (8 lớp)</option>
													<option value="besteffort" <% nvram_match_x("", "cake_diffserv", "besteffort", "selected"); %>>Besteffort (1 lớp)</option>
												</select>
											</td>
										</tr>
										<tr>
											<th>Độ trễ mục tiêu (RTT)</th>
											<td>
												<select class="input" name="cake_rtt">
													<option value="internet" <% nvram_match_x("", "cake_rtt", "internet", "selected"); %>>Internet (100ms)</option>
													<option value="regional" <% nvram_match_x("", "cake_rtt", "regional", "selected"); %>>Regional (30ms)</option>
													<option value="metro" <% nvram_match_x("", "cake_rtt", "metro", "selected"); %>>Metro (10ms)</option>
													<option value="oceanic" <% nvram_match_x("", "cake_rtt", "oceanic", "selected"); %>>Oceanic (300ms)</option>
												</select>
											</td>
										</tr>
										<tr>
											<th>Bù trừ đóng gói (Overhead)</th>
											<td>
												<select class="input" name="cake_overhead">
													<option value="ethernet" <% nvram_match_x("", "cake_overhead", "ethernet", "selected"); %>>Ethernet</option>
													<option value="pppoe" <% nvram_match_x("", "cake_overhead", "pppoe", "selected"); %>>PPPoE (quang/GPON, Ethernet)</option>
													<option value="none" <% nvram_match_x("", "cake_overhead", "none", "selected"); %>>Không bù trừ</option>
													<option value="atm" <% nvram_match_x("", "cake_overhead", "atm", "selected"); %>>ADSL / ATM</option>
													<option value="ptm" <% nvram_match_x("", "cake_overhead", "ptm", "selected"); %>>VDSL2 / PTM</option>
													<option value="docsis" <% nvram_match_x("", "cake_overhead", "docsis", "selected"); %>>DOCSIS (cáp)</option>
												</select>
											</td>
										</tr>
										<tr>
											<th>Lọc gói ACK (chiều upload)</th>
											<td>
												<select class="input" name="cake_ack_filter">
													<option value="none" <% nvram_match_x("", "cake_ack_filter", "none", "selected"); %>>Tắt</option>
													<option value="ack-filter" <% nvram_match_x("", "cake_ack_filter", "ack-filter", "selected"); %>>Bật</option>
													<option value="ack-filter-aggressive" <% nvram_match_x("", "cake_ack_filter", "ack-filter-aggressive", "selected"); %>>Mạnh</option>
												</select>
											</td>
										</tr>
										<tr>
											<th>Nhận diện IP qua NAT</th>
											<td>
												<div class="main_itoggle">
													<div id="cake_nat_on_of">
														<input type="checkbox" id="cake_nat_fake" <% nvram_match_x("", "cake_nat", "1", "value=1 checked"); %><% nvram_match_x("", "cake_nat", "0", "value=0"); %>>
													</div>
												</div>
												<div style="position: absolute; margin-left: -10000px;">
													<input type="radio" value="1" name="cake_nat" id="cake_nat_1" class="input" <% nvram_match_x("", "cake_nat", "1", "checked"); %>><#checkbox_Yes#>
													<input type="radio" value="0" name="cake_nat" id="cake_nat_0" class="input" <% nvram_match_x("", "cake_nat", "0", "checked"); %>><#checkbox_No#>
												</div>
											</td>
										</tr>
										<tr>
											<th>Wash (xóa nhãn DSCP chiều download)</th>
											<td>
												<div class="main_itoggle">
													<div id="cake_wash_on_of">
														<input type="checkbox" id="cake_wash_fake" <% nvram_match_x("", "cake_wash", "1", "value=1 checked"); %><% nvram_match_x("", "cake_wash", "0", "value=0"); %>>
													</div>
												</div>
												<div style="position: absolute; margin-left: -10000px;">
													<input type="radio" value="1" name="cake_wash" id="cake_wash_1" class="input" <% nvram_match_x("", "cake_wash", "1", "checked"); %>><#checkbox_Yes#>
													<input type="radio" value="0" name="cake_wash" id="cake_wash_0" class="input" <% nvram_match_x("", "cake_wash", "0", "checked"); %>><#checkbox_No#>
												</div>
											</td>
										</tr>
										<tr>
											<th>Tham số bổ sung</th>
											<td>
												<input type="text" maxlength="64" class="input" size="30" name="cake_custom" value="<% nvram_get_x("", "cake_custom"); %>" placeholder="memlimit 32M"/>
											</td>
										</tr>
									</table>
									</div>

									<div id="row_cake_stats">
									<table width="100%" align="center" cellpadding="4" cellspacing="0" class="table">
										<tr>
											<th style="background-color: #E3E3E3;">
												Thống kê hàng đợi
												<button type="button" id="btn_refresh_stat" class="btn btn-mini btn-info pull-right" onclick="get_cake_status();">Cập nhật</button>
											</th>
										</tr>
										<tr>
											<td>
												<pre id="cake_stats_area" style="margin: 0; max-height: 260px; overflow: auto; font-size: 11px;">Bấm "Cập nhật" để xem trạng thái CAKE (sau khi đã Áp dụng).</pre>
											</td>
										</tr>
									</table>
									</div>

									<table class="table">
										<tr>
											<td style="border: 0 none;">
												<center><input class="btn btn-primary" style="width: 219px" type="button" value="<#CTL_apply#>" onclick="applyRule()" /></center>
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
