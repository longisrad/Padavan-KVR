<!DOCTYPE html>
<html>
<head>
<title>Padavan Web Management - CAKE SQM</title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
<meta http-equiv="Pragma" content="no-cache">
<meta http-equiv="Expires" content="-1">

<link rel="shortcut icon" href="images/favicon.ico">
<link rel="icon" href="images/favicon.png">
<link rel="stylesheet" type="text/css" href="/bootstrap/css/bootstrap.min.css">
<link rel="stylesheet" type="text/css" href="/bootstrap/css/main.css">

<script type="text/javascript" src="/jquery.js"></script>
<script type="text/javascript" src="/bootstrap/js/bootstrap.min.js"></script>
<script type="text/javascript" src="/state.js"></script>
<script type="text/javascript" src="/general.js"></script>
<script type="text/javascript" src="/itoggle.js"></script>
<script type="text/javascript" src="/popup.js"></script>
<script type="text/javascript" src="/help.js"></script>

<script>
var $j = jQuery.noConflict();

$j(document).ready(function() {
	init_itoggle('cake_enable', change_cake_enable);
	init_itoggle('cake_nat');
	init_itoggle('cake_wash');
});

function initial(){
	show_banner(1);
	show_menu(5, -1, 0); // Hiển thị menu cấp cao
	show_footer();
	change_cake_enable();
}

function change_cake_enable(){
	var en = document.form.cake_enable[0].checked;
	showhide_div('row_cake_settings', en);
}

function applyRule(){
	if(validForm()){
		showLoading();
		document.form.action_mode.value = " Apply ";
		document.form.current_page.value = "Advanced_cake.asp";
		document.form.next_page.value = "";
		document.form.submit();
	}
}

function validForm(){
	if(document.form.cake_enable[0].checked){
		if(!validate_range(document.form.cake_down_bw, 1, 10000000)){
			alert("Vui lòng nhập tốc độ Download hợp lệ (Kbps)!");
			document.form.cake_down_bw.focus();
			return false;
		}
		if(!validate_range(document.form.cake_up_bw, 1, 10000000)){
			alert("Vui lòng nhập tốc độ Upload hợp lệ (Kbps)!");
			document.form.cake_up_bw.focus();
			return false;
		}
	}
	return true;
}
</script>
</head>

<body onload="initial();" onunload="return unload_body();">
<div id="Loading" class="popup_bg"></div>

<div class="wrapper">
	<div class="container-fluid" style="padding-right: 0px">
		<div class="row-fluid">
			<div class="span3"><div id="mainMenu"></div><div id="subMenu"></div></div>
			<div class="span9">
				<div id="tabMenu" class="submenuBlock"></div>
				<div class="box well">
					<form method="post" name="form" action="/start_apply.htm" target="hidden_frame">
					<input type="hidden" name="current_page" value="Advanced_cake.asp">
					<input type="hidden" name="next_page" value="">
					<input type="hidden" name="next_host" value="">
					<input type="hidden" name="sid_list" value="CakeConf;">
					<input type="hidden" name="group_id" value="">
					<input type="hidden" name="action_mode" value="">
					<input type="hidden" name="action_script" value="restart_cake">

					<div class="heading">
						<h3>CAKE Smart Queue Management (SQM)</h3>
						<p class="description">CAKE là thuật toán quản lý hàng đợi QoS thế hệ mới giúp giảm tối đa độ trễ Bufferbloat khi đường truyền đầy tải.</p>
					</div>

					<table width="100%" align="center" cellpadding="4" cellspacing="0" class="table">
						<tr>
							<th width="35%">Kích hoạt CAKE QoS</th>
							<td>
								<div class="main_itoggle">
									<div id="cake_enable_on_of">
										<input type="checkbox" id="cake_enable_fake" <% nvram_match_x("", "cake_enable", "1", "value='1' checked"); %>>
									</div>
								</div>
								<div style="position: absolute; margin-left: -10000px;">
									<input type="radio" value="1" name="cake_enable" id="cake_enable_1" <% nvram_match_x("", "cake_enable", "1", "checked"); %>>Bật
									<input type="radio" value="0" name="cake_enable" id="cake_enable_0" <% nvram_match_x("", "cake_enable", "0", "checked"); %>>Tắt
								</div>
							</td>
						</tr>
					</table>

					<div id="row_cake_settings">
						<table width="100%" align="center" cellpadding="4" cellspacing="0" class="table">
							<tr>
								<th colspan="2" style="background-color: #E0E5E8;">Băng thông giới hạn (Bandwidth Shaping)</th>
							</tr>
							<tr>
								<th width="35%">Tốc độ Download (Kbps):</th>
								<td>
									<input type="text" class="input" size="10" name="cake_down_bw" value="<% nvram_get_x("", "cake_down_bw"); %>" style="width: 150px;" />
									<span class="muted">&nbsp;(Ví dụ: 100Mbps = 100000 Kbps - Đặt tầm 85-95% tốc độ thực tế)</span>
								</td>
							</tr>
							<tr>
								<th>Tốc độ Upload (Kbps):</th>
								<td>
									<input type="text" class="input" size="10" name="cake_up_bw" value="<% nvram_get_x("", "cake_up_bw"); %>" style="width: 150px;" />
									<span class="muted">&nbsp;(Ví dụ: 50Mbps = 50000 Kbps)</span>
								</td>
							</tr>

							<tr>
								<th colspan="2" style="background-color: #E0E5E8;">Tham số thuật toán CAKE</th>
							</tr>
							<tr>
								<th>Chế độ cách ly luồng (Flow Isolation):</th>
								<td>
									<select name="cake_flow_mode" class="input">
										<option value="triple-isolate" <% nvram_match_x("", "cake_flow_mode", "triple-isolate", "selected"); %>>Triple-Isolate (Host + Flow - Khuyên dùng)</option>
										<option value="flows" <% nvram_match_x("", "cake_flow_mode", "flows", "selected"); %>>Flows (Công bằng theo từng luồng)</option>
										<option value="hosts" <% nvram_match_x("", "cake_flow_mode", "hosts", "selected"); %>>Hosts (Công bằng theo thiết bị IP)</option>
										<option value="besteffort" <% nvram_match_x("", "cake_flow_mode", "besteffort", "selected"); %>>Besteffort (Không cách ly)</option>
									</select>
								</td>
							</tr>
							<tr>
								<th>Cơ chế ưu tiên gói (Diffserv):</th>
								<td>
									<select name="cake_diffserv" class="input">
										<option value="diffserv4" <% nvram_match_x("", "cake_diffserv", "diffserv4", "selected"); %>>Diffserv4 (4 hàng đợi ưu tiên - Mặc định)</option>
										<option value="diffserv3" <% nvram_match_x("", "cake_diffserv", "diffserv3", "selected"); %>>Diffserv3 (3 hàng đợi)</option>
										<option value="diffserv8" <% nvram_match_x("", "cake_diffserv", "diffserv8", "selected"); %>>Diffserv8 (8 hàng đợi)</option>
										<option value="besteffort" <% nvram_match_x("", "cake_diffserv", "besteffort", "selected"); %>>Besteffort (1 hàng đợi duy nhất)</option>
									</select>
								</td>
							</tr>
							<tr>
								<th>Độ trễ mục tiêu (RTT Latency):</th>
								<td>
									<select name="cake_rtt" class="input">
										<option value="internet" <% nvram_match_x("", "cake_rtt", "internet", "selected"); %>>Internet (100ms - Phổ thông)</option>
										<option value="metro" <% nvram_match_x("", "cake_rtt", "metro", "selected"); %>>Metro (10ms - Nội đô / Cáp quang ping thấp)</option>
										<option value="regional" <% nvram_match_x("", "cake_rtt", "regional", "selected"); %>>Regional (30ms - Khu vực)</option>
										<option value="oceanic" <% nvram_match_x("", "cake_rtt", "oceanic", "selected"); %>>Oceanic (300ms - Tuyến cáp biển)</option>
									</select>
								</td>
							</tr>
							<tr>
								<th>Bù trừ đóng gói (Framing / Overhead):</th>
								<td>
									<select name="cake_overhead" class="input">
										<option value="none" <% nvram_match_x("", "cake_overhead", "none", "selected"); %>>Không bù trừ (None / 0 byte)</option>
										<option value="ethernet" <% nvram_match_x("", "cake_overhead", "ethernet", "selected"); %>>Ethernet (14 byte overhead)</option>
										<option value="atm" <% nvram_match_x("", "cake_overhead", "atm", "selected"); %>>ADSL / ATM (44 byte overhead)</option>
										<option value="ptm" <% nvram_match_x("", "cake_overhead", "ptm", "selected"); %>>VDSL2 / PTM (8 byte overhead)</option>
										<option value="docsis" <% nvram_match_x("", "cake_overhead", "docsis", "selected"); %>>DOCSIS Cable (18 byte)</option>
									</select>
								</td>
							</tr>
							<tr>
								<th>Lọc gói ACK (ACK Filter):</th>
								<td>
									<select name="cake_ack_filter" class="input">
										<option value="none" <% nvram_match_x("", "cake_ack_filter", "none", "selected"); %>>Tắt (None)</option>
										<option value="ack-filter" <% nvram_match_x("", "cake_ack_filter", "ack-filter", "selected"); %>>Bật (Khuyên dùng khi Upload chậm)</option>
										<option value="ack-filter-aggressive" <% nvram_match_x("", "cake_ack_filter", "ack-filter-aggressive", "selected"); %>>Aggressive (Lọc mạnh tay)</option>
									</select>
								</td>
							</tr>
							<tr>
								<th>Nhận diện luồng qua NAT:</th>
								<td>
									<input type="checkbox" name="cake_nat" value="1" <% nvram_match_x("", "cake_nat", "1", "checked"); %> />
									<span class="muted">Kích hoạt để CAKE nhận diện IP nội bộ sau NAT chính xác hơn.</span>
								</td>
							</tr>
							<tr>
								<th>Wash (Xóa Diffserv lạ):</th>
								<td>
									<input type="checkbox" name="cake_wash" value="1" <% nvram_match_x("", "cake_wash", "1", "checked"); %> />
									<span class="muted">Tẩy nhãn DSCP từ ngoài vào để tránh bị nhà mạng làm sai lệch ưu tiên.</span>
								</td>
							</tr>
							<tr>
								<th>Tham số tùy biến (Custom Options):</th>
								<td>
									<input type="text" class="input span12" name="cake_custom" value="<% nvram_get_x("", "cake_custom"); %>" placeholder="memlimit 32M qerror" />
								</td>
							</tr>
						</table>
					</div>

					<table class="table">
						<tr>
							<td style="border: 0 none; text-align: right;">
								<input type="button" class="btn btn-primary" style="width: 120px" value="<#CTL_apply#>" onclick="applyRule();" />
							</td>
						</tr>
					</table>
					</form>
				</div>
			</div>
		</div>
	</div>
</div>
<div id="footer"></div>
</body>
</html>
