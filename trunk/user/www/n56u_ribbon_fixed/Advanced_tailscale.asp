<!DOCTYPE html>
<html>
<head>
<title><#Web_Title#> - Tailsale</title>
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
<script type="text/javascript" src="/client_function.js"></script>
<script type="text/javascript" src="/itoggle.js"></script>
<script type="text/javascript" src="/popup.js"></script>
<script type="text/javascript" src="/help.js"></script>
<script>
var $j = jQuery.noConflict();
<% tailscale_status(); %>
<% tailscaled_status(); %>
$j(document).ready(function() {
	init_itoggle('tailscale_dns');
	init_itoggle('tailscale_route');
	init_itoggle('tailscale_exit');
	init_itoggle('tailscale_reset');
	init_itoggle('tailscale_ssh');
	init_itoggle('tailscale_shields');
	$j("#tab_tailscale_cfg, #tab_tailscale_log").click(
	function () {
		var newHash = $j(this).attr('href').toLowerCase();
		showTab(newHash);
		return false;
	});

});

</script>
<script>

function initial(){
	show_banner(2);
	show_menu(5, 29, 0);
	show_footer();
	fill_status(tailscaled_status());
	fill_status2(tailscale_status());
	change_tailscale_enable();

}

var arrHashes = ["cfg","log"];
function showTab(curHash) {
	var obj = $('tab_tailscale_' + curHash.slice(1));
	if (obj == null || obj.style.display == 'none')
	curHash = '#cfg';
	for (var i = 0; i < arrHashes.length; i++) {
		if (curHash == ('#' + arrHashes[i])) {
			$j('#tab_tailscale_' + arrHashes[i]).parents('li').addClass('active');
			$j('#wnd_tailscale_' + arrHashes[i]).show();
		} else {
			$j('#wnd_tailscale_' + arrHashes[i]).hide();
			$j('#tab_tailscale_' + arrHashes[i]).parents('li').removeClass('active');
			}
		}
	window.location.hash = curHash;
}

function fill_status(status_code){
	var stext = "Unknown";
	if (status_code == 0)
		stext = "<#Stopped#>";
	else if (status_code == 1)
		stext = "<#Running#>";
	$("tailscaled_status").innerHTML = '<span class="label label-' + (status_code != 0 ? 'success' : 'warning') + '">' + stext + '</span>';
}

function fill_status2(status_code){
	var stext = "Unknown";
	if (status_code == 0)
		stext = "<#Stopped#>";
	else if (status_code == 1)
		stext = "<#Running#>";
	$("tailscale_status").innerHTML = '<span class="label label-' + (status_code != 0 ? 'success' : 'warning') + '">' + stext + '</span>';
}

function applyRule(){
	showLoading();
	
	document.form.action_mode.value = " Apply ";
	document.form.current_page.value = "/Advanced_tailscale.asp";
	document.form.next_page.value = "";
	
	document.form.submit();
}

function done_validating(action){
	refreshpage();
}

function change_tailscale_enable(mflag){
	var m = document.form.tailscale_enable.value;
	var is_tailscale_enable = (m == "1" || m == "2") ? "Restart" : "Update";
	document.form.restarttailscale.value = is_tailscale_enable;
	
	var is_tailscale_cmd = (m == "2") ? 1 : 0;
	var is_tailscale_df = (m == "1") ? 1 : 0;

	showhide_div("tailscale_cmd_tr", is_tailscale_cmd);
	showhide_div("tailscale_cmd_td", is_tailscale_cmd);

	
	showhide_div("tailscale_dns_tr", is_tailscale_df);
	showhide_div("tailscale_dns_td", is_tailscale_df);

	showhide_div("tailscale_route_tr", is_tailscale_df);
	showhide_div("tailscale_route_td", is_tailscale_df);

	showhide_div("tailscale_routes_tr", is_tailscale_df);
	showhide_div("tailscale_routes_td", is_tailscale_df);
	
	showhide_div("tailscale_exit_tr", is_tailscale_df);
	showhide_div("tailscale_exit_td", is_tailscale_df);

	showhide_div("tailscale_exitip_tr", is_tailscale_df);
	showhide_div("tailscale_exitip_td", is_tailscale_df);

	showhide_div("tailscale_server_tr", is_tailscale_df);
	showhide_div("tailscale_server_td", is_tailscale_df);

	showhide_div("tailscale_ssh_tr", is_tailscale_df);
	showhide_div("tailscale_ssh_td", is_tailscale_df);

	showhide_div("tailscale_shields_tr", is_tailscale_df);
	showhide_div("tailscale_shields_td", is_tailscale_df);

	showhide_div("tailscale_host_tr", is_tailscale_df);
	showhide_div("tailscale_host_td", is_tailscale_df);

	showhide_div("tailscale_key_tr", is_tailscale_df);
	showhide_div("tailscale_key_td", is_tailscale_df);

	showhide_div("tailscale_reset_tr", is_tailscale_df);
	showhide_div("tailscale_reset_td", is_tailscale_df);
	
	showhide_div("tailscale_cmd2_tr", is_tailscale_df);
	showhide_div("tailscale_cmd2_td", is_tailscale_df);

}
function button_restarttailscale() {
    var m = document.form.tailscale_enable.value;

    var actionMode = (m == "1" || m == "2") ? ' Restarttailscale ' : ' Updatetailscale ';

    change_tailscale_enable(m); 

    var $j = jQuery.noConflict(); 
    $j.post('/apply.cgi', {
        'action_mode': actionMode 
    });
}

function clearLog(){
	var $j = jQuery.noConflict();
	$j.post('/apply.cgi', {
		'action_mode': ' ClearTsLog ',
		'next_host': 'Advanced_tailscale.asp#log'
	}).always(function() {
		setTimeout(function() {
			location.reload(); 
		}, 3000);
	});
}

</script>
</head>

<body onload="initial();" onunLoad="return unload_body();">

<div class="wrapper">
	<div class="container-fluid" style="padding-right: 0px">
	<div class="row-fluid">
	<div class="span3"><center><div id="logo"></div></center></div>
	<div class="span9" >
	<div id="TopBanner"></div>
	</div>
	</div>
	</div>

	<div id="Loading" class="popup_bg"></div>

	<iframe name="hidden_frame" id="hidden_frame" src="" width="0" height="0" frameborder="0"></iframe>

	<form method="post" name="form" id="ruleForm" action="/start_apply.htm" target="hidden_frame">

	<input type="hidden" name="current_page" value="Advanced_tailscale.asp">
	<input type="hidden" name="next_page" value="">
	<input type="hidden" name="next_host" value="">
	<input type="hidden" name="sid_list" value="TAILSCALE;LANHostConfig;General;">
	<input type="hidden" name="group_id" value="">
	<input type="hidden" name="action_mode" value="">
	<input type="hidden" name="action_script" value="">

	<div class="container-fluid">
	<div class="row-fluid">
	<div class="span3">
	<!--Sidebar content-->
	<!--=====Beginning of Main Menu=====-->
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
	<!--Body content-->
	<div class="row-fluid">
	<div class="span12">
	<div class="box well grad_colour_dark_blue">
	<h2 class="box_head round_top">Tailsale</h2>
	<div class="round_bottom">
	<div>
	<ul class="nav nav-tabs" style="margin-bottom: 10px;">
	<li class="active"><a id="tab_tailscale_cfg" href="#cfg">Basic Settings</a></li>
	<li><a id="tab_tailscale_log" href="#log">Run Log</a></li>
	</ul>
	</div>
	<div class="row-fluid">
	<div id="tabMenu" class="submenuBlock"></div>
	<div id="wnd_tailscale_cfg">
	<div class="alert alert-info" style="margin: 10px;">Tailscale lets you easily manage access to private resources and quickly SSH into devices on your network, making networking simple.
	<div>Project page: <a href="https://github.com/tailscale/tailscale" target="blank">https://github.com/tailscale/tailscale</a></div>
  		<br><div>Current version: 【<span style="color: #FFFF00;"><% nvram_get_x("", "tailscale_ver"); %></span>】&nbsp;&nbsp;Latest version: 【<span style="color: #FD0187;"><% nvram_get_x("", "tailscale_ver_n"); %></span>】 &nbsp;&nbsp;<a href="<% nvram_get_x("", "tailscale_login"); %>" target="blank"><% nvram_get_x("", "tailscale_login"); %></a>
  		<br>&nbsp;<% nvram_get_x("", "tailscale_info"); %>
	</div>
	
	<span style="color:#FF0000;" class=""></span></div>

	<table width="100%" align="center" cellpadding="4" cellspacing="0" class="table">
	<tr>
	<th colspan="4" style="background-color: #756c78;">Running Status</th>
	</tr>
	<tr> <th>tailscaled</th>
            <td id="tailscaled_status" colspan="2"></td>
          </tr>
	<tr> <th>tailscale</th>
            <td id="tailscale_status" colspan="2"></td>
          </tr>
	<tr>
	<th colspan="4" style="background-color: #756c78;">Program Configuration</th>
	</tr>
	<tr>
	<th width="30%" style="border-top: 0 none;">Enable Tailscale</th>
	<td style="border-top: 0 none;">
	<select name="tailscale_enable" class="input" onChange="change_tailscale_enable();" style="width: 185px;">
	<option value="0" <% nvram_match_x("","tailscale_enable", "0","selected"); %>>【Off】</option>
	<option value="1" <% nvram_match_x("","tailscale_enable", "1","selected"); %>>【On】</option>
	<option value="2" <% nvram_match_x("","tailscale_enable", "2","selected"); %>>【On】Tailscale Custom Parameters</option>
	<option value="3" <% nvram_match_x("","tailscale_enable", "3","selected"); %>>【Reset】Restore to defaults</option>
	</select>
	</td>
	<td colspan="4" style="border-top: 0 none;">
	<input class="btn btn-success" style="width:150px" type="button" name="restarttailscale" value="Update" onclick="button_restarttailscale()" />
	</td>
	</tr><td colspan="3"></td>
	<tr id="tailscale_cmd_tr">
	<th width="30%" style="border-top: 0 none;">Custom Parameter Startup
	</th>
	<td colspan="4" style="border-top: 0 none;">
	<textarea maxlength="1024" class="input" name="tailscale_cmd" id="tailscale_cmd" placeholder="up --accept-dns=false --accept-routes --advertise-routes=192.168.2.0/24 --advertise-exit-node --reset" style="width: 210px; height: 20px; resize: both; overflow: auto;"><% nvram_get_x("","tailscale_cmd"); %></textarea>
	&nbsp;<a href="https://tailscale.com/kb/1241/tailscale-up/" target="blank">Command Parameter Reference</a><br>&nbsp;<span style="color:#888;">Enter the startup command directly, no need for path or program name.</span>
	</td>
	</tr><tr id="tailscale_cmd_td" ><td colspan="3"></td></tr>
	<tr id="tailscale_dns_tr" >
	<th style="border-top: 0 none;">Accept DNS Settings</th>
	<td style="border-top: 0 none;">
	<div class="main_itoggle">
	<div id="tailscale_dns_on_of">
	<input type="checkbox" id="tailscale_dns_fake" <% nvram_match_x("", "tailscale_dns", "1", "value=1 checked"); %><% nvram_match_x("", "tailscale_dns", "0", "value=0"); %> />
	</div>
	</div>
	<div style="position: absolute; margin-left: -10000px;">
	<input type="radio" value="1" name="tailscale_dns" id="tailscale_dns_1" class="input" value="1" <% nvram_match_x("", "tailscale_dns", "1", "checked"); %> /><#checkbox_Yes#>
	<input type="radio" value="0" name="tailscale_dns" id="tailscale_dns_0" class="input" value="0" <% nvram_match_x("", "tailscale_dns", "0", "checked"); %> /><#checkbox_No#>
	</div>
	</td>
	</tr><tr id="tailscale_dns_td" ><td colspan="3"></td></tr>
	<tr id="tailscale_route_tr" >
	<th style="border-top: 0 none;">Accept Routes</th>
	<td style="border-top: 0 none;">
	<div class="main_itoggle">
	<div id="tailscale_route_on_of">
	<input type="checkbox" id="tailscale_route_fake" <% nvram_match_x("", "tailscale_route", "1", "value=1 checked"); %><% nvram_match_x("", "tailscale_route", "0", "value=0"); %> />
	&nbsp;<span style="color:#888;">Accept subnet routes advertised by other nodes</span></div>
	</div>
	<div style="position: absolute; margin-left: -10000px;">
		<input type="radio" value="1" name="tailscale_route" id="tailscale_route_1" class="input" value="1" <% nvram_match_x("", "tailscale_route", "1", "checked"); %> /><#checkbox_Yes#>
		<input type="radio" value="0" name="tailscale_route" id="tailscale_route_0" class="input" value="0" <% nvram_match_x("", "tailscale_route", "0", "checked"); %> /><#checkbox_No#>
	</div>
	</td>
	</tr><tr id="tailscale_route_td" ><td colspan="3"></td></tr>
	<tr id="tailscale_routes_tr">
	<th width="30%" style="border-top: 0 none;">Local Subnet</th>
	<td colspan="4" style="border-top: 0 none;">
		<textarea maxlength="1024" class="input" name="tailscale_routes" id="tailscale_routes" placeholder="192.168.2.0/24,192.168.123.0/24" style="width: 210px; height: 20px; resize: both; overflow: auto;"><% nvram_get_x("","tailscale_routes"); %></textarea>
	<br>&nbsp;<span style="color:#888;">Advertise local subnet routes, use commas to separate multiple subnets</span>
	</td>
	</tr><tr id="tailscale_routes_td" ><td colspan="3"></td></tr>
	<tr id="tailscale_exit_tr" >
	<th style="border-top: 0 none;">Enable Exit Node</th>
	<td style="border-top: 0 none;">
	<div class="main_itoggle">
	<div id="tailscale_exit_on_of">
	<input type="checkbox" id="tailscale_exit_fake" <% nvram_match_x("", "tailscale_exit", "1", "value=1 checked"); %><% nvram_match_x("", "tailscale_exit", "0", "value=0"); %> />
	&nbsp;<span style="color:#888;">Make this device a traffic exit node</span></div>
	</div>
	<div style="position: absolute; margin-left: -10000px;">
		<input type="radio" value="1" name="tailscale_exit" id="tailscale_exit_1" class="input" value="1" <% nvram_match_x("", "tailscale_exit", "1", "checked"); %> /><#checkbox_Yes#>
		<input type="radio" value="0" name="tailscale_exit" id="tailscale_exit_0" class="input" value="0" <% nvram_match_x("", "tailscale_exit", "0", "checked"); %> /><#checkbox_No#>
	</div>
	</td>
	</tr><tr id="tailscale_exit_td" ><td colspan="3"></td></tr>
	<tr id="tailscale_exitip_tr">
	<th width="30%" style="border-top: 0 none;">Exit Node Address</th>
	<td style="border-top: 0 none;">
		<input type="text" maxlength="128" class="input" size="15" placeholder="" id="tailscale_exitip" name="tailscale_exitip" value="<% nvram_get_x("","tailscale_exitip"); %>" onKeyPress="return is_string(this,event);" />
	<br>&nbsp;<span style="color:#888;">Specify the node to use as traffic exit</span>
	</td>
	</tr><tr id="tailscale_exitip_td"><td colspan="3"></td></tr>
	<tr id="tailscale_server_tr">
	<th width="30%" style="border-top: 0 none;">Control Server Address</th>
	<td style="border-top: 0 none;">
		<input type="text" maxlength="256" class="input" size="15" placeholder="https://controlplane.tailscale.com" id="tailscale_server" name="tailscale_server" value="<% nvram_get_x("","tailscale_server"); %>" onKeyPress="return is_string(this,event);" />
	<br>&nbsp;<span style="color:#888;">Address of the control server. If you use Headscale as your control server, use your Headscale instance URL</span>
	</td>
	</tr><tr id="tailscale_server_td"><td colspan="3"></td></tr>
	<tr id="tailscale_ssh_tr" >
	<th style="border-top: 0 none;">Enable SSH Server</th>
	<td style="border-top: 0 none;">
	<div class="main_itoggle">
	<div id="tailscale_ssh_on_of">
	<input type="checkbox" id="tailscale_ssh_fake" <% nvram_match_x("", "tailscale_ssh", "1", "value=1 checked"); %><% nvram_match_x("", "tailscale_ssh", "0", "value=0"); %> />
	&nbsp;<span style="color:#888;">Run the Tailscale SSH server</span></div>
	</div>
	<div style="position: absolute; margin-left: -10000px;">
		<input type="radio" value="1" name="tailscale_ssh" id="tailscale_ssh_1" class="input" value="1" <% nvram_match_x("", "tailscale_ssh", "1", "checked"); %> /><#checkbox_Yes#>
		<input type="radio" value="0" name="tailscale_ssh" id="tailscale_ssh_0" class="input" value="0" <% nvram_match_x("", "tailscale_ssh", "0", "checked"); %> /><#checkbox_No#>
	</div>
	</td>
	</tr><tr id="tailscale_ssh_td" ><td colspan="3"></td></tr>
	<tr id="tailscale_shields_tr" >
	<th style="border-top: 0 none;">Outbound Connections Only</th>
	<td style="border-top: 0 none;">
	<div class="main_itoggle">
	<div id="tailscale_shields_on_of">
		<input type="checkbox" id="tailscale_shields_fake" <% nvram_match_x("", "tailscale_shields", "1", "value=1 checked"); %><% nvram_match_x("", "tailscale_shields", "0", "value=0"); %> />
	&nbsp;<span style="color:#888;">When enabled, blocks incoming connections from other devices on the Tailscale network. Useful for personal devices that only make outbound connections.</span></div>
	</div>
	<div style="position: absolute; margin-left: -10000px;">
		<input type="radio" value="1" name="tailscale_shields" id="tailscale_shields_1" class="input" value="1" <% nvram_match_x("", "tailscale_shields", "1", "checked"); %> /><#checkbox_Yes#>
		<input type="radio" value="0" name="tailscale_shields" id="tailscale_shields_0" class="input" value="0" <% nvram_match_x("", "tailscale_shields", "0", "checked"); %> /><#checkbox_No#>
	</div>
	</td>
	</tr><tr id="tailscale_shields_td" ><td colspan="3"></td></tr>
	<tr id="tailscale_host_tr">
	<th width="30%" style="border-top: 0 none;">Device Name</th>
	<td style="border-top: 0 none;">
		<input type="text" maxlength="50" class="input" size="15" placeholder="<% nvram_get_x("","computer_name"); %>" id="tailscale_host" name="tailscale_host" value="<% nvram_get_x("","tailscale_host"); %>" onKeyPress="return is_string(this,event);" />
	<br>&nbsp;<span style="color:#888;">Set this device's name to make it easier to identify</span>
	</td>
	</tr><tr id="tailscale_host_td"><td colspan="3"></td></tr>
	<tr id="tailscale_key_tr">
	<th width="30%" style="border-top: 0 none;">Auth Key</th>
	<td style="border-top: 0 none;">
		<textarea maxlength="1024" class="input" name="tailscale_key" id="tailscale_key" placeholder="" style="width: 210px; height: 20px; resize: both; overflow: auto;"><% nvram_get_x("","tailscale_key"); %></textarea>
	<br>&nbsp;<span style="color:#888;">Enter an auth key to automatically authenticate this node to your user account</span>
	</td>
	</tr><tr id="tailscale_key_td"><td colspan="3"></td></tr>
	<tr id="tailscale_reset_tr" >
	<th style="border-top: 0 none;">Reset to Defaults</th>
	<td style="border-top: 0 none;">
	<div class="main_itoggle">
	<div id="tailscale_reset_on_of">
	<input type="checkbox" id="tailscale_reset_fake" <% nvram_match_x("", "tailscale_reset", "1", "value=1 checked"); %><% nvram_match_x("", "tailscale_reset", "0", "value=0"); %> />
	&nbsp;<span style="color:#888;">Reset unused parameters to their default values</span></div>
	</div>
	<div style="position: absolute; margin-left: -10000px;">
		<input type="radio" value="1" name="tailscale_reset" id="tailscale_reset_1" class="input" value="1" <% nvram_match_x("", "tailscale_reset", "1", "checked"); %> /><#checkbox_Yes#>
		<input type="radio" value="0" name="tailscale_reset" id="tailscale_reset_0" class="input" value="0" <% nvram_match_x("", "tailscale_reset", "0", "checked"); %> /><#checkbox_No#>
	</div>
	</td>
	</tr><tr id="tailscale_reset_td" ><td colspan="3"></td></tr>
	<tr id="tailscale_cmd2_tr">
	<th width="30%" style="border-top: 0 none;">Extra Parameters
	</th>
	<td colspan="4" style="border-top: 0 none;">
	<textarea maxlength="1024" class="input" name="tailscale_cmd2" id="tailscale_cmd2" placeholder="--netfilter-mode --exit-node-allow-lan-access" style="width: 210px; height: 20px; resize: both; overflow: auto;"><% nvram_get_x("","tailscale_cmd2"); %></textarea>
	<br>&nbsp;<span style="color:#888;">Add any parameters missing from the options above</span>
	</td>
	</tr><tr id="tailscale_cmd2_td" ><td colspan="3"></td></tr>
	<tr>
	<th style="border: 0 none;">Program Path</th>
	<td style="border: 0 none;">
		<textarea maxlength="1024"class="input" name="tailscale_bin" id="tailscale_bin" placeholder="/etc/storage/bin/tailscaled" style="width: 210px; height: 20px; resize: both; overflow: auto;"><% nvram_get_x("","tailscale_bin"); %></textarea>
	</div><br><span style="color:#888;">Custom path to the main program, enter the full path and program name</span>
	</tr><td colspan="3"></td>
	<tr>
	<td colspan="4" style="border-top: 0 none;">
	<br />
	<center><input class="btn btn-primary" style="width: 219px" type="button" value="<#CTL_apply#>" onclick="applyRule()" /></center>
	</td>
	</tr>
	
	</table>
	</div>
	</div>
	</div>
	<div id="wnd_tailscale_log" style="display:none">
	<table width="100%" cellpadding="4" cellspacing="0" class="table">
	<tr>
	<td colspan="3" style="border-top: 0 none; padding-bottom: 0px;">
		<textarea rows="21" class="span12" style="height:377px; font-family:'Courier New', Courier, mono; font-size:13px;" readonly="readonly" wrap="off" id="textarea"><% nvram_dump("tailscale.log",""); %></textarea>
	</td>
	</tr>
	<tr>
	<td width="15%" style="text-align: left; padding-bottom: 0px;">
	<input type="button" onClick="location.reload()" value="Refresh Log" class="btn btn-primary" style="width: 200px">
	</td>
	<td width="75%" style="text-align: right; padding-bottom: 0px;">
	<input type="button" onClick="clearLog();" value="Clear Log" class="btn btn-info" style="width: 200px">
	</td>
	</tr>
	</table>
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

